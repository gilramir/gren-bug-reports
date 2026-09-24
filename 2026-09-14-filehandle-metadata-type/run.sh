#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# Reading the metadata, which is what `metadata` is for, does not compile.
echo '$ gren make Main --output=app'
gren make Main --output=app

# Passing the result to FileHandle.read, which the annotation allows, compiles and crashes.
echo
echo '$ gren make ReadFromMetadata --output=app && node app'
gren make ReadFromMetadata --output=app >/dev/null && node app
