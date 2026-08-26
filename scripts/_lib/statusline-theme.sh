#!/usr/bin/env bash
# dotfiles statusline theme resolver.
#
# source this from the statusline command of an AI CLI coding agent (anything
# that runs a script to render its statusline: Claude Code, GitHub Copilot CLI,
# Antigravity CLI) to colour it from the active `dotfiles theme`. it reads the
# current theme's palette and sets a set of SL_* variables holding ANSI
# truecolour foreground escapes, so the statusline follows `dotfiles theme
# switch` automatically.
#
# if the active theme can't be resolved (no theme set, file missing, not a
# dotfiles checkout) it sets nothing; callers should keep their own defaults
# behind `${SL_*:-<fallback>}`, so sourcing this is always safe:
#
#   source ~/.config/dotfiles/statusline-theme.sh
#   COL_MODEL="${SL_MODEL:-$'\033[38;2;255;121;198m'}"
#   COL_BRANCH="${SL_BRANCH:-$'\033[38;2;139;233;253m'}"
#
# Variables set (each an ANSI fg escape, mapped from the theme palette):
#   SL_MODEL SL_DIR SL_BRANCH SL_TIME SL_REMAINING SL_CONTEXT
#   SL_STAGED SL_MODIFIED SL_DELETED SL_UNTRACKED
#   SL_LINES_ADD SL_LINES_DEL SL_SEP SL_BRACKET SL_WARNING
# The raw theme hexes are also exposed as SL_HEX_* for custom mapping.
#
# role colours (model, dir, branch, time, context, separators) follow the theme
# palette directly. the semantic roles that carry universal add/delete/modify/
# warn meaning (SL_STAGED, SL_LINES_ADD, SL_MODIFIED, SL_DELETED, SL_LINES_DEL,
# SL_WARNING) are hue-locked: they keep the theme's brightness/saturation but are
# pinned to a green/red/amber hue, so the git +/- diff and status markers always
# read correctly even under a theme whose "green" slot is teal or grey, or whose
# "red" is a washed-out pink

# resolve everything in a function so the only thing that leaks into the caller
# is the SL_* result set (helpers are unset at the end)
__sl_theme_resolve() {
    local self real root config_dir name theme_file

    # 1. locate the dotfiles checkout. prefer an explicit env, else walk up from
    #    this file's real path (works through the ~/.config/dotfiles symlink)
    root="${DOTFILES_DIR:-${DOTFILES_ROOT:-}}"
    if [[ -z "$root" || ! -d "$root/themes" ]]; then
        self="${BASH_SOURCE[0]}"
        real="$(readlink -f "$self" 2>/dev/null || realpath "$self" 2>/dev/null || echo "$self")"
        root="$(cd "$(dirname "$real")/../.." 2>/dev/null && pwd)"
    fi
    [[ -n "$root" && -d "$root/themes" ]] || return 0

    # 2. read the active theme name (sanitised, used in a path)
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
    [[ -r "$config_dir/current-theme" ]] || return 0
    name="$(<"$config_dir/current-theme")"
    name="${name//[^a-zA-Z0-9._-]/}"
    [[ -n "$name" ]] || return 0

    # 3. locate the theme file (hand-crafted, then generated)
    if [[ -f "$root/themes/$name.theme" ]]; then
        theme_file="$root/themes/$name.theme"
    elif [[ -f "$root/themes/generated/$name.theme" ]]; then
        theme_file="$root/themes/generated/$name.theme"
    else
        return 0
    fi

    # pull a literal `VAR="#rrggbb"` assignment without executing the theme file
    # (hand-crafted themes call shell functions we don't want to run here)
    __sl_var() {
        sed -n "s/^$1=\"\(#[0-9a-fA-F]\{6\}\)\".*/\1/p" "$theme_file" | head -1
    }

    local fg fg_dim bg purple pink cyan green yellow red
    fg="$(__sl_var TMUX_FG_PRIMARY)"
    fg_dim="$(__sl_var TMUX_FG_SECONDARY)"
    bg="$(__sl_var TMUX_BG_PRIMARY)"
    purple="$(__sl_var TMUX_ACCENT_PURPLE)"
    pink="$(__sl_var TMUX_ACCENT_PINK)"
    cyan="$(__sl_var TMUX_ACCENT_CYAN)"
    green="$(__sl_var TMUX_ACCENT_GREEN)"
    yellow="$(__sl_var TMUX_ACCENT_YELLOW)"
    red="$(__sl_var TMUX_ACCENT_RED)"

    # bail unless the essentials parsed, keeps callers on their own defaults
    [[ -n "$fg" && -n "$bg" && -n "$pink" && -n "$cyan" && -n "$green" && -n "$red" ]] || return 0
    : "${fg_dim:=$fg}" "${purple:=$pink}" "${yellow:=$red}"

    # hex -> ANSI 24-bit fg escape (real ESC byte via printf)
    __sl_fg() {
        local h="${1#\#}"
        printf '\033[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
    }
    # blend hex1 towards hex2 by pct (0-100) -> hex
    __sl_blend() {
        local a="${1#\#}" b="${2#\#}" p="$3" inv=$((100 - $3))
        printf '#%02x%02x%02x' \
            $(((16#${a:0:2} * inv + 16#${b:0:2} * p) / 100)) \
            $(((16#${a:2:2} * inv + 16#${b:2:2} * p) / 100)) \
            $(((16#${a:4:2} * inv + 16#${b:4:2} * p) / 100))
    }
    # pin a hex onto a semantic hue band while keeping the theme's own lightness
    # and saturation -> hex. converts to HSL, clamps the hue into [lo,hi] (the
    # band may run past 360 for red), enforces a saturation floor (rescues a grey
    # accent) and a lightness window (rescues a washed-out or too-dark accent),
    # then converts back. args: hex, hue-centre (used for greys with no hue),
    # band-lo, band-hi (degrees), sat-floor, light-lo, light-hi (each 0-100)
    __sl_huelock() {
        local h="${1#\#}"
        awk -v r="$((16#${h:0:2}))" -v g="$((16#${h:2:2}))" -v b="$((16#${h:4:2}))" \
            -v hc="$2" -v lo="$3" -v hi="$4" -v sf="$5" -v llo="$6" -v lhi="$7" '
        function cl(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }
        function h2(p, q, t) {
            if (t < 0) t += 1; if (t > 1) t -= 1
            if (t < 1/6) return p + (q - p) * 6 * t
            if (t < 1/2) return q
            if (t < 2/3) return p + (q - p) * (2/3 - t) * 6
            return p
        }
        BEGIN {
            r /= 255; g /= 255; b /= 255
            mx = r; if (g > mx) mx = g; if (b > mx) mx = b
            mn = r; if (g < mn) mn = g; if (b < mn) mn = b
            L = (mx + mn) / 2; d = mx - mn
            if (d == 0) { H = hc; S = 0 }      # grey: no hue, take the band centre
            else {
                S = (L > 0.5) ? d / (2 - mx - mn) : d / (mx + mn)
                if (mx == r)      H = (g - b) / d + (g < b ? 6 : 0)
                else if (mx == g) H = (b - r) / d + 2
                else              H = (r - g) / d + 4
                H *= 60
            }
            if (hi > 360 && H < 180) H += 360  # fold low hues into a wrapped band
            if (H < lo) H = lo; if (H > hi) H = hi
            if (H >= 360) H -= 360
            sf /= 100; llo /= 100; lhi /= 100
            if (S < sf) S = sf
            if (L < llo) L = llo; if (L > lhi) L = lhi
            if (S == 0) { R = L; G = L; B = L }
            else {
                q = (L < 0.5) ? L * (1 + S) : L + S - L * S
                p = 2 * L - q
                R = h2(p, q, H/360 + 1/3); G = h2(p, q, H/360); B = h2(p, q, H/360 - 1/3)
            }
            printf "#%02x%02x%02x", int(cl(R) * 255 + 0.5), int(cl(G) * 255 + 0.5), int(cl(B) * 255 + 0.5)
        }'
    }

    # semantic tones, hue-locked so add/delete/modify/warn always read correctly
    # regardless of how far a theme's accent strays from a true green/red/amber.
    # each keeps the source slot's brightness/saturation but is pinned to its hue
    # band: green (add/staged), red (delete/deleted), orange (modified, a warmer
    # cut of yellow), amber (warning). the separator stays a plain dim blend
    local c_green c_red c_orange c_amber sep
    c_green="$(__sl_huelock "$green" 127 100 150 45 45 68)"
    c_red="$(__sl_huelock "$red" 360 350 372 55 45 66)"
    c_orange="$(__sl_huelock "$yellow" 30 22 38 55 48 66)"
    c_amber="$(__sl_huelock "$yellow" 46 40 52 55 50 70)"
    sep="$(__sl_blend "$fg_dim" "$bg" 55)"

    # theme-driven role colours: follow the palette directly so the statusline
    # still reflects the active theme
    SL_MODEL="$(__sl_fg "$pink")"
    SL_DIR="$(__sl_fg "$fg")"
    SL_BRANCH="$(__sl_fg "$cyan")"
    SL_TIME="$(__sl_fg "$yellow")"
    SL_REMAINING="$(__sl_fg "$fg")"
    SL_CONTEXT="$(__sl_fg "$purple")"
    SL_UNTRACKED="$(__sl_fg "$fg_dim")"
    SL_SEP="$(__sl_fg "$sep")"
    SL_BRACKET="$(__sl_fg "$fg_dim")"

    # semantic role colours: hue-locked, so the git +/- diff, the status markers
    # and the context-pressure indicator always carry the add/delete/warn cue
    SL_STAGED="$(__sl_fg "$c_green")"
    SL_LINES_ADD="$(__sl_fg "$c_green")"
    SL_MODIFIED="$(__sl_fg "$c_orange")"
    SL_DELETED="$(__sl_fg "$c_red")"
    SL_LINES_DEL="$(__sl_fg "$c_red")"
    SL_WARNING="$(__sl_fg "$c_amber")"

    # raw hexes for callers that want to map their own roles
    SL_HEX_FG="$fg" SL_HEX_FG_DIM="$fg_dim" SL_HEX_BG="$bg"
    SL_HEX_PURPLE="$purple" SL_HEX_PINK="$pink" SL_HEX_CYAN="$cyan"
    SL_HEX_GREEN="$green" SL_HEX_YELLOW="$yellow" SL_HEX_RED="$red"
}

__sl_theme_resolve
unset -f __sl_theme_resolve __sl_var __sl_fg __sl_blend __sl_huelock 2>/dev/null
