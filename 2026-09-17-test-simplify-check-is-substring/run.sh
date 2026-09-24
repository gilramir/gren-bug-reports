#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf app
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

# The test from tests/src/FuzzerTests.gren, "(0,+) non-zero", built the way
# tests/src/Helpers.gren's simplifiesTowardsWith and testSimplifyingWith build
# it: the same label, seed and run count, and the same String.contains check.
cat > src/Main.gren <<'GREN'
module Main exposing (main)

import Expect
import Fuzz
import Node
import Random
import Stream
import Task
import Test
import Test.Runner


expected : String
expected =
    Debug.toString 1.1102230246251567e-15


row : String
row =
    let
        test =
            Test.fuzz (Fuzz.floatRange 0 5)
                ("[(0,+) non-zero] Simplifies towards " ++ expected)
                (\n -> Expect.equal True (n == 0) |> Expect.onFail expected)
    in
    when Test.Runner.fromTest 1000 (Random.initialSeed 2242652938) test is
        Test.Runner.Plain [ runner ] ->
            when Array.first (runner.run {}) |> Maybe.andThen Test.Runner.getFailureReason is
                Just { given = Just given, description } ->
                    "| " ++ given ++ " | " ++ description
                        ++ " | " ++ Debug.toString (String.contains given description)
                        ++ " | " ++ Debug.toString (given == description) ++ " |"

                _ ->
                    "the test did not fail with a given value"

        _ ->
            "unexpected runners"


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram <| \env ->
        [ "| given | description | String.contains given description | given == description |"
        , "|---|---|---|---|"
        , row
        ]
            |> String.join "\n"
            |> (\text -> Stream.writeLineAsBytes text env.stdout)
            |> Task.map (\_ -> {})
            |> Task.onError (\_ -> Task.succeed {})
            |> Node.endSimpleProgram
GREN

gren make Main --output=app >/dev/null && node app
