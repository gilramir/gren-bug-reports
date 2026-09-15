# `String.split ""` cuts a character outside the Basic Multilingual Plane in two

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22, Linux x86-64.

## Summary

Splitting on the empty string is how a string is taken apart into its
characters, and the usual next step is to do something to the pieces and join
them again, for example to reverse the text:

```gren
String.split "" s |> Array.reverse |> String.join ""
```

For any character above U+FFFF (emoji, most of the mathematical alphanumerics,
the higher CJK extensions), `split ""` does not give that character as one
piece. It gives two pieces, each holding half of the character's UTF-16
surrogate pair, so the reversed string holds the two halves in the wrong order
and is not text at all. Everything else in `String` counts that character as
one: `String.count "a😀b"` is 3, and `split ""` answers four pieces.

`./run.sh` prints this, with `s = "a😀b"` (U+1F600 is the middle character):

| call | result | expected |
|---|---|---|
| `String.count s` | 3 | 3 |
| `Array.length (String.split "" s)` | 4 | 3 |
| `String.split "" s \|> Array.map String.count` | [ 1, 1, 1, 1 ] | [ 1, 1, 1 ] |
| `code points of (String.split "" s \|> Array.reverse \|> String.join "")` | [ 0x62, 0xDE00, 0xD83D, 0x61 ] | [ 0x62, 0x1F600, 0x61 ] |

`0xD83D` and `0xDE00` are U+1F600's two surrogates, each alone.

## Cause

`_String_split` in `Gren/Kernel/String.js` is JavaScript's `split`:

```js
var _String_split = F2(function (sep, str) {
  return str.split(sep);
});
```

and `"a😀b".split("")` splits between UTF-16 code units.

## Fix

Split on characters when the separator is empty, which is what
`Array.from` does:

```js
var _String_split = F2(function (sep, str) {
  return sep === "" ? Array.from(str) : str.split(sep);
});
```

A non-empty separator is not affected: a well-formed separator can only match
whole characters of a well-formed string.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** `gren` 0.6.6, node 22
