#!/bin/bash
# Display Claude Code alerts for tmux status bar
# Shows windows with active Claude alerts (excludes current session)

ALERTS_FILE="$HOME/.claude/alerts"
CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null)

if [[ -f "$ALERTS_FILE" && -s "$ALERTS_FILE" ]]; then
    # Read unique alerts, excluding current session
    alerts=$(grep -v "^${CURRENT_SESSION}:" "$ALERTS_FILE" 2>/dev/null | sort -u | head -3 | tr '\n' ' ' | sed 's/ $//')
    count=$(grep -v "^${CURRENT_SESSION}:" "$ALERTS_FILE" 2>/dev/null | sort -u | wc -l | tr -d ' ')

    # Only show if there are alerts from other sessions
    if [[ $count -gt 0 && -n "$alerts" ]]; then
        if [[ $count -gt 3 ]]; then
            echo "#[fg=#f1fa8c,bold]⚡ ${alerts}+$((count-3))#[default] "
        else
            echo "#[fg=#f1fa8c,bold]⚡ ${alerts}#[default] "
        fi
    fi
fi
