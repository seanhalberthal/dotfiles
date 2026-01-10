#!/usr/bin/env bash
# shellcheck disable=SC1091
# Rollback utilities for installation scripts
# Source this file after common.sh

# State file location
ROLLBACK_STATE_DIR="${DOTFILES_DIR:-.}/.install-state"
ROLLBACK_STATE_FILE="$ROLLBACK_STATE_DIR/state.txt"
SYMLINKS_CREATED_FILE="$ROLLBACK_STATE_DIR/symlinks.txt"
BACKUP_LOCATION_FILE="$ROLLBACK_STATE_DIR/backup-location.txt"

# Initialise rollback state directory
init_rollback_state() {
    rm -rf "$ROLLBACK_STATE_DIR"
    mkdir -p "$ROLLBACK_STATE_DIR"
    chmod 700 "$ROLLBACK_STATE_DIR"

    # Create empty state files
    touch "$ROLLBACK_STATE_FILE"
    touch "$SYMLINKS_CREATED_FILE"
    touch "$BACKUP_LOCATION_FILE"
}

# Record current installation step
record_step() {
    local step="$1"
    echo "$step" >> "$ROLLBACK_STATE_FILE"
}

# Get last completed step
get_last_step() {
    if [[ -f "$ROLLBACK_STATE_FILE" ]]; then
        tail -n1 "$ROLLBACK_STATE_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Record backup location
record_backup_location() {
    local location="$1"
    echo "$location" > "$BACKUP_LOCATION_FILE"
}

# Get backup location
get_backup_location() {
    if [[ -f "$BACKUP_LOCATION_FILE" ]]; then
        cat "$BACKUP_LOCATION_FILE"
    else
        echo ""
    fi
}

# Record created symlink
record_symlink() {
    local link_path="$1"
    local target_path="$2"
    echo "${link_path}|${target_path}" >> "$SYMLINKS_CREATED_FILE"
}

# Get all created symlinks
get_created_symlinks() {
    if [[ -f "$SYMLINKS_CREATED_FILE" ]]; then
        cat "$SYMLINKS_CREATED_FILE"
    fi
}

# Check if rollback state exists
has_rollback_state() {
    [[ -d "$ROLLBACK_STATE_DIR" ]] && [[ -f "$ROLLBACK_STATE_FILE" ]]
}

# Clean up rollback state (after successful install)
cleanup_rollback_state() {
    rm -rf "$ROLLBACK_STATE_DIR"
}

# Perform rollback
perform_rollback() {
    local backup_dir
    backup_dir=$(get_backup_location)

    info "Starting rollback..."

    # Step 1: Remove created symlinks
    info "Removing created symlinks..."
    while IFS='|' read -r link_path target_path; do
        if [[ -L "$link_path" ]]; then
            rm -f "$link_path"
            success "Removed: $link_path"
        fi
    done < <(get_created_symlinks)

    # Step 2: Restore from backup if available
    if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
        info "Restoring from backup: $backup_dir"

        # Restore each backed up file
        find "$backup_dir" -type f | while read -r backup_file; do
            # Calculate original path
            local relative_path="${backup_file#"$backup_dir"/}"
            local original_path="$HOME/$relative_path"
            local original_dir
            original_dir=$(dirname "$original_path")

            # Create directory if needed
            mkdir -p "$original_dir"

            # Restore file
            cp -p "$backup_file" "$original_path"
            success "Restored: $original_path"
        done

        success "Backup restored from: $backup_dir"
    else
        warn "No backup found to restore"
    fi

    # Step 3: Clean up state
    cleanup_rollback_state

    success "Rollback complete"
}
