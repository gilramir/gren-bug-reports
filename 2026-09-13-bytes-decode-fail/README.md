# A decoder that uses `Bytes.Decode.fail` crashes instead of returning `Nothing`

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`src/Main.gren` is the example from `Bytes.Decode.fail`'s own documentation: a
tag byte picks a decoder, and an unknown tag is `fail`.

```gren
distance : Decode.Decoder String
distance =
    Decode.unsignedInt8
        |> Decode.andThen
            (\tag ->
                when tag is
                    0 -> Decode.map (\_ -> "yards") (Decode.float32 Bytes.BE)
                    1 -> Decode.map (\_ -> "meters") (Decode.float32 Bytes.BE)
                    _ -> Decode.fail
            )
```

`Decode.decode distance` should give `Nothing` for an unknown tag. Instead the
program crashes.

| input | `Decode.decode distance` | expected |
|---|---|---|
| tag `0`, then a float | `Just "yards"` | `Just "yards"` |
| tag `0`, then no float | `Nothing` | `Nothing` |
| tag `7`, then a float | **throws `0`** | `Nothing` |

`fail` is `_Bytes_decodeFailure`, which does `throw 0`. `_Bytes_decode` catches
only `RangeError`, the error a `DataView` read past the end raises, and rethrows
everything else:

```js
var _Bytes_decode = F2(function (decoder, bytes) {
  try {
    return __Maybe_Just(A2(decoder, bytes, 0).__$value);
  } catch (e) {
    if (e instanceof RangeError) {
      return __Maybe_Nothing;
    } else {
      throw e;
    }
  }
});
```

So running out of input is `Nothing`, and `fail` escapes as an uncaught `0`. The
narrowing is commit 397368a, "Only return Nothing from Bytes.decode on RangeError
exceptions", first released in `core` 5.0.0. It
answers core#47 (elm/bytes#9), where a stack overflow inside a decoder came back
as `Nothing`.

## Reproduction

`./run.sh` builds the program and runs it twice:

```
$ node app
known tag:        Just yards
input too short:  Nothing
exit status: 0

$ node app direct
0
exit status: 0
```

With no argument, each line is decoded inside its own task. The third line never
appears, stderr is empty and the exit status is 0. With `direct`, the same decode
runs outside any task, and node prints the thrown `0`. The exit status is still 0.
That part is compiler#385 (a crashing program exits zero) and core#142 (an
exception raised after a stream write is swallowed), not this report.

## The fix

Make the failure something `_Bytes_decode` recognizes. For example, throw a
dedicated sentinel and catch it beside `RangeError`:

```js
var _Bytes_decodeFailed = {};

var _Bytes_decodeFailure = F2(function () {
  throw _Bytes_decodeFailed;
});

// in _Bytes_decode:
if (e instanceof RangeError || e === _Bytes_decodeFailed) {
  return __Maybe_Nothing;
}
```

That keeps what 397368a wanted, which is not to turn an unrelated exception into
`Nothing`, and gives `fail` its documented meaning back.
