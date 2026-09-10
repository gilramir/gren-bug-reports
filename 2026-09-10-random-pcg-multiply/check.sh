#!/bin/sh
# Run before the fix and after it. Prints a per-check verdict and exits 0 only
# if every check passes. Against `gren-lang/core` 7.4.2 it fails 8 of 8.
cd "$(dirname "$0")" || exit 1

output=$(devbox run gren run Check) || exit $?
printf '%s\n' "$output"

case "$output" in
    *"RESULT  pass"*) exit 0 ;;
    *) exit 1 ;;
esac
