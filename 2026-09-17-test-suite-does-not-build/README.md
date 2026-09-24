# `gren-lang/test`'s own test suite does not build with gren 0.6.6

**Repository:** `gren-lang/test`
**Found against:** `gren` 0.6.6, `gren-lang/test` 5.0.0, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, `gren-lang/test-runner-node` 7.0.0, node 22

`tests/` was last changed on 2024-06-22 and still targets Gren 0.4, so the
suite that checks the fuzzer and its shrinking cannot be run on the current
compiler. `run-tests.sh` passes a file path to `gren make`, `tests/gren.json`
asks for `core` 5.0.0, and with the dependencies moved to the current releases
four modules do not parse.

## Reproduction

`./run.sh` does all of this, using the `gren` and `node` that devbox pins.

```sh
git clone --branch 5.0.0 --depth 1 https://github.com/gren-lang/test.git
cd test/tests

./run-tests.sh

gren make TestsMain --output=/dev/null

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
            "gren-lang/test": "local:..",
            "gren-lang/test-runner-node": "7.0.0"
        },
        "indirect": {
            "gren-lang/url": "6.0.0"
        }
    }
}
JSON
gren make TestsMain --output=/dev/null 2>&1 | grep -o -- '-- [A-Z].*'
```

Output (the second command's download progress left out):

```
$ ./run-tests.sh
I'm having trouble with this argument:

    src/TestsMain.gren

It's supposed to be a <module-names> value, like one of these:

    Main
    My.Module
$ gren make TestsMain --output=/dev/null
-- CANNOT FIND COMPATIBLE VERSION----------------------------------------------

I cannot find a version of gren-lang/core that is compatible with your existing dependencies.

These are the conflicting versions:

    5.0.0 <= v < 5.0.1
    7.0.0 <= v < 8.0.0

$ gren make TestsMain --output=/dev/null 2>&1 | grep -o -- '-- [A-Z].*'
-- UNEXPECTED ARROW --------------------------------------- src/FuzzerTests.gren
-- UNEXPECTED ARROW ------------------------------------------- src/Helpers.gren
-- UNEXPECTED ARROW --------------------------------------- src/RunnerTests.gren
-- MISSING EXPRESSION ------------------------- src/ShrinkingChallengeTests.gren
```

## Fix

| what | where | today's spelling |
|---|---|---|
| `case … of` | 30 places, 5 modules | `when … is` |
| a variant with more than one parameter | `Heap`, and the calculator's `Add` and `Div`, in `ShrinkingChallengeTests` | a record |
| `AbsoluteOrRelative a b` | `FloatWithinTests`, 5 places | `AbsoluteOrRelative { absolute = a, relative = b }` |
| `String.length`, `Array.flatMap`, `Array.filterMap` | `Helpers`, `FuzzerTests`, `ShrinkingChallengeTests` | `String.unitLength`, `Array.mapAndFlatten`, `Array.mapAndKeepJust` |
| `gren make src/TestsMain.gren` | `run-tests.sh` | `gren make TestsMain` |
| `gren-version` 0.4.0, `core` 5.0.0, `node` 4.0.0, `test-runner-node` 4.0.0 | `tests/gren.json` | 0.6.6, 7.4.2, 6.1.3, 7.0.0 |

With these, on gren 0.6.6, `TestsMain` passes 382 of 382 and `SeedTestsMain` 1
of 1.
