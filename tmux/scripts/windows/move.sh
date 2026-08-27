#!/usr/bin/env bash
# move a tmux window to a different session
# usage: move.sh <session:window_index>

SCRIPT_DIR="${BASH_SOURCE%/*}"
source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/alerts.sh"

# load current theme colours for fzf
load_fzf_theme

if [[ -z "$1" ]]; then
    error "No window specified"
    exit 1
fi

SOURCE_WINDOW="$1"

# validate input contains colon separator (session:window format)
if [[ ! "$SOURCE_WINDOW" =~ : ]]; then
    error "Invalid format: expected 'session:window_index' (e.g., 'main:1')"
    exit 1
fi

SOURCE_SESSION="${SOURCE_WINDOW%%:*}"
WINDOW_INDEX="${SOURCE_WINDOW##*:}"

# remove any trailing indicators (⚡, 󱜙, etc.) from the window identifier
SOURCE_SESSION="${SOURCE_SESSION%% *}"
WINDOW_INDEX="${WINDOW_INDEX%% *}"

# get the window name for display purposes
WINDOW_NAME=$(tmux display-message -p -t "${SOURCE_SESSION}:${WINDOW_INDEX}" '#{window_name}' 2>/dev/null)

if [[ -z "$WINDOW_NAME" ]]; then
    error "Window ${SOURCE_WINDOW} not found"
    exit 1
fi

# get list of sessions excluding the source session
TARGET_SESSION=$(tmux list-sessions -F '#{session_name}' |
    grep -v "^${SOURCE_SESSION}$" |
    fzf --height=100% --layout=reverse --exact --cycle --disabled \
        --prompt ': ' \
        --border=rounded \
        --border-label=" Move window '${WINDOW_NAME}' from '${SOURCE_SESSION}' to: " \
        --border-label-pos=top \
        --no-info \
        --pointer='▌' \
        --bind 'j:down,k:up,g:first,G:last,q:abort,space:accept' \
        --bind 'enter:accept' \
        --bind 'change:transform:[[ $FZF_PROMPT == ": " ]] && echo "clear-query"' \
        --bind '/:enable-search+change-prompt(> )+unbind(j,k,g,G,q,space)' \
        --bind 'esc:transform:[[ $FZF_PROMPT == "> " ]] && echo "disable-search+clear-query+change-prompt(: )+rebind(j,k,g,G,q,space)" || echo "abort"')

if [[ -z "$TARGET_SESSION" ]]; then
    exit 0 # user cancelled
fi

# move the window to the target session
tmux move-window -s "${SOURCE_SESSION}:${WINDOW_INDEX}" -t "${TARGET_SESSION}:"

# renumber remaining windows in the source session to fill the gap left behind
tmux move-window -r -s "$SOURCE_SESSION" 2>/dev/null

# update alert tracking: replace source session name with target in the alerts file.
# tmux window options (@*_alert) travel with the window automatically; only the
# flat file needs updating. handles both 3-field and 5-field alert formats.
# window names are stored percent-encoded, so encode before matching
ENC_WINDOW_NAME=$(alerts_encode_window "$WINDOW_NAME")
if [[ -f "$ALERTS_FILE" ]] && grep -qF "${SOURCE_SESSION}:${ENC_WINDOW_NAME}:" "$ALERTS_FILE" 2>/dev/null; then
    if _acquire_alerts_lock; then
        tmp_file=$(mktemp "${ALERTS_FILE}.tmp.XXXXXX")
        if sed "s|^${SOURCE_SESSION}:${ENC_WINDOW_NAME}:|${TARGET_SESSION}:${ENC_WINDOW_NAME}:|" "$ALERTS_FILE" >"$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$ALERTS_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
        else
            rm -f "$tmp_file" 2>/dev/null
        fi
        _release_alerts_lock
    fi
fi

success "Moved window '${WINDOW_NAME}' from '${SOURCE_SESSION}' to '${TARGET_SESSION}'"
