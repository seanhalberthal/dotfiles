#!/usr/bin/env bash
# codex hook script: clear tmux alert when user sends a message
# wrapper around agent-alert-clear.sh

# skip when running as ACP subprocess inside nvim (e.g. codecompanion.nvim)
[[ -n "${NVIM:-}" ]] && exit 0

SCRIPT_DIR="${BASH_SOURCE%/*}/.."
"$SCRIPT_DIR/agent-alert-clear.sh" codex
