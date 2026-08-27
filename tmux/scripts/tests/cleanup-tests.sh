#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# cleanup-tests.sh
# ══════════════════════════════════════════════════════════════
# cleans up leftover tmux test servers, sockets, and backup files.
# run this to clean up orphaned test resources from failed tests.
#
# usage:
#   cleanup-tests.sh           # clean up test resources
#   cleanup-tests.sh --dry-run # show what would be cleaned
# ══════════════════════════════════════════════════════════════

set -euo pipefail

# colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

SOCKET_DIR="/private/tmp/tmux-501"
SESSIONS_DIR="${HOME}/.tmux/resurrect/sessions"

SOCKET_COUNT=0
BACKUP_COUNT=0

# ──────────────────────────────────────────────────────────────
# clean up test sockets/servers
# ──────────────────────────────────────────────────────────────
if [[ -d "$SOCKET_DIR" ]]; then
    # find test sockets (either 'test-*' or 'tmux-test-*')
    TEST_SOCKETS=$(find "$SOCKET_DIR" -name 'test-*' -o -name 'tmux-test-*' 2>/dev/null || true)

    if [[ -n "$TEST_SOCKETS" ]]; then
        printf "${CYAN}Test servers:${NC}\n"
        while IFS= read -r socket; do
            [[ -z "$socket" ]] && continue

            SOCKET_NAME=$(basename "$socket")

            if [[ "$DRY_RUN" == "true" ]]; then
                printf "${YELLOW}Would kill:${NC} %s\n" "$SOCKET_NAME"
            else
                # try to kill the server gracefully
                tmux -L "$SOCKET_NAME" kill-server 2>/dev/null || true

                # remove socket file if it still exists
                rm -f "$socket" 2>/dev/null || true

                printf "${GREEN}✓${NC} Cleaned up: %s\n" "$SOCKET_NAME"
            fi

            SOCKET_COUNT=$((SOCKET_COUNT + 1))
        done <<<"$TEST_SOCKETS"
    fi
fi

# ──────────────────────────────────────────────────────────────
# clean up test session backup files
# ──────────────────────────────────────────────────────────────
if [[ -d "$SESSIONS_DIR" ]]; then
    # find test session backups (files starting with 'test')
    TEST_BACKUPS=$(find "$SESSIONS_DIR" -name 'test*.txt' 2>/dev/null || true)

    if [[ -n "$TEST_BACKUPS" ]]; then
        if [[ $SOCKET_COUNT -gt 0 ]]; then
            printf "\n"
        fi
        printf "${CYAN}Test session backups:${NC}\n"
        while IFS= read -r backup; do
            [[ -z "$backup" ]] && continue

            BACKUP_NAME=$(basename "$backup" .txt)

            if [[ "$DRY_RUN" == "true" ]]; then
                printf "${YELLOW}Would remove:${NC} %s\n" "$BACKUP_NAME"
            else
                rm -f "$backup" 2>/dev/null || true
                printf "${GREEN}✓${NC} Cleaned up: %s\n" "$BACKUP_NAME"
            fi

            BACKUP_COUNT=$((BACKUP_COUNT + 1))
        done <<<"$TEST_BACKUPS"
    fi
fi

# ──────────────────────────────────────────────────────────────
# summary
# ──────────────────────────────────────────────────────────────
printf "\n"
if [[ $SOCKET_COUNT -eq 0 && $BACKUP_COUNT -eq 0 ]]; then
    printf "${GREEN}No test resources found - all clean!${NC}\n"
elif [[ "$DRY_RUN" == "true" ]]; then
    printf "${YELLOW}Found %d test servers and %d test backups${NC}\n" "$SOCKET_COUNT" "$BACKUP_COUNT"
    printf "${YELLOW}(use without --dry-run to clean)${NC}\n"
else
    printf "${GREEN}Cleaned up %d test servers and %d test backups${NC}\n" "$SOCKET_COUNT" "$BACKUP_COUNT"
fi
