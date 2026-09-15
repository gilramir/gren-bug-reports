# `Json.Encode.object` drops a member named `__proto__`

## Summary

`"__proto__"` is an ordinary key in JSON, and `Json.Decode` reads it as one:
`keyValuePairs` of `{"__proto__":1,"a":2}` has both members. `Json.Encode`
cannot write it. `Encode.object` and `Encode.dict` leave the member out, so an
object decoded and encoded again loses it without an error. When the member's
value is an object, it is not only dropped but becomes the new object's
prototype, and `Decode.field` then finds its fields on an object that has none.

## Reproduction

`./run.sh` prints the table.

| call | result | expected |
|---|---|---|
| `decodeString (keyValuePairs int) "{\"__proto__\":1,\"a\":2}"` | Ok [__proto__ = 1, a = 2] | Ok [__proto__ = 1, a = 2] |
| the same object through `dict int`, then `Encode.dict` | {"a":2} | {"__proto__":1,"a":2} |
| `encode 0 (object [ { key = "__proto__", value = int 1 } ])` | {} | {"__proto__":1} |
| `encode 0 (object [ { key = "__proto__", value = object [ { key = "x", value = int 1 } ] } ])` | {} | {"__proto__":{"x":1}} |
| `decodeValue (field "x" int) (object [ { key = "__proto__", value = object [ { key = "x", value = int 1 } ] } ])` | Ok 1 | Err |

The last row also needs `field`'s use of `in`, reported separately as
"`Json.Decode.field` finds fields in arrays, and inherited properties in
objects". Fixing either one fixes that row, and only this report's fix keeps
the member.

## Cause and fix

`_Json_addField` in `Gren/Kernel/Json.js`, which `Encode.object` and
`Encode.dict` both fold with, assigns the member:

```js
object[key] = unwrapped;
```

On an object made with `{}`, assigning to `__proto__` calls the inherited
`Object.prototype.__proto__` setter. It sets the prototype when the value is an
object and does nothing otherwise, and in neither case creates an own property,
so `JSON.stringify` does not write one. `JSON.parse` defines the property
instead, which is why decoding is not affected. Defining it here does the same:

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

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2, and `main` as of 2026-09-15
- **Versions:** `gren` 0.6.6, node 22
