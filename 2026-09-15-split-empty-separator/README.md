# `String.split ""` cuts a character above U+FFFF into its two surrogates

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-split-empty-separator
**Filed:** not yet.

`String.split "" s` is how a string is taken apart into characters, usually to
work on the pieces and join them again, as in
`String.split "" s |> Array.reverse |> String.join ""`. A character above
U+FFFF (emoji, most mathematical alphanumerics, the higher CJK extensions)
comes out as two pieces, one lone surrogate each, so the reversed string has
the halves in the wrong order and is not text. Everything else in `String`
counts that character as one.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Math
import Node
import Stream
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


s : String
s =
    -- "a", U+1F600, "b": three characters; U+1F600 is the two UTF-16 code units 0xD83D 0xDE00
    "a😀b"


table : Array String
table =
    [ "| call | result | expected |"
    , "|---|---|---|"
    , "| `String.count s` | " ++ String.fromInt (String.count s) ++ " | 3 |"
    , "| `Array.length (String.split \"\" s)` | " ++ String.fromInt (Array.length (String.split "" s)) ++ " | 3 |"
    , "| code points of `String.split \"\" s \\|> Array.reverse \\|> String.join \"\"` | "
        ++ codePoints (String.split "" s |> Array.reverse |> String.join "")
        ++ " | 0x62 0x1F600 0x61 |"
    ]


codePoints : String -> String
codePoints str =
    String.foldl (\c acc -> Array.pushLast ("0x" ++ hex (Char.toCode c)) acc) [] str
        |> String.join " "


hex : Int -> String
hex n =
    if n < 16 then
        String.slice n (n + 1) "0123456789ABCDEF"

    else
        hex (n // 16) ++ hex (Math.modBy 16 n)
```

Output:

```
| call | result | expected |
|---|---|---|
| `String.count s` | 3 | 3 |
| `Array.length (String.split "" s)` | 4 | 3 |
| code points of `String.split "" s \|> Array.reverse \|> String.join ""` | 0x62 0xDE00 0xD83D 0x61 | 0x62 0x1F600 0x61 |
```

## Cause

`_String_split` in `src/Gren/Kernel/String.js` is `str.split(sep)`, and
`"a😀b".split("")` splits between UTF-16 code units.

## Fix

```js
var _String_split = F2(function (sep, str) {
  return sep === "" ? Array.from(str) : str.split(sep);
});
```

A non-empty separator is not affected: a well-formed separator can only match
whole characters of a well-formed string.
