#!/bin/sh
# Builds Main with the Elm compiler devbox pins, and runs it under node; the
# Debug.log lines are the result.
set -e
cd "$(dirname "$0")"

devbox run -- elm make src/Main.elm --output=main.js
devbox run -- node -e "require('./main.js').Elm.Main.init()"
