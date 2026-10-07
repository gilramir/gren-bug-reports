# `String.Parser.keyword` matches in front of a digit since 7.5.0

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.5.0, `gren-lang/node` 6.2.0, node 22

`./run.sh` builds and runs `src/Main.gren` under `devbox`. For each source it
prints whether `keyword "let" |> skip end` and `keyword "let"` alone succeed.
None of the sources but the last is the keyword `let`, so the third column
should be `Err` on every other row.

core 7.5.0:

```
letters	Err	Err
let_	Err	Err
let1	Err	Ok
let9x	Err	Ok
let١	Err	Ok
letés	Err	Err
let	Ok	Ok
```

With core 7.4.2 and node 6.1.3 in `gren.json`, `let1` and `let9x` give `Err`,
and `let١` and `letés` give `Ok` (core#144). The fix for core#144, `4250172`,
tests the next character against `\p{L}` or `_`, and so drops the digits that
`Char.isAlphaNum` had included. `[\p{L}\p{N}_]` keeps both.
