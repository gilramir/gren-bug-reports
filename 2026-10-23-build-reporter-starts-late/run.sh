#!/bin/sh
# Builds Main three times and shows each build's whole output, carriage
# returns as ^M. Set GREN_BIN to run a compiler built from source.
set -e
cd "$(dirname "$0")"

for i in 1 2 3; do
    rm -rf .gren
    status=0
    devbox run -q -- gren make Main --output=/dev/null > out.txt 2>&1 || status=$?
    echo "== build $i, exit $status"
    cat -A out.txt
    echo
done
rm -f out.txt
