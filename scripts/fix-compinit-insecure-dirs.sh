#!/usr/bin/env bash
# clear zsh's "compinit: insecure directories" prompt by removing the group/other
# write bit from whatever compaudit flags.
#
# homebrew installs its share dir group-writable (775). on macOS that dir is
# group-owned by a shared group (admin/staff), so compinit's audit flags it and
# prompts on the daily full-compinit path. on linux each user gets a private
# single-member group, so the same bit is owner-only and compaudit stays clean:
# this script is a no-op there. it only ever chmods paths the current user owns,
# so anything root-owned is reported for a manual sudo fix rather than touched.
#
# usage:
#   ./fix-compinit-insecure-dirs.sh [--dry-run]

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

zsh_bin="$(command -v zsh || true)"
if [[ -z "$zsh_bin" ]]; then
  echo "zsh not found on PATH; nothing to audit" >&2
  exit 0
fi

audit() {
  "$zsh_bin" -fc 'autoload -Uz compaudit; compaudit' 2>/dev/null || true
}

insecure="$(audit)"
if [[ -z "$insecure" ]]; then
  echo "compaudit clean; completion dirs already secure"
  exit 0
fi

skipped=0
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if [[ ! -O "$path" ]]; then
    echo "SKIP (not owner, needs sudo): $path" >&2
    skipped=$((skipped + 1))
    continue
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would chmod go-w: $path"
  else
    echo "chmod go-w: $path"
    chmod go-w "$path"
  fi
done <<< "$insecure"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run: no changes made"
  exit 0
fi

# force a clean dump rebuild so the next shell doesn't reuse a stale one
rm -f "${HOME}/.zcompdump" "${HOME}"/.zcompdump.* 2>/dev/null || true

remaining="$(audit)"
if [[ -n "$remaining" ]]; then
  echo "still insecure (fix manually, likely root-owned):" >&2
  echo "$remaining" >&2
  echo "  e.g. sudo chmod go-w <path>" >&2
  exit 1
fi

echo "done; open a new shell to clear the compinit prompt"
[[ $skipped -gt 0 ]] && echo "note: $skipped path(s) skipped (not owner)"
exit 0
