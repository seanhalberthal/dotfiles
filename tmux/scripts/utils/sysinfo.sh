#!/usr/bin/env bash
# cached battery/cpu/ram segment for the tmux status bar.
#
# status-interval is 1 so the clock ticks every second, but re-running the
# tmux-battery/tmux-cpu plugin scripts every second spawns hundreds of
# processes per minute (battery_color_charge.sh alone reads ~22 tmux options,
# one exec each). this wrapper calls the stock plugin scripts at most once
# per TTL and serves the assembled segment from a cache in between, so the
# plugins stay unpatched upstream clones.
#
# cache format: line 1 = epoch written, line 2 = payload.
# TTL override: DOTFILES_SYSINFO_TTL (seconds, default 5)

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
CACHE_FILE="$CACHE_DIR/tmux-sysinfo"
TTL="${DOTFILES_SYSINFO_TTL:-5}"

now="${EPOCHSECONDS:-$(date +%s)}"

# hot path: serve the cached segment with bash builtins only, no forks
if [[ -f "$CACHE_FILE" ]]; then
    { IFS= read -r cache_ts && IFS= read -r cache_payload; } <"$CACHE_FILE" 2>/dev/null ||
        {
            cache_ts=0
            cache_payload=""
        }
    if [[ "$cache_ts" =~ ^[0-9]+$ ]] && ((now - cache_ts < TTL)); then
        printf '%s' "$cache_payload"
        exit 0
    fi
fi

# cache miss: locate the stock TPM plugins
plugin_root=""
for root in "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins" "$HOME/.tmux/plugins"; do
    if [[ -d "$root/tmux-battery" && -d "$root/tmux-cpu" ]]; then
        plugin_root="$root"
        break
    fi
done
[[ -n "$plugin_root" ]] || exit 0

# icons and colour come from @sysinfo_* options (set in tmux.conf). they are
# not passed as #() arguments because tmux format-expands #() content, which
# would mangle "#rrggbb" colour values
fg="" cpu_icon="" ram_icon=""
while IFS= read -r opt; do
    case "$opt" in
        '@sysinfo_fg '*) fg="${opt#'@sysinfo_fg '}" ;;
        '@sysinfo_cpu_icon '*) cpu_icon="${opt#'@sysinfo_cpu_icon '}" ;;
        '@sysinfo_ram_icon '*) ram_icon="${opt#'@sysinfo_ram_icon '}" ;;
    esac
done < <(tmux show-options -g 2>/dev/null)
fg="${fg%\"}"
fg="${fg#\"}"
cpu_icon="${cpu_icon%\"}"
cpu_icon="${cpu_icon#\"}"
ram_icon="${ram_icon%\"}"
ram_icon="${ram_icon#\"}"

battery_scripts="$plugin_root/tmux-battery/scripts"
cpu_scripts="$plugin_root/tmux-cpu/scripts"

# tmux-battery has no "no battery" case of its own: on machines with no
# battery (desktops, most SBCs) upower only exposes the synthetic
# DisplayDevice, so the plugin reports an "unknown" status and 0% instead of
# nothing. Detect real battery hardware ourselves and skip the segment
# entirely when there isn't any.
has_battery() {
    if command -v pmset >/dev/null 2>&1; then
        pmset -g batt 2>/dev/null | grep -q "No batteries available" && return 1
        return 0
    else
        compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1
    fi
}

battery_segment=""
if has_battery; then
    batt_bg=$("$battery_scripts/battery_color_charge.sh" bg 2>/dev/null) || batt_bg=""
    batt_icon=$("$battery_scripts/battery_icon_status.sh" 2>/dev/null) || batt_icon=""
    batt_pct=$("$battery_scripts/battery_percentage.sh" 2>/dev/null) || batt_pct=""
    battery_segment="${batt_bg}#[fg=${fg}] ${batt_icon} ${batt_pct} "
fi

cpu_bg=$("$cpu_scripts/cpu_bg_color.sh" 2>/dev/null) || cpu_bg=""
cpu_pct=$("$cpu_scripts/cpu_percentage.sh" 2>/dev/null) || cpu_pct=""
ram_bg=$("$cpu_scripts/ram_bg_color.sh" 2>/dev/null) || ram_bg=""
ram_pct=$("$cpu_scripts/ram_percentage.sh" 2>/dev/null) || ram_pct=""

# mirrors the segment layout previously inlined in status-right
payload="${battery_segment}${cpu_bg}#[fg=${fg}] ${cpu_icon} ${cpu_pct} ${ram_bg}#[fg=${fg}] ${ram_icon} ${ram_pct} "

mkdir -p "$CACHE_DIR"
printf '%s\n%s\n' "$now" "$payload" >"$CACHE_FILE"
printf '%s' "$payload"
