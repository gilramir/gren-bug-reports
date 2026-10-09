#!/bin/sh
set -e
cd "$(dirname "$0")"

echo "== Write"
devbox run gren run Write
echo "== Read"
devbox run gren run Read
