#!/bin/sh
set -e
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

gren make Main --output=main.js >/dev/null

echo '$ node host.js'
node host.js
