#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf test app
git -c advice.detachedHead=false clone --quiet --branch 5.0.0 --depth 1 https://github.com/gren-lang/test.git test

# Fuzz.Float and MicroBitwiseExtra are internal modules, so the program puts the
# package's src/ on its own source path to call them directly.
mkdir -p src
cat > gren.json <<'JSON'
{
    "type": "application",
    "platform": "node",
    "source-directories": ["src", "test/src"],
    "gren-version": "0.6.6",
    "dependencies": {
        "direct": {
            "gren-lang/core": "7.4.2",
            "gren-lang/node": "6.1.3"
        },
        "indirect": {
            "gren-lang/url": "6.0.0"
        }
    }
}
JSON

cat > src/Main.gren <<'GREN'
module Main exposing (main)

import Fuzz.Float
import MicroBitwiseExtra
import Node
import Stream
import Task


row : Int -> Int -> String
row hi lo =
    "| ("
        ++ String.fromInt hi
        ++ ", "
        ++ String.fromInt lo
        ++ ") | "
        ++ String.fromInt (MicroBitwiseExtra.int52FromTuple { hi = hi, lo = lo })
        ++ " | "
        ++ String.fromFloat (Fuzz.Float.wellShrinkingFloat { hi = hi, lo = lo })
        ++ " | "
        ++ String.fromInt (hi * 0x100000000 + lo)
        ++ " |"


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram <| \env ->
        [ "| (hi, lo) | int52FromTuple | wellShrinkingFloat | hi * 2^32 + lo |"
        , "|---|---|---|---|"
        , row 0 0x7FFFFFFF
        , row 0 0x80000000
        , row 0 0xFFFFFFFF
        , row 1 0x80000000
        , "int52FromTuple (int52ToTuple 2147483648) = "
            ++ String.fromInt (MicroBitwiseExtra.int52FromTuple (MicroBitwiseExtra.int52ToTuple 2147483648))
        ]
            |> String.join "\n"
            |> (\text -> Stream.writeLineAsBytes text env.stdout)
            |> Task.map (\_ -> {})
            |> Task.onError (\_ -> Task.succeed {})
            |> Node.endSimpleProgram
GREN

gren make Main --output=app >/dev/null && node app
