# `Json.Decode.field` finds fields in arrays, and inherited properties in objects

## Summary

A decoder that accepts one of two shapes, an object or an array, picks the
object branch for an array whenever the field it asks for is `length`:

```gren
type Clip
    = Duration Int
    | Samples (Array Int)

-- A clip is either { "length": seconds } or the array of its samples.
clip : Decoder Clip
clip =
    Decode.oneOf
        [ Decode.map Duration (Decode.field "length" Decode.int)
        , Decode.map Samples (Decode.array Decode.int)
        ]
```

`decodeString clip "[ 10, 20, 30 ]"` answers `Duration 3`. `field "length"`
succeeded on an array, which is not a JSON object and has no fields, and read
the array's length. The same happens for a field named `"0"`, `"1"` and so on,
which read elements. On an object, a field that is not in the JSON but that
every JavaScript object inherits, such as `constructor` or `toString`, is found
too, and its value is a JavaScript function.

## Reproduction

| call | result | expected |
|---|---|---|
| `decodeString clip "{ \"length\": 90 }"` | Ok (Duration 90) | Ok (Duration 90) |
| `decodeString clip "[ 10, 20, 30 ]"` | Ok (Duration 3) | Ok (Samples [ 10, 20, 30 ]) |
| `decodeString (field "length" int) "[ 10, 20, 30 ]"` | Ok 3 | Err |
| `decodeString (field "0" string) "[ \"a\" ]"` | Ok "a" | Err |
| `decodeString (field "constructor" value) "{}" \|> map (encode 0)` | Ok undefined | Err |

The last row's `Value` holds `Object`, the constructor function, and
`Encode.encode` writes it as `undefined`, which is not JSON.

## Cause and fix

The `FIELD` case of `_Json_runHelp` in `Gren/Kernel/Json.js` checks that the
value is an object with `field in value`. An array is a JavaScript object, and
`in` also looks along the prototype chain. The check wants an own property of
something that is not an array:

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

`keyValuePairs` already uses `Object.hasOwn`, and already refuses an array.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** `gren` 0.6.6, node 22
