# `SemanticVersion.fromString` drops parts that are not numbers before counting them

Against `gren` 0.6.6, `gren-lang/compiler-common` 4.0.0, `gren-lang/core`
7.6.1, `gren-lang/node` 6.2.0, node 22.

`./run.sh` builds and runs `src/Main.gren` under `devbox`, which prints
`SemanticVersion.fromString` of each string:

| call | answer | expected |
|---|---|---|
| `fromString "1.2.3"` | `Just 1.2.3` | `Just 1.2.3` |
| `fromString "1.2.3.x"` | `Just 1.2.3` | `Nothing` |
| `fromString "1.x.2.3"` | `Just 1.2.3` | `Nothing` |
| `fromString "1.2.3."` | `Just 1.2.3` | `Nothing` |
| `fromString "1.-1.2.3"` | `Just 1.2.3` | `Nothing` |
| `fromString "x.1.2.3"` | `Just 1.2.3` | `Nothing` |
| `fromString "1.2.3.4"` | `Nothing` | `Nothing` |

`fromString` splits on `.`, then keeps only the parts `String.toInt` reads and
that are not negative, and only then asks for exactly three. A part that is
not a number is removed rather than refused, so any string with three numeric
parts and others beside them parses as those three.

The fix is to refuse the string when any part is not a non-negative integer:
map the parts with `String.toInt` and match on exactly three `Just`s, rather
than `mapAndKeepJust` and `keepIf`.
