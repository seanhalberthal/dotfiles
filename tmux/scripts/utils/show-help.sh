#!/usr/bin/env bash
set -euo pipefail

# display tmux help with platform-appropriate modifier key names
# macOS shows "Opt", Linux shows "Alt"
#
# the full template is 37 rows tall. when the popup pty is shorter than that
# (small terminal, or display-popup -h clamped to terminal height), fall back
# to the compact 21-row template so the bottom doesn't get clipped

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

MOD=$(mod_key)

popup_height=40
read -r popup_height _ < <(stty size 2>/dev/null) || true

if ((popup_height < 38)); then
    TEMPLATE="$SCRIPT_DIR/../../tmux-help-compact.template"
else
    TEMPLATE="$SCRIPT_DIR/../../tmux-help.template"
fi

sed "s/{{M}}/$MOD/g" "$TEMPLATE"
