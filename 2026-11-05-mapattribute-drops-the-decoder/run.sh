#!/bin/sh
# Builds index.html; open it in a browser and click both buttons.
set -e
cd "$(dirname "$0")"

devbox run gren make Main --output=index.html
echo "open $(pwd)/index.html and click \"plain\", then \"mapped\""
