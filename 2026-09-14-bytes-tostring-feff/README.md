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

## Why `Bytes.toString` has to keep it

A byte-order mark belongs to the start of a text file or a text stream, and a
library reading one should remove it. `core` already has that library:
`Stream.textDecoder` is a `TextDecoderStream`, and it removes `EF BB BF` at the
start of the stream and keeps a U+FEFF anywhere after it. Fixing
`Bytes.toString` does not change that.

`Bytes.toString` sits below that layer, and it cannot tell whether its bytes
are the start of a file. Most of the time they are not:

- **A string field inside a binary message.** `Bytes.Decode.string n` reads a
  length-prefixed value out of the middle of a larger structure, such as
  protobuf, MessagePack or a format of the program's own. Its first byte starts
  a value, not a file, so U+FEFF there is the value's first character.
  Removing it returns different data than was encoded.
- **A round trip.** `Bytes.fromString` writes the characters it is given. It
  never adds a byte-order mark and never removes a U+FEFF, and `toString` is
  its inverse only if it does the same. Anything that re-encodes and compares
  sees the string change, and that includes a canonical-form check, a hash, a
  signature and a cache key.
- **Only one way can be undone.** If `toString` keeps the character, a program
  reading a file that may carry a mark can drop a leading `'\u{FEFF}'` in one
  line. If `toString` removes it, the character is gone and nothing can tell it
  was there. The loss is one character, at offset 0 only, with no error.

Other languages decode UTF-8 the same way: the character is kept, and removing
a mark is something the caller asks for.

| decoding `EF BB BF 61` | result |
|---|---|
| Python 3.12 `bytes.decode("utf-8")` | `U+FEFF U+0061` |
| Python 3.12 `bytes.decode("utf-8-sig")`, which asks for removal | `U+0061` |
| Go 1.25 `string(b)` | `U+FEFF U+0061` |
| Java 21 `new String(b, StandardCharsets.UTF_8)` | `U+FEFF U+0061` |
| Node 22 `Buffer.toString("utf8")` | `U+FEFF U+0061` |
| Node 22 `fs.readFileSync(path, "utf8")` | `U+FEFF U+0061` |
| `new TextDecoder("utf-8", { ignoreBOM: true })` | `U+FEFF U+0061` |
| `new TextDecoder("utf-8")`, what `Bytes.toString` uses | `U+0061` |

`TextDecoder`'s default comes from the WHATWG Encoding Standard, which decodes
whole web resources, where a leading mark is expected. That is the same job
`Stream.textDecoder` does, and not the job `Bytes.toString` does.

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
is what `Bytes.fromString` wrote. Text read through `Stream.textDecoder` still
has its mark removed.
