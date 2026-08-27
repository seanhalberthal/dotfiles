#!/usr/bin/env bash
# list tmux windows sorted by last viewed (most recent first)
# used by the window switcher (prefix + f)
# shows agent-specific indicators for windows with alerts
#
# usage: list.sh [--all]
#   --all: list windows from all sessions (default: current session only)

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"
# shellcheck source=tmux/scripts/_lib/alerts.sh
source "$SCRIPT_DIR/../_lib/alerts.sh"

load_fzf_theme
print_dotfiles_logo

# pre-read alerts file once (avoids per-window tmux calls)
_all_alerts=""
[[ -f "$ALERTS_FILE" ]] && _all_alerts=$(<"$ALERTS_FILE")

# get windows sorted by last-viewed, then add alert indicator
FORMAT='#{?#{@last-viewed},#{@last-viewed},0} #{session_name}:#{window_index} #{window_name}'
if [[ "$1" == "--all" ]]; then
    tmux list-windows -a -F "$FORMAT"
else
    tmux list-windows -F "$FORMAT"
fi | sort -rn | cut -d' ' -f2- | while read -r display_line; do
    # display_line: "session:window_index window_name"
    # extract session and window_name for alerts file lookup
    local_target="${display_line%% *}"  # session:window_index
    local_session="${local_target%%:*}" # session
    local_window="${display_line#* }"   # window_name

    # window names are stored percent-encoded in the alerts file
    icons=$(build_alert_icons "$_all_alerts" "^${local_session}:$(alerts_encode_window "$local_window"):")

    if [[ -n "$icons" ]]; then
        printf "%s %b\n" "$display_line" "${icons}"
    else
        echo "$display_line"
    fi
done
