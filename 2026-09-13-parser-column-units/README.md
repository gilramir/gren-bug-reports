# `String.Parser`'s column counts UTF-16 code units after `token`, `keyword`, `chompUntil`, `chompUntilEndOr` and `lineComment`

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-13-parser-column-units
**Filed:** not yet.

`DeadEnd`'s documentation says "The `col` increments as characters are
chomped", and `chompIf` and `chompWhile` do that. `token`, `keyword`,
`chompUntil`, `chompUntilEndOr` and `lineComment` move the column by UTF-16
code units instead, so after a character above U+FFFF the column is one too
large, and an error position depends on which parser consumed the text before
it: one column to the right for each emoji earlier on the line, in a comment or
a string token. (`getOffset` is documented to count code units; this is only
about the column.)

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Node
import Stream
import String.Parser as P
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram
        (\env ->
            Stream.writeLineAsBytes (String.join "\n" table) env.stdout
                |> Task.map (\_ -> {})
                |> Task.onError (\_ -> Task.succeed {})
                |> Node.endSimpleProgram
        )


{-| 😀 is U+1F600: one character, two UTF-16 code units (0xD83D 0xDE00).
Each parser consumes exactly one 😀 (lineComment also the "--" before it).
-}
table : Array String
table =
    [ "| parser | source | result | expected |"
    , "|---|---|---|---|"
    , row "chompIf (\\_ -> True)" (P.chompIf (\_ -> True)) "😀b" "row 1, col 2"
    , row "token \"😀\"" (P.token "😀") "😀b" "row 1, col 2"
    , row "chompUntil \"b\"" (P.chompUntil "b") "😀b" "row 1, col 2"
    , row "chompUntilEndOr \"b\"" (P.chompUntilEndOr "b") "😀b" "row 1, col 2"
    , row "lineComment \"--\"" (P.lineComment "--") "--😀\nb" "row 1, col 4"
    , row "token \"\\n😀\"" (P.token "\n😀") "\n😀b" "row 2, col 2"
    ]


{-| Run the parser, then `getPosition`. -}
row : String -> P.Parser a -> String -> String -> String
row name parser source expected =
    let
        result =
            when P.run (parser |> P.andThen (\_ -> P.getPosition)) source is
                Ok pos ->
                    "row " ++ String.fromInt pos.row ++ ", col " ++ String.fromInt pos.col

                Err _ ->
                    "Err"
    in
    "| `" ++ name ++ "` | `\"" ++ String.replace "\n" "\\n" source ++ "\"` | " ++ result ++ " | " ++ expected ++ " |"
```

Output:

```
| parser | source | result | expected |
|---|---|---|---|
| `chompIf (\_ -> True)` | `"😀b"` | row 1, col 2 | row 1, col 2 |
| `token "😀"` | `"😀b"` | row 1, col 3 | row 1, col 2 |
| `chompUntil "b"` | `"😀b"` | row 1, col 3 | row 1, col 2 |
| `chompUntilEndOr "b"` | `"😀b"` | row 1, col 3 | row 1, col 2 |
| `lineComment "--"` | `"--😀\nb"` | row 1, col 5 | row 1, col 4 |
| `token "\n😀"` | `"\n😀b"` | row 2, col 3 | row 2, col 2 |
```

## Cause

`isSubString` (behind `token` and `keyword`) and `findSubString` (behind
`chompUntil`, `chompUntilEndOr` and `lineComment`) in
`src/String/Parser/Advanced.gren` compute the new column by subtracting code
unit offsets: `col + sliceLength`, `sliceLength - newlineIndex`, `col + idx`,
`idx - lastNewlineIdx`. `isSubChar`, behind `chompIf` and `chompWhile`, already
moves the column by one for a surrogate pair.

## Fix

Count the characters in the text those offsets delimit. In `isSubString`:

```gren
  , newCol =
    newlineIndices
      |> Array.last
      |> Maybe.map (\newlineIndex -> String.count (String.sliceUnits (newlineIndex + 1) sliceLength slice) + 1)
      |> Maybe.withDefault (col + String.count slice)
```

and the same shape for the two `newCol`s in `findSubString`, with `idx` and
`sliceLength` as the end of the text counted.
