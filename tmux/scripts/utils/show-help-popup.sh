#!/usr/bin/env bash
set -euo pipefail

# pick a popup size matching whichever help template will fit, then launch
# the help popup. the actual template choice happens inside show-help.sh
# via `stty size`; this wrapper just makes sure the popup itself isn't
# wildly larger than its content.
#
#   wide + tall  → -w 74 -h 40   (full 37-row template)
#   wide + short → -w 74 -h 24   (compact 21-row template + chrome)
#   narrow       → -w 95% -h 24  (compact, fit-to-width)
#   tiny         → -w 95% -h 95% (last-resort, content may scroll)
#
# dimensions are passed in by the tmux binding via `#{client_width}` and
# `#{client_height}` format strings; querying via `tmux display-message`
# from inside run-shell occasionally returned 129/SIGHUP

SCRIPT_DIR="${BASH_SOURCE%/*}"

client_width="${1:-80}"
client_height="${2:-40}"

if ((client_width >= 80 && client_height >= 40)); then
    width=74
    height=40
elif ((client_width >= 76 && client_height >= 24)); then
    width=74
    height=24
elif ((client_height >= 24)); then
    width="95%"
    height=24
else
    width="95%"
    height="95%"
fi

tmux display-popup -w "$width" -h "$height" \
    "$SCRIPT_DIR/show-help.sh; read -sk1" || true

exit 0
