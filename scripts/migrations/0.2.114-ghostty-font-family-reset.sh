#!/usr/bin/env bash
# migration: insert a `font-family = ""` reset into an existing ghostty local
# override when it sets a font-family but lacks the reset
#
# Ghostty chains repeated font-family values into a fallback list (first entry =
# primary) rather than last-value-wins. the base config (~/.config/ghostty/config)
# already sets font-family, so a bare `font-family = MyFont` in the user-owned
# local file ends up as a *fallback* behind the base font, not the primary. the
# fix is a leading `font-family = ""` that clears the inherited value first
#
# local.template now ships that reset for fresh installs, but local is
# copy-on-install (never overwritten), so existing users need it patched in here
#
# idempotent: does nothing if no font-family override is present, or if a reset
# already exists

set -euo pipefail

f="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/local"

if [[ ! -f "$f" ]]; then
    exit 0
fi

# already has a font-family reset (empty value or "") -> nothing to do
if grep -Eq '^[[:space:]]*font-family[[:space:]]*=[[:space:]]*("")?[[:space:]]*$' "$f"; then
    exit 0
fi

# no non-empty plain font-family override -> the base default already wins; leave
# the file untouched. (the regex excludes font-family-bold/-italic, which would
# have a '-' rather than '=' immediately after 'font-family')
if ! grep -Eq '^[[:space:]]*font-family[[:space:]]*=[[:space:]]*[^[:space:]]' "$f"; then
    exit 0
fi

# insert the reset before the first active (non-comment, non-blank) line, i.e.
# at the top of the settings block. it only has to precede the font-family
# override to win; placing it at the top keeps it out of the way and avoids
# splitting whatever grouping the user has. indentation matches that first line
tmp="$(mktemp)"
awk '
    !done && /[^[:space:]]/ && $0 !~ /^[[:space:]]*#/ {
        indent = $0
        sub(/[^[:space:]].*$/, "", indent)   # leading whitespace of this line
        print indent "font-family = \"\""
        done = 1
    }
    { print }
' "$f" >"$tmp" && mv "$tmp" "$f"

echo "    Added a font-family reset to $f"
echo "    (your font-family override now applies as the primary font, not a fallback)"
