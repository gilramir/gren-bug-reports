# `Json.Decode.errorToString` writes the path to a failure backwards

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-json-error-path-reversed
**Filed:** not yet.

`errorToString` names where decoding failed as a path from the root, but any
path of two or more steps comes out reversed: `at [ "user", "address", "city" ]`
fails at `json.city.address.user`, a place that is not in the value, and an
array index can point at a different element than the one that failed. The
`Error` value itself is right; only the text is reversed, and also in "The
Json.Decode.oneOf at json… failed" and "Ran into a Json.Decode.oneOf with no
possibilities at json…". A path that reads the same both ways, such as
`[1][1]`, hides it.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Json.Decode as Decode exposing (Decoder)
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
    [ "| decoder | json | first line of errorToString | expected |"
    , "|---|---|---|---|"
    , row "field \"a\" int" (Decode.field "a" Decode.int) "{\"a\":true}" "json.a"
    , row "at [ \"user\", \"address\", \"city\" ] string" (Decode.at [ "user", "address", "city" ] Decode.string) "{\"user\":{\"address\":{\"city\":1}}}" "json.user.address.city"
    , row "field \"items\" (array (field \"id\" int))" (Decode.field "items" (Decode.array (Decode.field "id" Decode.int))) "{\"items\":[{\"id\":1},{\"id\":null}]}" "json.items[1].id"
    , row "array (array int)" (Decode.array (Decode.array Decode.int)) "[[1,2],[3,4],[true]]" "json[2][0]"
    ]


row : String -> Decoder a -> String -> String -> String
row name decoder json expected =
    let
        firstLine =
            when Decode.decodeString decoder json is
                Ok _ ->
                    "Ok"

                Err e ->
                    Decode.errorToString e
                        |> String.split "\n"
                        |> Array.first
                        |> Maybe.withDefault ""
    in
    "| `" ++ name ++ "` | `" ++ json ++ "` | " ++ firstLine ++ " | Problem with the value at " ++ expected ++ ": |"
```

Output:

```
| decoder | json | first line of errorToString | expected |
|---|---|---|---|
| `field "a" int` | `{"a":true}` | Problem with the value at json.a: | Problem with the value at json.a: |
| `at [ "user", "address", "city" ] string` | `{"user":{"address":{"city":1}}}` | Problem with the value at json.city.address.user: | Problem with the value at json.user.address.city: |
| `field "items" (array (field "id" int))` | `{"items":[{"id":1},{"id":null}]}` | Problem with the value at json.id[1].items: | Problem with the value at json.items[1].id: |
| `array (array int)` | `[[1,2],[3,4],[true]]` | Problem with the value at json[0][2]: | Problem with the value at json[2][0]: |
```

## Cause

`errorToStringHelp` in `src/Json/Decode.gren` walks the error from the outside
in and puts each step in front of the ones it has already seen:

```gren
errorToStringHelp err ([ fieldName ] ++ context)
...
errorToStringHelp err ([ indexName ] ++ context)
```

This is `elm/json`'s `fieldName :: context`, but `elm/json` reverses the list
before joining it (`String.join "" (List.reverse context)`), and the reverse
was dropped.

## Fix

Append instead; the three joins stay as they are:

```gren
errorToStringHelp err (context ++ [ fieldName ])
...
errorToStringHelp err (context ++ [ indexName ])
```
