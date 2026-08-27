#!/usr/bin/env bash
# Brewfile filtering utilities
# Source this file: source "${BASH_SOURCE%/*}/_lib/brewfile.sh"

# guard against multiple sourcing
[[ -n "${_DOTFILES_BREWFILE_SH_LOADED:-}" ]] && return 0
_DOTFILES_BREWFILE_SH_LOADED=1

# filter Brewfile based on preset
# the Brewfile uses section markers like "# @preset: minimal"
# sections are included by hierarchy: minimal < core < full
#
# Usage: filter_brewfile "preset" "brewfile_path"
# Arguments:
#   preset      - one of: minimal, core, full
#   brewfile    - path to the Brewfile to filter
#
# Output: filtered brewfile content to stdout
filter_brewfile() {
    local preset="$1"
    local brewfile="$2"
    local include_minimal=true
    local include_core=false
    local include_full=false

    case "$preset" in
        minimal)
            include_minimal=true
            ;;
        core)
            include_minimal=true
            include_core=true
            ;;
        full)
            include_minimal=true
            include_core=true
            include_full=true
            ;;
        *)
            echo "Error: Invalid preset '$preset'. Must be: minimal, core, or full" >&2
            return 1
            ;;
    esac

    local is_darwin="true"
    [[ "$(uname)" != "Darwin" ]] && is_darwin="false"

    # AWK state machine: filters Brewfile by preset.
    # lines before the first @preset marker are always included (headers, taps).
    # when a @preset marker is hit, `include` is set based on whether that
    # preset level was requested (preset hierarchy: minimal ⊂ core ⊂ full).
    # the `next` skips the marker line itself from output.
    # cask lines are additionally stripped on Linux (macOS-only packages)
    awk -v inc_min="$include_minimal" -v inc_core="$include_core" -v inc_full="$include_full" -v darwin="$is_darwin" '
    BEGIN {
        include = 1  # Include header lines before any preset marker
    }

    # Detect preset section markers
    /^# @preset: minimal/ {
        include = (inc_min == "true") ? 1 : 0
        next
    }
    /^# @preset: core/ {
        include = (inc_core == "true") ? 1 : 0
        next
    }
    /^# @preset: full/ {
        include = (inc_full == "true") ? 1 : 0
        next
    }

    # Skip cask lines on Linux (casks are macOS-only)
    darwin != "true" && /^cask / { next }

    # Skip formulas marked as macOS-only on Linux
    darwin != "true" && /# macOS-only/ { next }

    # Print lines if we should include this section
    include { print }
    ' "$brewfile"
}

# create a temporary filtered Brewfile
# creates a temp file and filters the Brewfile into it
#
# Usage: FILTERED_FILE=$(create_filtered_brewfile "preset" "brewfile_path")
# Arguments:
#   preset      - one of: minimal, core, full
#   brewfile    - path to the Brewfile to filter
#
# Output: path to temporary filtered Brewfile (caller must clean up)
# Note: caller is responsible for removing the temp file
create_filtered_brewfile() {
    local preset="$1"
    local brewfile="$2"
    local filtered_file

    filtered_file=$(mktemp)

    # filter and write to temp file
    if ! filter_brewfile "$preset" "$brewfile" >"$filtered_file"; then
        rm -f "$filtered_file"
        return 1
    fi

    echo "$filtered_file"
}
