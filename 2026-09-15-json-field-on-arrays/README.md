# `Json.Decode.field` succeeds on arrays, and on inherited properties of objects

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-json-field-on-arrays
**Filed:** not yet.

A decoder that accepts either an object or an array with `oneOf` takes the
object branch for an array when the field it asks for is `length`:
`field "length" int` succeeds on `[ 10, 20, 30 ]` and reads the array's length.
A field named `"0"`, `"1"` and so on reads an element. On an object, a field
that is not in the JSON but that every JavaScript object inherits, such as
`constructor` or `toString`, is found too, and its `Value` is a JavaScript
function (`Object` in the last row), which `Encode.encode` writes as
`undefined`, not JSON.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
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


type Clip
    = Duration Int
    | Samples (Array Int)


{-| A clip is either `{ "length": seconds }` or the array of its samples. -}
clip : Decoder Clip
clip =
    Decode.oneOf
        [ Decode.map Duration (Decode.field "length" Decode.int)
        , Decode.map Samples (Decode.array Decode.int)
        ]


table : Array String
table =
    [ "| call | result | expected |"
    , "|---|---|---|"
    , row "decodeString clip \"{ \\\"length\\\": 90 }\"" (Decode.decodeString clip "{ \"length\": 90 }") "Ok (Duration 90)"
    , row "decodeString clip \"[ 10, 20, 30 ]\"" (Decode.decodeString clip "[ 10, 20, 30 ]") "Ok (Samples [10,20,30])"
    , row "decodeString (field \"length\" int) \"[ 10, 20, 30 ]\"" (Decode.decodeString (Decode.field "length" Decode.int) "[ 10, 20, 30 ]") "Err"
    , row "decodeString (field \"0\" string) \"[ \\\"a\\\" ]\"" (Decode.decodeString (Decode.field "0" Decode.string) "[ \"a\" ]") "Err"
    , row "decodeString (field \"constructor\" value) \"{}\" \\|> map (encode 0)" (Decode.decodeString (Decode.field "constructor" Decode.value) "{}" |> Result.map (Encode.encode 0)) "Err"
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
| `decodeString clip "{ \"length\": 90 }"` | Ok (Duration 90) | Ok (Duration 90) |
| `decodeString clip "[ 10, 20, 30 ]"` | Ok (Duration 3) | Ok (Samples [10,20,30]) |
| `decodeString (field "length" int) "[ 10, 20, 30 ]"` | Ok 3 | Err |
| `decodeString (field "0" string) "[ \"a\" ]"` | Ok "a" | Err |
| `decodeString (field "constructor" value) "{}" \|> map (encode 0)` | Ok "undefined" | Err |
```

## Cause

The `FIELD` case of `_Json_runHelp` in `src/Gren/Kernel/Json.js` tests
`field in value`. An array is a JavaScript object, and `in` also looks along
the prototype chain:

```js
if (typeof value !== "object" || value === null || !(field in value)) {
```

## Fix

Ask for an own property of something that is not an array, as `keyValuePairs`
already does:

```js
case __1_FIELD:
  var field = decoder.__field;
  if (
    typeof value !== "object" ||
    value === null ||
    _Json_isArray(value) ||
    !Object.hasOwn(value, field)
  ) {
```
