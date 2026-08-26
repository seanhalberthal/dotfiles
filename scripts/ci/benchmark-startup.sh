#!/usr/bin/env bash
# benchmark zsh startup time in CI
# usage: benchmark-startup.sh [threshold_ms]
#
# runs hyperfine against `zsh -i -c exit` using the dotfiles framework,
# outputs results for benchmark-action, writes a summary to $GITHUB_STEP_SUMMARY,
# and exits non-zero if the median exceeds the threshold

set -euo pipefail

THRESHOLD="${1:-500}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_FILE="$(mktemp)"

# ─────────────────────────────────────────
# create a temporary .zshrc that sources the framework
# ─────────────────────────────────────────
TEMP_ZSHRC="$(mktemp)"
cat >"$TEMP_ZSHRC" <<EOF
# CI benchmark, sources the dotfiles framework
# Suppress powerlevel10k instant prompt (not installed in CI)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet 2>/dev/null
source "$DOTFILES_DIR/zsh/dotfiles.zsh"
EOF

cleanup() {
    rm -f "$TEMP_ZSHRC" "$RESULTS_FILE"
}
trap cleanup EXIT

# ─────────────────────────────────────────
# run benchmark
# ─────────────────────────────────────────
echo "Benchmarking zsh startup (threshold: ${THRESHOLD}ms)..."
echo "Using framework: $DOTFILES_DIR/zsh/dotfiles.zsh"
echo ""

ZDOTDIR_DIR="$(mktemp -d)"
cp "$TEMP_ZSHRC" "$ZDOTDIR_DIR/.zshrc"

hyperfine \
    --warmup 5 \
    --runs 100 \
    --export-json "$RESULTS_FILE" \
    --shell=none \
    "env ZDOTDIR=$ZDOTDIR_DIR zsh -i -c exit"

rm -rf "$ZDOTDIR_DIR"

# ─────────────────────────────────────────
# parse results
# ─────────────────────────────────────────
MEDIAN_S=$(python3 -c "
import json, sys
with open('$RESULTS_FILE') as f:
    data = json.load(f)
result = data['results'][0]
print(result['median'])
")

MEDIAN_MS=$(python3 -c "print(round($MEDIAN_S * 1000, 1))")
MIN_MS=$(python3 -c "
import json
with open('$RESULTS_FILE') as f:
    data = json.load(f)
print(round(data['results'][0]['min'] * 1000, 1))
")
MAX_MS=$(python3 -c "
import json
with open('$RESULTS_FILE') as f:
    data = json.load(f)
print(round(data['results'][0]['max'] * 1000, 1))
")
STDDEV_MS=$(python3 -c "
import json
with open('$RESULTS_FILE') as f:
    data = json.load(f)
print(round(data['results'][0]['stddev'] * 1000, 1))
")

echo ""
echo "Results: median=${MEDIAN_MS}ms  min=${MIN_MS}ms  max=${MAX_MS}ms  stddev=${STDDEV_MS}ms"
echo ""

# export for downstream steps (e.g. badge update)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "min_ms=${MIN_MS}" >>"$GITHUB_OUTPUT"
    echo "median_ms=${MEDIAN_MS}" >>"$GITHUB_OUTPUT"
fi

# ─────────────────────────────────────────
# write GitHub step summary
# ─────────────────────────────────────────
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Zsh Startup Benchmark"
        echo ""
        echo "| Metric | Value |"
        echo "|--------|-------|"
        echo "| Median | ${MEDIAN_MS}ms |"
        echo "| Min | ${MIN_MS}ms |"
        echo "| Max | ${MAX_MS}ms |"
        echo "| Std Dev | ${STDDEV_MS}ms |"
        echo "| Threshold | ${THRESHOLD}ms |"
        echo ""
    } >>"$GITHUB_STEP_SUMMARY"
fi

# ─────────────────────────────────────────
# check threshold
# ─────────────────────────────────────────
EXCEEDED=$(python3 -c "print('yes' if $MEDIAN_MS > $THRESHOLD else 'no')")

if [[ "$EXCEEDED" == "yes" ]]; then
    echo "FAIL: Median startup time (${MEDIAN_MS}ms) exceeds threshold (${THRESHOLD}ms)"
    exit 1
else
    echo "PASS: Median startup time (${MEDIAN_MS}ms) is within threshold (${THRESHOLD}ms)"
    exit 0
fi
