#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# Duplicate Launcher
# ══════════════════════════════════════════════════════════════
# copies a launcher to USER_LAUNCHERS with a "-copy" suffix.
# successive duplicates get "-copy-2", "-copy-3", etc.
#
# Usage: duplicate.sh <launcher_name>

SCRIPT_DIR="${BASH_SOURCE%/*}"

# shellcheck source=tmux/scripts/_lib/common.sh
source "$SCRIPT_DIR/../_lib/common.sh"

name="${1:-}"
[[ -n "$name" ]] || exit 0

# prevent path traversal
name=$(basename "$name")
if [[ "$name" == *"/"* ]] || [[ "$name" == "." ]] || [[ "$name" == ".." ]]; then
    exit 1
fi

# resolve source file (user launchers take priority)
source_file=""
if [[ -f "$USER_LAUNCHERS/$name" ]]; then
    source_file="$USER_LAUNCHERS/$name"
elif [[ -f "$DOTFILES_LAUNCHERS/$name" ]]; then
    source_file="$DOTFILES_LAUNCHERS/$name"
else
    exit 1
fi

# generate unique copy name: name-copy, name-copy-2, name-copy-3, ...
# strip any existing "-copy" or "-copy-N" suffix first so duplicating a copy
# still bases the numbering on the original name
base_name="$name"
base_name=$(printf '%s' "$base_name" | sed -E 's/-copy(-[0-9]+)?$//')

copy_name="${base_name}-copy"
if [[ -f "$USER_LAUNCHERS/$copy_name" ]] || [[ -f "$DOTFILES_LAUNCHERS/$copy_name" ]]; then
    n=2
    while [[ -f "$USER_LAUNCHERS/${base_name}-copy-${n}" ]] ||
        [[ -f "$DOTFILES_LAUNCHERS/${base_name}-copy-${n}" ]]; do
        ((n++))
    done
    copy_name="${base_name}-copy-${n}"
fi

mkdir -p "$USER_LAUNCHERS"

# copy the file
cp "$source_file" "$USER_LAUNCHERS/$copy_name"
chmod +x "$USER_LAUNCHERS/$copy_name"

# update the @description tag to indicate it's a copy
if grep -q '# @description:' "$USER_LAUNCHERS/$copy_name" 2>/dev/null; then
    sed_inplace "s/# @description: .*/# @description: Copy of $name/" "$USER_LAUNCHERS/$copy_name"
fi

# output the copy name so the caller can hand off to the wizard
printf '%s' "$copy_name"
