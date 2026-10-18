# `chompUntil`, `chompUntilEndOr` and `lineComment` overshoot by the offset they start at

Against `gren` 0.6.6, `gren-lang/core` 7.6.0 (and 7.5.0), `gren-lang/node`
6.2.0, node 22.

`./run.sh` builds and runs `src/Main.gren` under `devbox`. Each row runs a
`token` (or nothing) and then the chomper, and prints the string the chomper
consumed and the offset, row and column it left the parser at:

| parser | source | answer | expected |
|---|---|---|---|
| `chompUntil "c"` | `"abc"` | "ab" offset 2, row 1, col 3 | "ab" offset 2, row 1, col 3 |
| `token "a", then chompUntil "c"` | `"abc"` | "bc" offset 3, row 1, col 3 | "b" offset 2, row 1, col 3 |
| `token "abcd", then chompUntil "h"` | `"abcdefghij"` | "efghij" offset 11, row 1, col 8 | "efg" offset 7, row 1, col 8 |
| `chompUntilEndOr "\n"` | `"-- c\nxyz"` | "-- c" offset 4, row 1, col 5 | "-- c" offset 4, row 1, col 5 |
| `token "x ", then chompUntilEndOr "\n"` | `"x -- c\nyz"` | "-- c\ny" offset 8, row 1, col 7 | "-- c" offset 6, row 1, col 7 |
| `token "x ", then lineComment "--"` | `"x -- c\nyz"` | "-- c\nyz" offset 10, row 1, col 7 | "-- c" offset 6, row 1, col 7 |

It then runs `token "x" |> skip spaces |> skip (lineComment "--") |> skip
(chompChar '\n') |> skip (token "y") |> skip end` on `"x -- c\ny"`, which
fails at row 1, column 7. With core 7.4.2 (change `gren.json` to core 7.4.2
and node 6.1.3) every row is as expected and that parses.

`findSubString` in `src/String/Parser/Advanced.gren` adds the starting offset
to `String.unitFirstIndexOfFrom`'s answer, which is already an index into the
whole string: `newOffset = offset + idx` should be `newOffset = idx`.
