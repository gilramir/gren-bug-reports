#!/bin/sh
set -e
cd "$(dirname "$0")"

devbox run gren run Main
echo
echo "--- the same generator in exact arithmetic, for comparison ---"
devbox run node reference.js
