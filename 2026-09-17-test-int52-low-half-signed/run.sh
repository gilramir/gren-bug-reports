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
import MicroBitwiseExtra as Bitwise
import Node
import Stream
import Task


rows : Array { hi : Int, lo : Int }
rows =
    [ { hi = 0, lo = 0x7FFFFFFE }
    , { hi = 0, lo = 0x7FFFFFFF }
    , { hi = 0, lo = 0x80000000 }
    , { hi = 0, lo = 0xFFFFFFFF }
    , { hi = 1, lo = 0 }
    , { hi = 1, lo = 0x80000000 }
    ]


show : { hi : Int, lo : Int } -> String
show t =
    "{ hi = " ++ String.fromInt t.hi ++ ", lo = " ++ String.fromInt t.lo ++ " }"


line : { hi : Int, lo : Int } -> String
line t =
    show t
        ++ "  int52FromTuple = "
        ++ String.fromInt (Bitwise.int52FromTuple t)
        ++ "  wellShrinkingFloat = "
        ++ String.fromFloat (Fuzz.Float.wellShrinkingFloat t)


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram
        (\env ->
            Node.endSimpleProgram
                (Stream.writeLineAsBytes
                    (String.join "\n"
                        (Array.map line rows
                            ++ [ "int52FromTuple (int52ToTuple 2147483648) = "
                                    ++ String.fromInt (Bitwise.int52FromTuple (Bitwise.int52ToTuple 2147483648))
                               ]
                        )
                    )
                    env.stdout
                    |> Task.map (\_ -> {})
                    |> Task.onError (\_ -> Task.succeed {})
                )
        )
GREN

echo '$ gren make Main && node app'
gren make Main --output=app >/dev/null && node app
