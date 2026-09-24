# A shrinking test in `tests/` passes when the value it got is a substring of the one it expected

**Repository:** `gren-lang/test`
**Found against:** `gren` 0.6.6, `gren-lang/test` 5.0.0, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`tests/src/Helpers.gren`'s `testSimplifyingWith` passes when
`String.contains given description`, where `given` is the value the fuzzer shrank
to and `description` is the expected value as text. So `FuzzerTests`'
`floatRange` row "(0,+) non-zero", which expects `1.1102230246251567e-15`,
passes although the fuzzer shrinks to `5`: `"5"` is inside
`"1.1102230246251567e-15"`.

## Reproduction

`./run.sh` does all of this, using the `gren` and `node` that devbox pins.

The row built as the helper builds it: the same label, seed `2242652938` and
1,000 runs.

`gren.json`: a node application with `"gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3", "gren-lang/test": "5.0.0"` (indirect `"gren-lang/url": "6.0.0"`).

`src/Main.gren`:

```gren
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
```

```sh
gren make Main --output=app && node app
```

Output:

```
| given | description | String.contains given description | given == description |
|---|---|---|---|
| 5 | 1.1102230246251567e-15 | True | False |
```

## Fix

`simplifiesTowardsMany` joins several expected values with `|`, which is
probably why the check is `contains`. Split and compare exactly:

```gren
                Just g ->
                    if Array.member g (String.split "|" description) then
                        Ok {}
```

The "(0,+) non-zero" row then fails, and its expected value should be `5`.
The suite does not build on 0.6.6 as released (see the report on `tests/` not
building); this was found with that report's changes applied.
