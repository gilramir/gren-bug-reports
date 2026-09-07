#!/bin/sh
# Three programs, none of which prints any commentary. README.md says what each
# one shows and what its output should have been.
set -e
cd "$(dirname "$0")"

echo "=== src/Identifiers.gren — every name in it is non-ASCII; it compiles"
devbox run identifiers

echo
echo "=== src/Boundary.gren — Err is correct for all four"
devbox run boundary

echo
echo "=== src/Language.gren"
devbox run language
