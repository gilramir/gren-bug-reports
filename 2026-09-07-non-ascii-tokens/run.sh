#!/bin/sh
# Two programs. `src/Boundary.gren` asks `keyword` directly; `src/Language.gren`
# is a small language built on it. README.md says what each line should say.
set -e
cd "$(dirname "$0")"

echo "=== src/Boundary.gren — Err is correct for all four"
devbox run boundary

echo
echo "=== src/Language.gren"
devbox run language
