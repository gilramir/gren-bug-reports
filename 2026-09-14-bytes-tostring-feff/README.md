# `Bytes.toString` drops a leading U+FEFF, so a string does not survive `fromString` and back

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

U+FEFF is a character, and `Bytes.fromString` writes it as the three bytes
`EF BB BF`. Reading those bytes back loses it when it is the first character:

| call | result | expected |
|---|---|---|
| `Bytes.length (Bytes.fromString "\u{FEFF}a")` | `4` | `4` |
| `Bytes.toString (Bytes.fromString "\u{FEFF}a") == Just "\u{FEFF}a"` | **`False`** | `True` |
| `Bytes.toString` of `EF BB BF 61` | **`Just "a"`** | `Just "\u{FEFF}a"` |
| `Bytes.toString` of `EF BB BF` | **`Just ""`** | `Just "\u{FEFF}"` |
| `Bytes.toString` of `EF BB BF EF BB BF` | **`Just "\u{FEFF}"`** | `Just "\u{FEFF}\u{FEFF}"` |
| `Bytes.toString` of `61 EF BB BF` | `Just "a\u{FEFF}"` | `Just "a\u{FEFF}"` |
| `Bytes.Decode.string 4` of `EF BB BF 61` | **`Just "a"`** | `Just "\u{FEFF}a"` |

`Bytes.Decode.string` calls `Bytes.toString` on the bytes it read, so any
length-prefixed string field whose value starts with U+FEFF comes back one
character short, and a decoder that checks a re-encoding against its input
refuses it.

The cause is the decoder's options:

```js
function _Bytes_toString(bytes) {
  var decoder = new TextDecoder("utf-8", { fatal: true });
```

The WHATWG `TextDecoder` has an `ignoreBOM` option, default `false`, and with
it `false` the decoder treats `EF BB BF` at the start of its input as a
byte-order mark and removes it. Only the first one is removed, which is why a
second U+FEFF, or one after another character, survives.

## Reproduction

`./run.sh` builds the program and runs it:

```
$ node app
Bytes.fromString "\u{FEFF}a" has length 4
Bytes.toString (Bytes.fromString "\u{FEFF}a") == Just "\u{FEFF}a": False
toString [EF BB BF 61]:          Just [97]
toString [EF BB BF]:             Just []
toString [EF BB BF EF BB BF]:    Just [65279]
toString [61 EF BB BF]:          Just [97, 65279]
Decode.string 4 [EF BB BF 61]:   Just [97]
```

The lists are the decoded strings' code points.

## The fix

```js
var decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
```

`Bytes.toString` then gives back exactly the characters the bytes encode, which
is what `Bytes.fromString` wrote. A program that wants a byte-order mark
stripped from a file can still drop a leading `'\u{FEFF}'` itself; a program
that needs the character has no way to get it back once it is gone.
