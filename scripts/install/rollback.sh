#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Rollback a failed or unwanted dotfiles installation
# Usage: ./scripts/rollback.sh [--force]

SCRIPT_DIR="${BASH_SOURCE%/*}"
DOTFILES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
export DOTFILES_DIR

source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/rollback.sh"

FORCE="${1:-}"

print_header "Dotfiles Rollback"

# Check if rollback state exists
if ! has_rollback_state; then
    error "No installation state found to rollback"
    echo ""
    echo "Rollback state is created during installation and cleaned up"
    echo "after successful completion."
    echo ""
    echo "To manually restore from a backup, check:"
    echo "  ls -la ~/.dotfiles-backup/"
    exit 1
fi

# Show what will be rolled back
echo "The following actions will be performed:"
echo ""

# Show symlinks to remove
symlinks=$(get_created_symlinks)
if [[ -n "$symlinks" ]]; then
    echo "Symlinks to remove:"
    while IFS='|' read -r link_path _target_path; do
        echo "  - $link_path"
    done <<< "$symlinks"
    echo ""
fi

# Show backup to restore
backup_dir=$(get_backup_location)
if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
    echo "Backup to restore from:"
    echo "  $backup_dir"
    echo ""
    echo "Files to restore:"
    find "$backup_dir" -type f | while read -r f; do
        echo "  - ${f#"$backup_dir"/}"
    done
    echo ""
fi

# Confirm unless --force
if [[ "$FORCE" != "--force" ]]; then
    if ! confirm "Proceed with rollback?"; then
        echo "Rollback cancelled"
        exit 0
    fi
fi

# Perform rollback
perform_rollback

echo ""
success "Rollback completed successfully"
echo ""
echo "Your system has been restored to its pre-installation state."
if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
    echo "Backup preserved at: $backup_dir"
fi
