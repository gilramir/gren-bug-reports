#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# A node application that lists a browser package, which the dependency check
# refuses with a report that has no file path.
echo '$ gren make Main --output=/dev/null'
gren make Main --output=/dev/null 2>&1 || true
