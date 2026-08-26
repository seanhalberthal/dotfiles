#!/usr/bin/env bash
set -euo pipefail

# set Zed as the default handler for code file types (macOS only)
#
# uses duti to bind file extensions to Zed. macOS quirks handled here:
#   - a stale LaunchServices registration makes duti's set a silent no-op
#     (the write succeeds but a competing app keeps winning), so Zed is
#     re-registered first
#   - extensions with no system-declared UTI resolve to an ephemeral dyn.*
#     type that LaunchServices refuses to bind (error -50), so they're
#     skipped. Zed already claims some of these (go, jsx) via its own
#     Info.plist, so they open in Zed regardless
#   - some extensions (log) are governed by a system UTI a built-in app
#     claims; binding the bare extension loses to that UTI, so the UTI is
#     bound instead (see bind_target)
#
# macOS 15+ shows a modal consent dialog on each programmatic handler change.
# to avoid re-nagging on every `dotfiles update`, an extension is only asked
# about once: it's skipped if Zed already handles it, or if the user declined
# before (recorded in .state/declined-default-apps). the dialog is modal so
# duti's set blocks until the click, letting a post-set re-check tell an
# accept from a decline

SCRIPT_DIR="${BASH_SOURCE%/*}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_lib/common.sh"

ZED_BUNDLE="dev.zed.Zed"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/.state"
DECLINED_FILE="$STATE_DIR/declined-default-apps"

# extensions to route to Zed. html is intentionally left to the browser.
# dynamic-UTI extensions (cs, lua, env, ...) are skipped automatically.
EXTENSIONS=(go cs lua md ts tsx env json yaml yml toml css js jsx log)

# what to bind for an extension. most bind the bare extension; a few are
# governed by a system-declared UTI another app claims, so the UTI is bound
# directly since the bare extension loses to it (kept a case, not an
# associative array, to stay bash 3.2 safe for a fresh macOS install)
bind_target() {
    case "$1" in
        log) printf '%s' 'com.apple.log' ;;
        *) printf '.%s' "$1" ;;
    esac
}

if ! is_macos; then
    info "default-app handlers are macOS-only, skipping"
    exit 0
fi

if ! command_exists duti; then
    warn "duti not installed, skipping default-app setup (brew install duti)"
    exit 0
fi

# locate Zed so its LaunchServices record can be refreshed
zed_app=""
for candidate in "/Applications/Zed.app" "$HOME/Applications/Zed.app"; do
    if [[ -d "$candidate" ]]; then
        zed_app="$candidate"
        break
    fi
done

if [[ -z "$zed_app" ]]; then
    info "Zed not found, skipping default-app setup"
    exit 0
fi

# refresh Zed's registration so duti's writes actually win the type binding
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$zed_app" 2>/dev/null || true
fi

# an extension is bindable only if it resolves to at least one real
# (non-dynamic) UTI; dynamic-only extensions can't be set and return -50
has_real_uti() {
    local ext="$1" line
    while IFS= read -r line; do
        case "$line" in
            *identifier:*dyn.*) ;;
            *identifier:*) return 0 ;;
        esac
    done < <(duti -e "$ext" 2>/dev/null)
    return 1
}

# true when Zed already handles the extension (duti -x prints the handler
# bundle id on its own line)
handler_is_zed() {
    duti -x "$1" 2>/dev/null | grep -qx "$ZED_BUNDLE"
}

declined_before() {
    [[ -f "$DECLINED_FILE" ]] && grep -qx "$1" "$DECLINED_FILE"
}

record_declined() {
    declined_before "$1" || printf '%s\n' "$1" >>"$DECLINED_FILE"
}

mkdir -p "$STATE_DIR"

set_count=0      # newly bound this run
already_count=0  # already handled by Zed
declined_count=0 # skipped or recorded as declined
skip_count=0     # unbindable, no stable UTI
for ext in "${EXTENSIONS[@]}"; do
    if ! has_real_uti "$ext"; then
        skip_count=$((skip_count + 1))
        continue
    fi
    if handler_is_zed "$ext"; then
        already_count=$((already_count + 1))
        continue
    fi
    if declined_before "$ext"; then
        declined_count=$((declined_count + 1))
        continue
    fi

    # ask once; the dialog blocks, so the re-check reflects the user's choice
    duti -s "$ZED_BUNDLE" "$(bind_target "$ext")" all 2>/dev/null || true
    if handler_is_zed "$ext"; then
        set_count=$((set_count + 1))
    else
        record_declined "$ext"
        declined_count=$((declined_count + 1))
    fi
done

success "Zed default apps: $set_count set, $already_count already set, $declined_count declined, $skip_count no stable type"
