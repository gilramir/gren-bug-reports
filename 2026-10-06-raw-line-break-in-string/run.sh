#!/bin/sh
set -e
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# compiler-common's answer for each case, with the module it parsed. Then the
# same module is compiled by `gren make`, and `gren run` prints its Probe.v.
gren run Main > parser.txt

printf '%-20s  %-22s  %s\n' "case" "gren make" "compiler-common"
node -e '
const fs = require("fs");
for (const row of fs.readFileSync("parser.txt", "utf8").replace(/\n$/, "").split("\0")) {
  const [name, answer, source] = row.split("\t");
  fs.writeFileSync("case-" + name + ".tsv", answer + "\n");
  fs.writeFileSync("case-" + name + ".gren", source);
}'
for f in case-*.gren; do
    name=${f#case-}; name=${name%.gren}
    rm -rf cases && mkdir -p cases/src
    cp gren.json cases/gren.json
    cp src/Show.gren cases/src/Show.gren
    cp "$f" cases/src/Probe.gren
    cat > cases/src/Main.gren <<'GREN'
module Main exposing (main)

import Init
import Node
import Probe
import Show exposing (show)
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram
        (\env ->
            Stream.writeLineAsBytes (show Probe.v) env.stdout
                |> Task.map (\_ -> {})
                |> Task.onError (\_ -> Task.succeed {})
                |> Node.endSimpleProgram
        )
GREN
    if (cd cases && gren make Main --output=/dev/null) >/dev/null 2>&1 </dev/null; then
        made=$(cd cases && gren run Main </dev/null)
    else
        made=refused
    fi
    printf '%-20s  %-22s  %s\n' "$name" "$made" "$(cat "case-$name.tsv")"
done
rm -rf cases parser.txt case-*
