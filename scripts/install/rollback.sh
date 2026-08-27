#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# rollback a failed or unwanted dotfiles installation
# usage: ./scripts/install/rollback.sh [--force]

SCRIPT_DIR="${BASH_SOURCE%/*}"
DOTFILES_DIR="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")" && pwd)"
export DOTFILES_DIR

source "$SCRIPT_DIR/../_lib/common.sh"
source "$SCRIPT_DIR/../_lib/rollback.sh"

FORCE="${1:-}"

print_header "Dotfiles Rollback"

# check if rollback state exists
if ! has_rollback_state; then
    # no state, but check for backups
    BACKUP_BASE="$HOME/.dotfiles-backup"
    if [[ -d "$BACKUP_BASE" ]]; then
        # find most recent backup
        LATEST_BACKUP=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d | sort -r | head -1)
        if [[ -n "$LATEST_BACKUP" ]] && [[ -d "$LATEST_BACKUP" ]]; then
            warn "No installation state found, but backup exists."
            echo ""
            echo "Found backup: $LATEST_BACKUP"
            echo ""
            if confirm "Restore from this backup?"; then
                restore_from_backup "$LATEST_BACKUP"
                echo ""
                success "Restore completed from: $LATEST_BACKUP"
                exit 0
            else
                echo "Rollback cancelled"
                exit 0
            fi
        fi
    fi

    error "No installation state or backups found to rollback"
    echo ""
    echo "Rollback state is created during installation and cleaned up"
    echo "after successful completion."
    exit 1
fi

# show what will be rolled back
echo "The following actions will be performed:"
echo ""

# show symlinks to remove
symlinks=$(get_created_symlinks)
if [[ -n "$symlinks" ]]; then
    echo "Symlinks to remove:"
    while IFS='|' read -r link_path _target_path; do
        echo "  - $link_path"
    done <<<"$symlinks"
    echo ""
fi

# show backup to restore
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

# confirm unless --force
if [[ "$FORCE" != "--force" ]]; then
    if ! confirm "Proceed with rollback?"; then
        echo "Rollback cancelled"
        exit 0
    fi
fi

# perform rollback
perform_rollback

echo ""
success "Rollback completed successfully"
echo ""
echo "Your system has been restored to its pre-installation state."
if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
    echo "Backup preserved at: $backup_dir"
fi
