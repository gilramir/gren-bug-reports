#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf app src
mkdir -p src
cat > gren.json <<'JSON'
{
    "type": "application",
    "platform": "node",
    "source-directories": ["src"],
    "gren-version": "0.6.6",
    "dependencies": {
        "direct": {
            "gren-lang/core": "7.4.2",
            "gren-lang/node": "6.1.3",
            "gren-lang/test": "5.0.0"
        },
        "indirect": {
            "gren-lang/url": "6.0.0"
        }
    }
}
JSON

# `Queue` is internal to gren-lang/test, so the published module is copied in
# beside Main, unchanged, from gren's package cache once it has fetched it.
cat > src/Main.gren <<'GREN'
module Main exposing (main)

import Node
import Stream
import Task


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram <| \env -> Node.endSimpleProgram (Task.succeed {})
GREN
gren make Main --output=app >/dev/null
cp "$HOME/.cache/gren/0.6.6/packages/gren-lang_test__5_0_0/src/Queue.gren" src/Queue.gren

cat > src/Main.gren <<'GREN'
module Main exposing (main)

import Node
import Queue
import Stream
import Task


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram <| \env ->
        let
            q =
                Queue.singleton 3
                    |> Queue.enqueue 4
                    |> Queue.updateFront (\_ -> Nothing)

            rest =
                (Queue.dequeue q).rest
        in
        [ "| on `singleton 3 |> enqueue 4 |> updateFront (\\_ -> Nothing)` | result |"
        , "|---|---|"
        , "| `toArray` | `" ++ Debug.toString (Queue.toArray q) ++ "` |"
        , "| `size` | `" ++ Debug.toString (Queue.size q) ++ "` |"
        , "| `front` | `" ++ Debug.toString (Queue.front q) ++ "` |"
        , "| `(dequeue q).first` | `" ++ Debug.toString (Queue.dequeue q).first ++ "` |"
        , "| `toArray (dequeue q).rest` | `" ++ Debug.toString (Queue.toArray rest) ++ "` |"
        ]
            |> String.join "\n"
            |> (\text -> Stream.writeLineAsBytes text env.stdout)
            |> Task.map (\_ -> {})
            |> Task.onError (\_ -> Task.succeed {})
            |> Node.endSimpleProgram
GREN

gren make Main --output=app >/dev/null && node app
