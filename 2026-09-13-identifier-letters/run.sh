#!/bin/sh
set -e
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# What compiler-common's parser says about each name.
gren run Main > parser.txt

# What `gren make` says about the same names.
printf '%-7s %-6s %-11s %s\n' "kind" "name" "gren make" "compiler-common"
while read -r kind name answer; do
    rm -rf names && mkdir -p names/src
    if [ "$kind" = lower ]; then
        printf 'module Probe exposing (..)\n\n\n%s : Int\n%s =\n    1\n' "$name" "$name" > names/src/Probe.gren
    else
        printf 'module Probe exposing (..)\n\n\ntype %s\n    = %s\n' "$name" "$name" > names/src/Probe.gren
    fi
    cp gren.json names/gren.json
    if (cd names && gren make Probe --output=/dev/null) >/dev/null 2>&1 </dev/null; then
        made=accepts
    else
        made=rejects
    fi
    printf '%-7s %-6s %-11s %s\n' "$kind" "$name" "$made" "$answer"
done < parser.txt
rm -rf names parser.txt
