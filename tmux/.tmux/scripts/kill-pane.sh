#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# kill-pane.sh
# ══════════════════════════════════════════════════════════════
# Kills the current pane, but saves its state for undo.
# If it's the last pane in the last window of a session, switches
# to another session first to avoid detaching the client.
#
# Usage: kill-pane.sh
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# Get current state
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#{window_index}')
CURRENT_PANE=$(tmux display-message -p '#{pane_index}')
PANE_COUNT=$(tmux list-panes | wc -l | tr -d ' ')
WINDOW_COUNT=$(tmux list-windows | wc -l | tr -d ' ')

# Undo file locations
UNDO_FILE="/tmp/tmux-undo-pane"
UNDO_STATE="/tmp/tmux-undo-pane-state.txt"
UNDO_CONTENT="/tmp/tmux-undo-pane-content.txt"

# Clear previous undo data
rm -f "$UNDO_FILE" "$UNDO_STATE" "$UNDO_CONTENT"

# Save pane info for undo
PANE_DIR=$(tmux display-message -p '#{pane_current_path}')
PANE_ACTIVE=$(tmux display-message -p '#{pane_active}')
WINDOW_LAYOUT=$(tmux display-message -p '#{window_layout}')

# Save state
cat > "$UNDO_STATE" << EOF
SESSION=${CURRENT_SESSION}
WINDOW=${CURRENT_WINDOW}
PANE=${CURRENT_PANE}
DIR=${PANE_DIR}
LAYOUT=${WINDOW_LAYOUT}
PANE_COUNT=${PANE_COUNT}
EOF

# Save pane target for undo
echo "${CURRENT_SESSION}:${CURRENT_WINDOW}.${CURRENT_PANE}" > "$UNDO_FILE"

# Capture pane contents (full scrollback)
tmux capture-pane -p -S - > "$UNDO_CONTENT" 2>/dev/null || true

# Check if this is the last pane in the last window
if [[ "$PANE_COUNT" -eq 1 && "$WINDOW_COUNT" -eq 1 ]]; then
    # Find another session to switch to (most recently used)
    OTHER_SESSION=$(tmux list-sessions -F '#{session_activity} #{session_name}' | \
        sort -rn | cut -d' ' -f2- | grep -v "^${CURRENT_SESSION}$" | head -n1)

    if [[ -n "$OTHER_SESSION" ]]; then
        tmux switch-client -t "$OTHER_SESSION"
    fi
fi

# Kill the pane (this will close window/session if it was the last)
tmux kill-pane
