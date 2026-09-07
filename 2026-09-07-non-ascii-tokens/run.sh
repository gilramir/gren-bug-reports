#!/bin/sh
# Builds and runs the reproduction. Everything it prints goes to stdout; there
# is no server and no browser involved.
set -e
cd "$(dirname "$0")"

exec devbox run run
