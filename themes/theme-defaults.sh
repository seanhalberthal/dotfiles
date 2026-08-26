# shellcheck shell=bash
# theme defaults and shared logic
# this file is sourced by individual theme files to set up common patterns

# this function should be called after setting base colours and accents
apply_theme_defaults() {
    # determine which accent to use for active elements (default: purple)
    local active_accent="${THEME_ACTIVE_ACCENT:-purple}"

    # ══════════════════════════════════════════════════════════════
    # status bar: standard patterns across all themes
    # ══════════════════════════════════════════════════════════════
    TMUX_STATUS_BG="$TMUX_BG_PRIMARY"
    TMUX_STATUS_FG="$TMUX_FG_PRIMARY"
    TMUX_STATUS_INACTIVE_FG="$TMUX_FG_SECONDARY"

    # active window colour uses the theme's chosen accent
    # TMUX_STATUS_BELL_FG can be overridden in the theme file; only set here if not already defined
    case "$active_accent" in
        cyan)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_CYAN"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_CYAN}"
            ;;
        purple)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_PURPLE"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_PURPLE}"
            ;;
        pink)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_PINK"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_PINK}"
            ;;
        green)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_GREEN"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_GREEN}"
            ;;
        yellow)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_YELLOW"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_YELLOW}"
            ;;
        red)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_RED"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_RED}"
            ;;
        *)
            TMUX_STATUS_ACTIVE_BG="$TMUX_ACCENT_PURPLE"
            TMUX_STATUS_BELL_FG="${TMUX_STATUS_BELL_FG:-$TMUX_ACCENT_PURPLE}"
            ;;
    esac
    TMUX_STATUS_ACTIVE_FG="$TMUX_BG_PRIMARY"

    # ══════════════════════════════════════════════════════════════
    # command exit alert colours: use theme accent green/red
    # can be overridden per-theme if needed
    # ══════════════════════════════════════════════════════════════
    TMUX_EXIT_PASS_COLOUR="${TMUX_EXIT_PASS_COLOUR:-$TMUX_ACCENT_GREEN}"
    TMUX_EXIT_FAIL_COLOUR="${TMUX_EXIT_FAIL_COLOUR:-$TMUX_ACCENT_RED}"

    # ══════════════════════════════════════════════════════════════
    # pane borders: active border matches active window
    # ══════════════════════════════════════════════════════════════
    TMUX_PANE_BORDER_INACTIVE="$TMUX_BG_SECONDARY"
    TMUX_PANE_BORDER_ACTIVE="$TMUX_STATUS_ACTIVE_BG"

    # ══════════════════════════════════════════════════════════════
    # message/command bar: uses active accent
    # ══════════════════════════════════════════════════════════════
    TMUX_MESSAGE_BG="$TMUX_STATUS_ACTIVE_BG"
    TMUX_MESSAGE_FG="$TMUX_BG_PRIMARY"
    TMUX_MESSAGE_COMMAND_BG="$TMUX_FG_SECONDARY"
    TMUX_MESSAGE_COMMAND_FG="$TMUX_FG_PRIMARY"

    # ══════════════════════════════════════════════════════════════
    # FZF colours: standard pattern across all themes
    # ══════════════════════════════════════════════════════════════
    FZF_BG="$TMUX_BG_PRIMARY"
    FZF_FG="$TMUX_FG_PRIMARY"
    FZF_BG_PLUS="$TMUX_BG_SECONDARY"       # current line background
    FZF_FG_PLUS="$TMUX_FG_PRIMARY"         # current line foreground
    FZF_HL="$TMUX_STATUS_ACTIVE_BG"        # highlighted substrings (uses active accent)
    FZF_HL_PLUS="$TMUX_STATUS_ACTIVE_BG"   # highlighted substrings (current line, uses active accent)
    FZF_BORDER="$TMUX_STATUS_ACTIVE_BG"    # border (uses active accent)
    FZF_PROMPT="$TMUX_STATUS_ACTIVE_BG"    # prompt (uses active accent)
    FZF_POINTER="$TMUX_STATUS_ACTIVE_BG"   # pointer (uses active accent)
    FZF_MARKER="$TMUX_ACCENT_GREEN"        # multi-select marker
    FZF_SPINNER="$TMUX_ACCENT_YELLOW"      # streaming input indicator
    FZF_HEADER="$TMUX_STATUS_ACTIVE_BG"    # header (uses active accent)
    FZF_INFO="$TMUX_FG_SECONDARY"          # info line
    FZF_SEPARATOR="$TMUX_FG_SECONDARY"     # border separator
    FZF_SCROLLBAR="$TMUX_STATUS_ACTIVE_BG" # scrollbar (uses active accent)
    FZF_LABEL="$TMUX_FG_PRIMARY"           # border label
    FZF_PREVIEW_BG="$TMUX_BG_PRIMARY"      # preview window background
    FZF_PREVIEW_FG="$TMUX_FG_PRIMARY"      # preview window foreground
}
