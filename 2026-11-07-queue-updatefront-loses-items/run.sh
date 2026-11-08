#!/bin/sh
# Builds and runs Main, which prints the table in README.md.
set -e
cd "$(dirname "$0")"

devbox run gren make Main --output=app
devbox run node app
