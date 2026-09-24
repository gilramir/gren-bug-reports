# `Json.Encode.object` and `Json.Encode.dict` drop a member named `__proto__`

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-json-encode-object-proto
**Filed:** not yet.

`"__proto__"` is an ordinary JSON key, and `Json.Decode` reads it as one. Decoding
`{"__proto__":1,"a":2}` with `Decode.dict` and encoding the result with
`Encode.dict` gives `{"a":2}`: the member is lost, with no error. `Encode.object`
drops it the same way.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Node
import Stream
import Task


decoded : Dict.Dict String Int
decoded =
    Decode.decodeString (Decode.dict Decode.int) "{\"__proto__\":1,\"a\":2}"
        |> Result.withDefault Dict.empty


rows : Array String
rows =
    [ "| call | result | expected |"
    , "|---|---|---|"
    , "| `Dict.keys decoded` | "
        ++ String.join ", " (Dict.keys decoded)
        ++ " | __proto__, a |"
    , "| `Encode.encode 0 (Encode.dict identity Encode.int decoded)` | "
        ++ Encode.encode 0 (Encode.dict identity Encode.int decoded)
        ++ " | {\"__proto__\":1,\"a\":2} |"
    , "| `Encode.encode 0 (Encode.object [ { key = \"__proto__\", value = Encode.int 1 } ])` | "
        ++ Encode.encode 0 (Encode.object [ { key = "__proto__", value = Encode.int 1 } ])
        ++ " | {\"__proto__\":1} |"
    , "| `Encode.encode 0 (Encode.object [ { key = \"__proto__\", value = Encode.object [ { key = \"x\", value = Encode.int 1 } ] } ])` | "
        ++ Encode.encode 0 (Encode.object [ { key = "__proto__", value = Encode.object [ { key = "x", value = Encode.int 1 } ] } ])
        ++ " | {\"__proto__\":{\"x\":1}} |"
    ]


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Node.endSimpleProgram
            (Stream.writeLineAsBytes (String.join "\n" rows) env.stdout
                |> Task.map (\_ -> {})
                |> Task.onError (\_ -> Task.succeed {})
            )
```

Output:

```
| call | result | expected |
|---|---|---|
| `Dict.keys decoded` | __proto__, a | __proto__, a |
| `Encode.encode 0 (Encode.dict identity Encode.int decoded)` | {"a":2} | {"__proto__":1,"a":2} |
| `Encode.encode 0 (Encode.object [ { key = "__proto__", value = Encode.int 1 } ])` | {} | {"__proto__":1} |
| `Encode.encode 0 (Encode.object [ { key = "__proto__", value = Encode.object [ { key = "x", value = Encode.int 1 } ] } ])` | {} | {"__proto__":{"x":1}} |
```

## Cause

`_Json_addField` in `src/Gren/Kernel/Json.js`, which both `Encode.object` and
`Encode.dict` fold with, assigns the member:

```js
object[key] = unwrapped;
```

On an object made with `{}`, assigning to `__proto__` calls the inherited
`Object.prototype.__proto__` setter instead of creating an own property. When the
value is an object it becomes the new object's prototype; otherwise nothing
happens. Either way `JSON.stringify` has nothing to write. (In the prototype case,
`Decode.field "x"` on that value then finds `x` on an object that has no such
member.) `JSON.parse` defines the property rather than assigning it, which is why
decoding is not affected.

## Fix

Define the property, as `JSON.parse` does:

```js
Object.defineProperty(object, key, {
  value: unwrapped,
  writable: true,
  enumerable: true,
  configurable: true,
});
```

A duplicate key still keeps its last value at its first position, as the
assignment did.
