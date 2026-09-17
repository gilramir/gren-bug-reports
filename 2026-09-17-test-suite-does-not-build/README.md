# The test suite does not build with gren 0.6.6

`tests/` in `gren-lang/test` 5.0.0 was last changed on 2024-06-22 and still
targets Gren 0.4. Its `gren.json` names `gren-version` 0.4.0, `core` 5.0.0,
`node` 4.0.0 and `test-runner-node` 4.0.0, and `run-tests.sh` passes a file path
to `gren make`, which 0.6.6 does not accept.

With the dependencies moved to the current releases, the suite does not parse:

```
$ ./run.sh
$ grep gren-version gren.json
    "gren-version": "0.4.0",
$ gren make TestsMain
-- UNEXPECTED ARROW ------------------------------------------- src/Helpers.gren
-- UNEXPECTED ARROW --------------------------------------- src/RunnerTests.gren
-- MISSING EXPRESSION ------------------------- src/ShrinkingChallengeTests.gren
```

The suite writes `case … of` in 30 places. Past the parse errors it uses
constructors with more than one parameter (`Heap`, and the calculator's `Add`
and `Div`), the old two-argument `AbsoluteOrRelative`, and `String.length`,
`Array.flatMap` and `Array.filterMap`.

## The fix

`case … of` becomes `when … is`; `run-tests.sh` passes `TestsMain` and
`SeedTestsMain`; the three variants take records; `AbsoluteOrRelative` takes
`{ absolute, relative }`; and the three functions become `String.unitLength`,
`Array.mapAndFlatten` and `Array.mapAndKeepJust`. With those, on gren 0.6.6,
`TestsMain` passes 382 of 382 and `SeedTestsMain` 1 of 1.

- **Filed as:** not yet filed
- **Package:** `gren-lang/test` 5.0.0
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, `gren-lang/test-runner-node` 7.0.0, node 22
