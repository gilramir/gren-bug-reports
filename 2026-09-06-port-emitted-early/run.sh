#!/bin/sh
# Builds the reproduction and serves it, then open http://localhost:8000/ and
# look at the browser's JavaScript console.
#
# Serve it rather than opening index.html directly: over file:// a browser
# treats every file as its own origin and reports the error as a bare
# "Script error." with no message and no line number.
set -e
cd "$(dirname "$0")"

devbox run build

echo
echo "=== http://localhost:8000/ — the console shows the throw; ctrl-c to stop"
exec devbox run serve
