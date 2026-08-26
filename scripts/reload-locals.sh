#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# reload all local override files across tmux, Ghostty, and nvim
# safe to run at any time; tmux and nvim are reloaded non-destructively
#
# usage: reload-locals.sh

SCRIPT_DIR="${BASH_SOURCE%/*}"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─────────────────────────────────────────
# tmux
# ─────────────────────────────────────────
if [[ -n "${TMUX:-}" ]]; then
    tmux source-file "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    tmux_msg="tmux: reloaded"
else
    tmux_msg="tmux: skipped"
fi

# ─────────────────────────────────────────
# Ghostty
# ─────────────────────────────────────────
"$DOTFILES_DIR/tmux/scripts/themes/reload-ghostty.sh"
ghostty_msg="ghostty: reloaded"

# ─────────────────────────────────────────
# nvim
# ─────────────────────────────────────────
# $TMPDIR may not be set in non-login shells (e.g. tmux run-shell)
tmpdir="${TMPDIR:-$(python3 -c 'import tempfile; print(tempfile.gettempdir())' 2>/dev/null || echo /tmp)}"
tmpdir="${tmpdir%/}/"
reloaded=0

while IFS= read -r socket; do
    [[ -z "$socket" ]] && continue
    nvim --server "$socket" --remote-expr \
        'execute("source ~/.config/nvim/local.lua")' \
        2>/dev/null && ((reloaded++)) || true
done < <(find "${tmpdir}nvim.${USER:-$(id -un)}" -type s -name "nvim.*" 2>/dev/null || true)

nvim_msg="nvim: ${reloaded} instance(s) reloaded"

# ─────────────────────────────────────────
# output
# ─────────────────────────────────────────
summary="${tmux_msg} | ${ghostty_msg} | ${nvim_msg}"

if [[ -n "${TMUX:-}" ]]; then
    tmux display-message -d 3000 "$summary"
else
    printf '%s\n' "$summary"
fi
