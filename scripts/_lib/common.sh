#!/usr/bin/env bash
# Common utilities for installation scripts
# Source this file: source "${BASH_SOURCE%/*}/_lib/common.sh"

# Colours for output (using $'...' for proper escape interpretation)
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m' # No Colour

# Print error message to stderr
error() {
    printf "${RED}Error:${NC} %s\n" "$1" >&2
}

# Print warning message to stderr
warn() {
    printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2
}

# Print info message
info() {
    printf "${CYAN}%s${NC}\n" "$1"
}

# Print success message
success() {
    printf "${GREEN}%s${NC}\n" "$1"
}

# Print step header with box style
print_header() {
    local title="$1"
    echo ""
    echo "${CYAN}╔════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║%*s%s%*s║${NC}\n" $(( (42 - ${#title}) / 2 )) "" "$title" $(( (43 - ${#title}) / 2 )) ""
    echo "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

# Print section header
print_section() {
    local title="$1"
    echo "============================================"
    echo "$title"
    echo "============================================"
    echo ""
}

# Print step with number
print_step() {
    local step_num="$1"
    local description="$2"
    echo "${CYAN}Step $step_num: $description${NC}"
    echo ""
}

# Print skipped step
print_skip() {
    local step_num="$1"
    local description="$2"
    local reason="$3"
    echo "${YELLOW}Step $step_num: Skipping $description ($reason)${NC}"
    echo ""
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check for a command and print status
check_command() {
    local name="$1"
    local cmd="$2"
    local install_hint="${3:-}"
    local is_optional="${4:-false}"

    if [[ "$is_optional" == "true" ]]; then
        printf "Checking %-20s" "$name (optional)..."
    else
        printf "Checking %-20s" "$name..."
    fi

    if command_exists "$cmd"; then
        printf '%s%s%s\n' "$GREEN" "OK" "$NC"
        return 0
    else
        if [[ "$is_optional" == "true" ]]; then
            printf '%s%s%s\n' "$YELLOW" "MISSING" "$NC"
        else
            printf '%s%s%s\n' "$RED" "MISSING" "$NC"
        fi
        if [[ -n "$install_hint" ]]; then
            printf "  ${YELLOW}Install with:${NC} %s\n" "$install_hint"
        fi
        return 1
    fi
}

# Check if running on macOS
is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# Check if running on Apple Silicon
is_apple_silicon() {
    [[ "$(uname -m)" == "arm64" ]]
}

# Get Homebrew prefix based on architecture
get_homebrew_prefix() {
    if is_apple_silicon; then
        echo "/opt/homebrew"
    else
        echo "/usr/local"
    fi
}

# Read with timeout (prevents hanging on interactive prompts)
# Usage: read_with_timeout "prompt" variable_name timeout_seconds
# Note: The variable_name is used via nameref for dynamic assignment
read_with_timeout() {
    local prompt="$1"
    local -n _result_var="$2"
    local timeout="${3:-300}"

    if read -r -t "$timeout" -p "$prompt" _result_var; then
        return 0
    else
        echo ""
        warn "Input timed out after ${timeout}s"
        return 1
    fi
}

# Confirm action (y/n prompt)
confirm() {
    local prompt="${1:-Continue?}"
    local response
    read -r -p "$prompt [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Get the script directory (for relative sourcing)
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Source the library from script location
# Usage: source "$(get_lib_path)/common.sh"
get_lib_path() {
    echo "$(get_script_dir)/_lib"
}
