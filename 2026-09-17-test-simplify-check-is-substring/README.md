# A shrinking test passes when the value it got is a substring of the one it expected

`tests/src/Helpers.gren`'s `testSimplifyingWith` decides whether a fuzz test
shrank to the right value with `String.contains given description`, where
`given` is the shrunk value and `description` is the expected one as text.
Any value whose text appears inside the expected text passes.

`FuzzerTests`' `floatRange` row "(0,+) non-zero" expects
`1.1102230246251567e-15`. The fuzzer shrinks to `5`, and `"5"` is inside
`"1.1102230246251567e-15"`, so the test passes:

```
$ ./run.sh
$ gren make Main && node app
simplified to:       5
expected:            1.1102230246251567e-15
String.contains given description = True
given == description = False
```

The program builds the row the way the helper does, with its label, seed
(`2242652938`) and run count (1000).

## The fix

Compare exactly. `simplifiesTowardsMany` joins several expected values with
`|`, which is probably why the check was `contains`. Split on `|` and check
membership instead:

```gren
                Just g ->
                    if Array.member g (String.split "|" description) then
                        Ok {}
```

With that, the "(0,+) non-zero" row fails, and its expected value should be
`5`, which is what `floatRange 0 5` shrinks to.

- **Filed as:** not yet filed
- **Package:** `gren-lang/test` 5.0.0, its `tests/` (after the fixes in `2026-09-17-test-suite-does-not-build`)
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
