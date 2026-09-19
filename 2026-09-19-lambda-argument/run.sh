#!/bin/sh
set -e
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# What compiler-common's parser says about each module, and the modules
# themselves, which `gren make` is then asked about.
gren run Main > parser.txt

printf '%-21s %-11s %s\n' "case" "gren make" "compiler-common"
while read -r name answer; do
    rm -rf cases && mkdir -p cases/src
    cp gren.json cases/gren.json
    sed -n "/name = \"$name\"/{n;p}" src/Main.gren \
        | sed 's/^ *, source = "//; s/"$//' \
        | sed 's/\\n/\n/g; s/\\\\/\\/g' > cases/src/Probe.gren
    if (cd cases && gren make Probe --output=/dev/null) >/dev/null 2>&1 </dev/null; then
        made=accepts
    else
        made=rejects
    fi
    printf '%-21s %-11s %s\n' "$name" "$made" "$answer"
done < parser.txt
rm -rf cases parser.txt
