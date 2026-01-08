#!/bin/bash
# Update the @last-viewed timestamp for the current window
TIMESTAMP=$(date +%s)
WINDOW_ID="$1"
tmux set-option -wt "$WINDOW_ID" @last-viewed "$TIMESTAMP"
