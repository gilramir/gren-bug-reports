# `Bytes.Decode.bytes` reads past the end of the `Bytes` it is decoding

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

The usual way to read a length-prefixed message is to decode the length, take
that many bytes with `Decode.bytes`, and then decode the body with a decoder of
its own:

```gren
firstBody =
    Decode.decode (Decode.unsignedInt8 |> Decode.andThen Decode.bytes) buffer
```

`buffer` is `[3, 10, 20, 30, 2, 40, 50]`, so `firstBody` is `[10, 20, 30]` and
`Bytes.length firstBody` is `3`. A decoder run over `firstBody` should see those
three bytes and nothing else. `Decode.bytes` sees the rest of `buffer`:

```
decoding the 3-byte body [10, 20, 30]   result                        expected
bytes 3                                 Just [10, 20, 30]             Just [10, 20, 30]
bytes 4                                 Just [10, 20, 30, 2]          Nothing
bytes 5                                 Just [10, 20, 30, 2, 40]      Nothing
unsignedInt8, four times                Nothing                       Nothing
string 4                                Just [10, 20, 30, 2]          Nothing
```

Asking for four bytes of a three-byte body returns the next message's length
byte as a fourth byte. `unsignedInt8` gets this right, and `string`, which is
built on `bytes`, gets it wrong.

A `Bytes` is a `DataView` onto a larger `ArrayBuffer`, and `Decode.bytes` returns
a view onto the same buffer rather than a copy. `_Bytes_read_bytes` makes that
view without checking it against the view it is reading:

```js
var _Bytes_read_bytes = F3(function (len, bytes, offset) {
  return {
    __$offset: offset + len,
    __$value: new DataView(bytes.buffer, bytes.byteOffset + offset, len),
  };
});
```

The `DataView` constructor throws only when the new view would run past the end
of the whole `ArrayBuffer`. `getUint8` and the other readers check against the
view's own `byteLength`, which is why `unsignedInt8` stops where it should.

## Why it matters

Whether a decoder succeeds on a slice depends on bytes outside the slice. A
malformed length inside a message does not fail; it reads into whatever follows.
And a decoder that tries a payload one way and falls back to another, as a
protobuf decoder does with a length-delimited field, keeps succeeding on bytes
it should have rejected. The work that follows can be very large. A schema-free
walker over a 23,527-byte protobuf file, with `Bytes.Decode.fail` patched so that it
could run at all, made 10,269,672 nested `decode` calls and
took 10.6 s. With the fix below, the same program made 3,841 calls and took
14 ms.

## Reproduction

`./run.sh` builds `src/Main.gren` and prints the table above.

## The fix

Check the request against the view being read before making the new view:

```js
var _Bytes_read_bytes = F3(function (len, bytes, offset) {
  if (len < 0 || offset + len > bytes.byteLength) {
    throw new RangeError("Bytes.Decode.bytes: past the end");
  }
  return {
    __$offset: offset + len,
    __$value: new DataView(bytes.buffer, bytes.byteOffset + offset, len),
  };
});
```

A `RangeError` is what `_Bytes_decode` already turns into `Nothing`.
