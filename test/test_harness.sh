#!/usr/bin/env bash
# Integration test for the Vim test runner's zero-test-file guard.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/test"
cp "$repo/test/run.sh" "$tmp/test/run.sh"
cp "$repo/test/vimrc" "$tmp/test/vimrc"
chmod +x "$tmp/test/run.sh"
printf '" This file intentionally contains no Test_* functions.\n' > "$tmp/test/test_empty.vim"

output="$({ VIM_BIN="${VIM_BIN:-vim}" "$tmp/test/run.sh" empty; } 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    echo "FAIL: runner accepted a test file with no Test_* functions" >&2
    echo "$output" >&2
    exit 1
fi
if [[ "$output" != *"contains no Test_* functions"* ]]; then
    echo "FAIL: runner failed for an unexpected reason" >&2
    echo "$output" >&2
    exit 1
fi
echo "PASS: empty test files are rejected"
