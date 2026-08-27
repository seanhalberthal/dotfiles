#!/usr/bin/env bash
# preview-pane: capture a pane for an fzf preview, anchored to the bottom.
#   capture-pane emits one line per pane row including trailing blanks, and fzf
#   anchors previews to the top, so a full pane's most recent rows (statusline /
#   prompt) get clipped. strip the trailing blank rows then tail to the preview
#   window height ($FZF_PREVIEW_LINES) so the true bottom stays visible.
# kept dependency-free on purpose: this runs on every preview refresh (~1s).
# usage: preview-pane.sh <target-pane>
set -euo pipefail

target="${1:-}"
[[ -n "$target" ]] || exit 0

tmux capture-pane -ep -t "$target" 2>/dev/null |
    awk '{ a[NR] = $0; if ($0 ~ /[^[:space:]]/) last = NR }
           END { for (i = 1; i <= last; i++) print a[i] }' |
    tail -n "${FZF_PREVIEW_LINES:-40}"
