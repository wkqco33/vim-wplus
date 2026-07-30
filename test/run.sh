#!/usr/bin/env bash
# Run the wplus test suite.
#
# Each test/test_*.vim is sourced in its own Vim process against test/vimrc.
# A test reports failures by appending to v:errors (via assert_*), which we
# write out and inspect. Any non-empty errors file fails the run.
#
# Usage: test/run.sh [name ...]     # name matches test_<name>.vim

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

VIM="${VIM_BIN:-vim}"
if ! command -v "$VIM" >/dev/null 2>&1; then
    echo "run.sh: '$VIM' not found on PATH" >&2
    exit 2
fi

if [ "$#" -gt 0 ]; then
    files=()
    for name in "$@"; do
        files+=("$here/test_${name#test_}.vim")
    done
else
    files=("$here"/test_*.vim)
fi

failed=0
ran=0

for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "run.sh: no such test: $file" >&2
        failed=1
        continue
    fi

    name="$(basename "$file" .vim)"
    errfile="$out/$name.errors"
    : >"$errfile"
    ran=$((ran + 1))

    # -es: silent-ex mode, scriptable and non-interactive.
    # The trailing writefile always runs, so an empty file means "passed"
    # and a missing file means Vim died before finishing.
    "$VIM" -Nu "$here/vimrc" -i NONE -n -es \
        -c "let v:errors = []" \
        -S "$file" \
        -c "call writefile(v:errors, '$errfile')" \
        -c "qa!" </dev/null >"$out/$name.stdout" 2>"$out/$name.stderr"
    status=$?

    if [ ! -s "$errfile" ] && [ "$status" -ne 0 ]; then
        echo "FAIL $name (vim exited $status before reporting)"
        sed 's/^/      /' "$out/$name.stderr" | head -20
        failed=1
        continue
    fi

    if [ -s "$errfile" ]; then
        count="$(wc -l <"$errfile" | tr -d ' ')"
        echo "FAIL $name ($count)"
        sed 's/^/      /' "$errfile"
        failed=1
    else
        echo "ok   $name"
    fi
done

echo
if [ "$failed" -ne 0 ]; then
    echo "FAILED ($ran test files)"
    exit 1
fi
echo "PASSED ($ran test files)"
