#!/usr/bin/env bash
# Integration test for the Vim test runner (test/run.sh).
#
# Two guards are covered:
#   1. A test file with no Test_* functions is rejected (vacuous pass).
#   2. A Test_* function that raises a Vim error is reported with the actual
#      error, not as "vim exited before reporting". Silent-ex mode (-es)
#      swallows messages, so without an explicit catch the cause is invisible
#      and a macOS-only failure cannot be diagnosed from CI logs.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/test"
cp "$repo/test/run.sh" "$tmp/test/run.sh"
cp "$repo/test/vimrc" "$tmp/test/vimrc"
chmod +x "$tmp/test/run.sh"

# ── guard 1: a file without Test_* functions must not pass ────────────────
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

# ── guard 2: a raised Vim error must be reported with its message ─────────
cat > "$tmp/test/test_raises.vim" <<'VIM'
function! Test_raises_a_vim_error() abort
    call assert_equal(1, 1)
    call wplus_harness_no_such_function()
endfunction
VIM

output="$({ VIM_BIN="${VIM_BIN:-vim}" "$tmp/test/run.sh" raises; } 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    echo "FAIL: runner passed a test that raised a Vim error" >&2
    echo "$output" >&2
    exit 1
fi
if [[ "$output" != *"E117"* ]]; then
    echo "FAIL: runner hid the raised Vim error (cause not in output)" >&2
    echo "$output" >&2
    exit 1
fi
echo "PASS: raised Vim errors are reported with their message"
