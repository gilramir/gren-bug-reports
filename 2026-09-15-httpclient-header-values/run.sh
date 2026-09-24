#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

gren make Main --output=app >/dev/null

echo '$ node app; echo "exit status $?"'
node app; echo "exit status $?"
