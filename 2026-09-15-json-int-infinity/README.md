# `Json.Decode.int` accepts `1e400` and answers an `Int` that is `Infinity`

## Summary

JSON has no infinity, but a number too large for a double, such as `1e400`, is
valid JSON and `JSON.parse` reads it as `Infinity`. `Json.Decode.int` then
accepts it, so a program gets an `Int` that is not an integer. Nothing
downstream can tell: `String.fromInt` writes `"Infinity"`, which `String.toInt`
does not read back, and arithmetic on it answers `NaN`.

## Reproduction

| call | result | expected |
|---|---|---|
| `decodeString int "12"` | Ok 12 | Ok 12 |
| `decodeString int "1e400"` | Ok Infinity | Err |
| `decodeString int "-1e400"` | Ok -Infinity | Err |
| `decodeString int "1e400" \|> map (String.fromInt >> String.toInt)` | Ok Nothing | Err |
| `decodeString int "1e400" \|> map (\n -> n - n)` | Ok NaN | Err |

`Json.Decode.float` answering `Infinity` for `1e400` is not this bug: that is
the double the text rounds to.

## Cause and fix

`_Json_decodeInt` in `Gren/Kernel/Json.js` accepts a number when
`Math.trunc(value) === value`, and `Math.trunc(Infinity)` is `Infinity`. Its
second test, `isFinite(value) && !(value % 1)`, is the right one, and is never
reached for an infinity because the first test has already said yes. Either
test alone, with `isFinite`, is the fix:

```js
var _Json_decodeInt = _Json_decodePrim(function (value) {
  return typeof value === "number" && Number.isInteger(value)
    ? __Result_Ok(value)
    : _Json_expecting("an INT", value);
});
```

`Number.isInteger` is false for both infinities and for `NaN`.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** `gren` 0.6.6, node 22
