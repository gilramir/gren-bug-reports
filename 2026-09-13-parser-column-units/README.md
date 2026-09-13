# The parser's column after `😀` is 2 or 3 depending on which parser consumed it

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`DeadEnd`'s documentation says how columns count:

> The `col` increments as characters are chomped.

`chompIf` and `chompWhile` do that. `token`, `keyword`, `chompUntil`,
`chompUntilEndOr` and `lineComment` move the column by the number of UTF-16
code units instead, so after a character outside the Basic Multilingual Plane
the column is one larger than it should be:

```gren
run (chompIf (\_ -> True) |> andThen (\_ -> getPosition)) "😀b"   --> col 2
run (token "😀"            |> andThen (\_ -> getPosition)) "😀b"   --> col 3
```

Both consume the same one character, and they disagree about where they
stopped. A parser that reports an error position gets a column that depends on
how it happened to consume the text before the error — on a line with an emoji
in a comment before it, one column to the right for each one.

`😀` is U+1F600, stored as the two code units 0xD83D and 0xDE00. The offset
(`getOffset`) is documented to count code units, and that is not what this
report is about; the column is documented to count characters.

## Reproduction

`./run.sh` produces the rows below. Each row consumes exactly one `😀` (and, in
the lineComment row, the `--` before it) and then calls `getPosition`.

| parser | source | result | expected |
|---|---|---|---|
| `chompIf (\_ -> True)` | `"😀b"` | row 1, col 2 | row 1, col 2 |
| `chompWhile (\c -> c /= 'b')` | `"😀b"` | row 1, col 2 | row 1, col 2 |
| `token "😀"` | `"😀b"` | row 1, col **3** | row 1, col 2 |
| `chompUntil "b"` | `"😀b"` | row 1, col **3** | row 1, col 2 |
| `chompUntilEndOr "b"` | `"😀b"` | row 1, col **3** | row 1, col 2 |
| `lineComment "--"` | `"--😀\nb"` | row 1, col **5** | row 1, col 4 |
| `token "\n😀"` | `"\n😀b"` | row 2, col **3** | row 2, col 2 |

The first two rows are right, and they are the parsers that go through
`isSubChar`, which already moves the column by one for a surrogate pair.

## The cause and the fix

`isSubString` (behind `token` and `keyword`) and `findSubString` (behind
`chompUntil`, `chompUntilEndOr` and `lineComment`) compute the new column by
subtracting unit offsets: `col + sliceLength`, `sliceLength - newlineIndex`,
`col + idx`, `idx - lastNewlineIdx`. Each of those is a count of the code units
between two points, and it wants to be a count of the characters.

The smallest change is to count the characters in the text those offsets
delimit. In `isSubString`:

```gren
  , newCol =
    newlineIndices
      |> Array.last
      |> Maybe.map (\newlineIndex -> String.count (String.sliceUnits (newlineIndex + 1) sliceLength slice) + 1)
      |> Maybe.withDefault (col + String.count slice)
```

and the same shape for the two `newCol`s in `findSubString`, with `idx` and
`sliceLength` as the end of the text counted.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`, `String.Parser.Advanced` (and `String.Parser`, which delegates to it)
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2
