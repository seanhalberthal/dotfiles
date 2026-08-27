#!/usr/bin/env bash
# codex alert wrapper
# triggers tmux window alerts when codex completes work

# skip when running as ACP subprocess inside nvim (e.g. codecompanion.nvim)
[[ -n "${NVIM:-}" ]] && exit 0

SCRIPT_DIR="${BASH_SOURCE%/*}/.."
"$SCRIPT_DIR/agent-alert.sh" codex
