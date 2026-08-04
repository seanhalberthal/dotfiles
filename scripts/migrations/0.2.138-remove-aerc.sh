#!/usr/bin/env bash
# migration: aerc is no longer managed by the dotfiles.
#
# the repo's aerc/ directory is gone, so the aerc.conf and binds.conf symlinks the
# installer created now dangle. remove them, but only when they are genuinely
# broken links into an aerc path, so a hand-rolled aerc config is never touched.
#
# accounts.conf is user-owned and holds real addresses, so it is left in place and
# reported instead. the aerc and w3m formulae are left installed too: removing
# software the user may still want is not this migration's job

set -euo pipefail

aerc_dir="${XDG_CONFIG_HOME:-$HOME/.config}/aerc"

[[ -d "$aerc_dir" ]] || exit 0

removed=0
for name in aerc.conf binds.conf; do
    link="$aerc_dir/$name"
    # symlink that no longer resolves, pointing at an aerc path
    [[ -L "$link" && ! -e "$link" ]] || continue
    case "$(readlink "$link")" in
        */aerc/*) ;;
        *) continue ;;
    esac
    rm -f "$link"
    echo "    Removed stale symlink: ~/${link#"$HOME"/}"
    removed=$((removed + 1))
done

if [[ -f "$aerc_dir/accounts.conf" ]]; then
    echo "    Left accounts.conf in place (user-owned, holds account details)"
    echo "    Delete it by hand when done, along with any aerc-* keychain entries"
elif [[ $removed -gt 0 ]]; then
    rmdir "$aerc_dir" 2>/dev/null && echo "    Removed empty ~/${aerc_dir#"$HOME"/}" || true
fi

exit 0
