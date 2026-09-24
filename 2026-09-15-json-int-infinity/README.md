# `Json.Decode.int` accepts `1e400` and answers an `Int` that is `Infinity`

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-json-int-infinity
**Filed:** not yet.

`1e400` is valid JSON, and `JSON.parse` reads it as `Infinity` because it is
too large for a double. `Json.Decode.int` then accepts it, so the program holds
an `Int` that is not an integer and nothing downstream can tell:
`String.fromInt` writes `"Infinity"`, which `String.toInt` does not read back,
and `n - n` is `NaN`. (`Json.Decode.float` answering `Infinity` is not this
bug; that is the double the text rounds to.)

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Json.Decode as Decode
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


table : Array String
table =
    [ "| call | result | expected |"
    , "|---|---|---|"
    , row "decodeString int \"12\"" (Decode.decodeString Decode.int "12") "Ok 12"
    , row "decodeString int \"1e400\"" (Decode.decodeString Decode.int "1e400") "Err"
    , row "decodeString int \"-1e400\"" (Decode.decodeString Decode.int "-1e400") "Err"
    , row "decodeString int \"1e400\" \\|> map (String.fromInt >> String.toInt)" (Decode.decodeString Decode.int "1e400" |> Result.map (String.fromInt >> String.toInt)) "Err"
    , row "decodeString int \"1e400\" \\|> map (\\n -> n - n)" (Decode.decodeString Decode.int "1e400" |> Result.map (\n -> n - n)) "Err"
    ]


row : String -> Result Decode.Error a -> String -> String
row call result expected =
    let
        shown =
            when result is
                Ok _ ->
                    Debug.toString result

                Err _ ->
                    "Err"
    in
    "| `" ++ call ++ "` | " ++ shown ++ " | " ++ expected ++ " |"
```

Output:

```
| call | result | expected |
|---|---|---|
| `decodeString int "12"` | Ok 12 | Ok 12 |
| `decodeString int "1e400"` | Ok Infinity | Err |
| `decodeString int "-1e400"` | Ok -Infinity | Err |
| `decodeString int "1e400" \|> map (String.fromInt >> String.toInt)` | Ok Nothing | Err |
| `decodeString int "1e400" \|> map (\n -> n - n)` | Ok NaN | Err |
```

## Cause

`_Json_decodeInt` in `src/Gren/Kernel/Json.js`:

```js
  return typeof value !== "number"
    ? _Json_expecting("an INT", value)
    : Math.trunc(value) === value
      ? __Result_Ok(value)
      : isFinite(value) && !(value % 1)
        ? __Result_Ok(value)
        : _Json_expecting("an INT", value);
```

`Math.trunc(Infinity) === Infinity`, so the first test says yes and the second,
which checks `isFinite`, is never reached.

## Fix

```js
var _Json_decodeInt = _Json_decodePrim(function (value) {
  return typeof value === "number" && Number.isInteger(value)
    ? __Result_Ok(value)
    : _Json_expecting("an INT", value);
});
```

`Number.isInteger` is false for both infinities and for `NaN`.
