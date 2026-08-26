#!/usr/bin/env bash
# shellcheck disable=SC1091
# rollback utilities for installation scripts
# source this file after common.sh

# three-file state protocol for installation rollback:
#   state.txt         append-only log of completed install steps (for resume detection)
#   symlinks.txt      pipe-delimited "link_path|target_path" records of created symlinks
#   backup-location.txt path to the timestamped backup directory
#
# lifecycle: init_rollback_state -> record_step/record_symlink/record_backup_location
#            -> perform_rollback (on failure) or cleanup_rollback_state (on success)
#
# rollback is two-phase: (1) remove created symlinks, (2) restore backed-up files
# path traversal sanitisation prevents restoring files outside $HOME

# guard against multiple sourcing
[[ -n "${_DOTFILES_ROLLBACK_SH_LOADED:-}" ]] && return 0
_DOTFILES_ROLLBACK_SH_LOADED=1

# state file location
ROLLBACK_STATE_DIR="${DOTFILES_DIR:-.}/.install-state"
ROLLBACK_STATE_FILE="$ROLLBACK_STATE_DIR/state.txt"
SYMLINKS_CREATED_FILE="$ROLLBACK_STATE_DIR/symlinks.txt"
BACKUP_LOCATION_FILE="$ROLLBACK_STATE_DIR/backup-location.txt"

# initialise rollback state directory
init_rollback_state() {
    rm -rf "$ROLLBACK_STATE_DIR"
    mkdir -p "$ROLLBACK_STATE_DIR"
    chmod 700 "$ROLLBACK_STATE_DIR"

    # create empty state files
    touch "$ROLLBACK_STATE_FILE"
    touch "$SYMLINKS_CREATED_FILE"
    touch "$BACKUP_LOCATION_FILE"
}

# record current installation step (no-op if state not initialised)
record_step() {
    local step="$1"
    [[ -d "$ROLLBACK_STATE_DIR" ]] || return 0
    echo "$step" >>"$ROLLBACK_STATE_FILE"
}

# get last completed step
get_last_step() {
    if [[ -f "$ROLLBACK_STATE_FILE" ]]; then
        tail -n1 "$ROLLBACK_STATE_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# record backup location (no-op if state not initialised)
record_backup_location() {
    local location="$1"
    [[ -d "$ROLLBACK_STATE_DIR" ]] || return 0
    echo "$location" >"$BACKUP_LOCATION_FILE"
}

# get backup location
get_backup_location() {
    if [[ -f "$BACKUP_LOCATION_FILE" ]]; then
        cat "$BACKUP_LOCATION_FILE"
    else
        echo ""
    fi
}

# record created symlink (no-op if state not initialised)
record_symlink() {
    local link_path="$1"
    local target_path="$2"
    [[ -d "$ROLLBACK_STATE_DIR" ]] || return 0
    echo "${link_path}|${target_path}" >>"$SYMLINKS_CREATED_FILE"
}

# get all created symlinks
get_created_symlinks() {
    if [[ -f "$SYMLINKS_CREATED_FILE" ]]; then
        cat "$SYMLINKS_CREATED_FILE"
    fi
}

# check if rollback state exists
has_rollback_state() {
    [[ -d "$ROLLBACK_STATE_DIR" ]] && [[ -f "$ROLLBACK_STATE_FILE" ]]
}

# clean up rollback state (after successful install)
cleanup_rollback_state() {
    rm -rf "$ROLLBACK_STATE_DIR"
}

# restore from a specific backup directory (without state)
restore_from_backup() {
    local backup_dir="$1"

    if [[ ! -d "$backup_dir" ]]; then
        error "Backup directory not found: $backup_dir"
        return 1
    fi

    info "Restoring from backup: $backup_dir"

    # find all files in backup and restore them
    find "$backup_dir" -type f | while read -r backup_file; do
        local relative_path="${backup_file#"$backup_dir"/}"

        # sanitise path to prevent traversal attacks
        if [[ "$relative_path" == ../* ]] || [[ "$relative_path" == */../* ]] || [[ "$relative_path" == */./* ]]; then
            warn "Skipping suspicious path: $relative_path"
            continue
        fi

        local original_path="$HOME/$relative_path"

        # remove existing symlink if present
        if [[ -L "$original_path" ]]; then
            rm -f "$original_path"
        fi

        # create directory if needed
        local original_dir
        original_dir=$(dirname "$original_path")
        mkdir -p "$original_dir"

        # restore file
        cp -p "$backup_file" "$original_path"
        success "Restored: $original_path"
    done

    success "Backup restored"
}

# perform rollback
perform_rollback() {
    local backup_dir
    backup_dir=$(get_backup_location)

    info "Starting rollback..."

    # step 1: remove created symlinks
    info "Removing created symlinks..."
    while IFS='|' read -r link_path target_path; do
        if [[ -L "$link_path" ]]; then
            rm -f "$link_path"
            success "Removed: $link_path"
        fi
    done < <(get_created_symlinks)

    # step 2: restore from backup if available
    if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
        info "Restoring from backup: $backup_dir"

        # restore each backed up file
        find "$backup_dir" -type f | while read -r backup_file; do
            # calculate original path
            local relative_path="${backup_file#"$backup_dir"/}"

            # sanitise path to prevent traversal attacks
            if [[ "$relative_path" == ../* ]] || [[ "$relative_path" == */../* ]] || [[ "$relative_path" == */./* ]]; then
                warn "Skipping suspicious path: $relative_path"
                continue
            fi

            local original_path="$HOME/$relative_path"

            # verify resolved path is still under $HOME
            local resolved_dir
            resolved_dir=$(cd "$(dirname "$original_path")" 2>/dev/null && pwd) || {
                warn "Cannot resolve path: $original_path"
                continue
            }

            if [[ "$resolved_dir" != "$HOME"* ]]; then
                warn "Path resolves outside home directory: $original_path"
                continue
            fi

            local original_dir
            original_dir=$(dirname "$original_path")

            # create directory if needed
            mkdir -p "$original_dir"

            # restore file
            cp -p "$backup_file" "$original_path"
            success "Restored: $original_path"
        done

        success "Backup restored from: $backup_dir"
    else
        warn "No backup found to restore"
    fi

    # step 3: clean up state
    cleanup_rollback_state

    success "Rollback complete"
}
