# `String.Parser.chompUntilEndOr` leaves the column one short when it runs to the end past a newline

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-13-chompuntilendor-column
**Filed:** not yet.

When `chompUntilEndOr` does not find its string it consumes the rest of the
input, and `getPosition` afterwards should point just past the last character.
If the text it consumed contains a newline, the column is one too small. It is
right with no newline, when the string is found, and for `chompWhile` over the
same text, so the position depends on whether the input ended: an error
reported after an unterminated comment at the end of a file points one column
to the left.

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


table : Array String
table =
    [ "| parser | source | result | expected |"
    , "|---|---|---|---|"
    , row "chompUntilEndOr \"X\"" (P.chompUntilEndOr "X") "a\nbc" "row 2, col 3"
    , row "chompUntilEndOr \"X\"" (P.chompUntilEndOr "X") "abc" "row 1, col 4"
    , row "chompUntilEndOr \"X\"" (P.chompUntilEndOr "X") "a\nbcX" "row 2, col 3"
    , row "chompWhile (\\_ -> True)" (P.chompWhile (\_ -> True)) "a\nbc" "row 2, col 3"
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
| `chompUntilEndOr "X"` | `"a\nbc"` | row 2, col 2 | row 2, col 3 |
| `chompUntilEndOr "X"` | `"abc"` | row 1, col 4 | row 1, col 4 |
| `chompUntilEndOr "X"` | `"a\nbcX"` | row 2, col 3 | row 2, col 3 |
| `chompWhile (\_ -> True)` | `"a\nbc"` | row 2, col 3 | row 2, col 3 |
```

## Cause

`findSubString` in `src/String/Parser/Advanced.gren` computes the column one
way for a match and another for running out:

```gren
    Just idx ->
      ...
          |> Maybe.map (\lastNewlineIdx -> idx - lastNewlineIdx)

    Nothing ->
      ...
          |> Maybe.map (\lastNewlineIdx -> sliceLength - lastNewlineIdx - 1)
```

`idx` and `sliceLength` are the same kind of number, the offset where the
search stopped, so the two should be the same expression.

## Fix

```gren
          |> Maybe.map (\lastNewlineIdx -> sliceLength - lastNewlineIdx)
```
