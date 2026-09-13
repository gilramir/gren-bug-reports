# `chompUntilEndOr` reports a column one too small when it reaches the end after a newline

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

A parser that runs to the end of its input should leave `getPosition` pointing
just past the last character. `chompUntilEndOr` does, unless the text it ran
over contains a newline — then the column is one too small:

```gren
run (chompUntilEndOr "X" |> andThen (\_ -> getPosition)) "a\nbc"
--> { row = 2, col = 2 }     -- the end of "bc" is col 3
```

`chompWhile (\_ -> True)` over the same source says col 3, and so does
`chompUntilEndOr` itself when it finds its string instead of running out
(`"a\nbcX"` stops before the `X`, at col 3). So a position taken after
`chompUntilEndOr` depends on whether the input ended, and anything that
reports an error location from it — an unterminated comment at the end of a
file is the usual case — points one column to the left.

## Reproduction

`./run.sh` produces the rows below. Each row runs one parser and then
`getPosition`.

| parser | source | result | expected |
|---|---|---|---|
| `chompUntilEndOr "X"` | `"a\nbc"` | row 2, col 2 | row 2, col 3 |
| `chompUntilEndOr "X"` | `"a\nbcdef"` | row 2, col 5 | row 2, col 6 |
| `chompUntilEndOr "X"` | `"abc"` | row 1, col 4 | row 1, col 4 |
| `chompWhile (\_ -> True)` | `"a\nbc"` | row 2, col 3 | row 2, col 3 |
| `chompUntilEndOr "X"` | `"a\nbcX"` | row 2, col 3 | row 2, col 3 |

The last three rows are already right: no newline, a different parser over the
same text, and the same parser finding what it looks for.

## The cause and the fix

`findSubString` in `String/Parser/Advanced.gren` computes the column two ways,
one for a match and one for running out:

```gren
    Just idx ->
      ...
      , newCol =
        relevantNewlines
          |> Array.last
          |> Maybe.map (\lastNewlineIdx -> idx - lastNewlineIdx)
          ...

    Nothing ->
      ...
      , newCol =
        newlines
          |> Array.last
          |> Maybe.map (\lastNewlineIdx -> sliceLength - lastNewlineIdx - 1)
          ...
```

`idx` and `sliceLength` are the same kind of number — the offset where the
search stopped — so the two lines should be the same expression. The `- 1` is
the defect:

```gren
          |> Maybe.map (\lastNewlineIdx -> sliceLength - lastNewlineIdx)
```

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`, `String.Parser.Advanced` (and `String.Parser`, which delegates to it)
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2
