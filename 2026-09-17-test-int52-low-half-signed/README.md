# `Fuzz.float` turns a low half of `0x80000000` or more into a negative number

**Repository:** `gren-lang/test`
**Found against:** `gren` 0.6.6, `gren-lang/test` 5.0.0, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`Fuzz.Float.wellShrinkingFloat` builds every whole number `Fuzz.float` makes
with `MicroBitwiseExtra.int52FromTuple`, and that reads a low half with its top
bit set as negative, so the result is `2^32` too small. `int52ToTuple` does not
have the problem, so the pair does not round trip. The shrinker takes a smaller
`(hi, lo)` to be a simpler float, and between two neighbouring choices the value
jumps from `2147483647` to `-2147483648`.

## Reproduction

`./run.sh` does all of this, using the `gren` and `node` that devbox pins.

Both modules are internal, so the program puts the package's `src/` on its
source path:

```sh
git clone --branch 5.0.0 --depth 1 https://github.com/gren-lang/test.git test
```

`gren.json`: a node application with `"source-directories": ["src", "test/src"]` and `"gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3"` (indirect `"gren-lang/url": "6.0.0"`).

`src/Main.gren`:

```gren
module Main exposing (main)

import Fuzz.Float
import MicroBitwiseExtra
import Node
import Stream
import Task


row : Int -> Int -> String
row hi lo =
    "| ("
        ++ String.fromInt hi
        ++ ", "
        ++ String.fromInt lo
        ++ ") | "
        ++ String.fromInt (MicroBitwiseExtra.int52FromTuple { hi = hi, lo = lo })
        ++ " | "
        ++ String.fromFloat (Fuzz.Float.wellShrinkingFloat { hi = hi, lo = lo })
        ++ " | "
        ++ String.fromInt (hi * 0x100000000 + lo)
        ++ " |"


main : Node.SimpleProgram {}
main =
    Node.defineSimpleProgram <| \env ->
        [ "| (hi, lo) | int52FromTuple | wellShrinkingFloat | expected |"
        , "|---|---|---|---|"
        , row 0 0x7FFFFFFF
        , row 0 0x80000000
        , row 0 0xFFFFFFFF
        , row 1 0x80000000
        , "int52FromTuple (int52ToTuple 2147483648) = "
            ++ String.fromInt (MicroBitwiseExtra.int52FromTuple (MicroBitwiseExtra.int52ToTuple 2147483648))
        ]
            |> String.join "\n"
            |> (\text -> Stream.writeLineAsBytes text env.stdout)
            |> Task.map (\_ -> {})
            |> Task.onError (\_ -> Task.succeed {})
            |> Node.endSimpleProgram
```

```sh
gren make Main --output=app && node app
```

Output:

```
| (hi, lo) | int52FromTuple | wellShrinkingFloat | expected |
|---|---|---|---|
| (0, 2147483647) | 2147483647 | 2147483647 | 2147483647 |
| (0, 2147483648) | -2147483648 | -2147483648 | 2147483648 |
| (0, 4294967295) | -1 | -1 | 4294967295 |
| (1, 2147483648) | 2147483648 | 2147483648 | 6442450944 |
int52FromTuple (int52ToTuple 2147483648) = -2147483648
```

## Cause

`int52FromTuple` calls `signedToUnsigned` on the low half **before**
`keepBits 32`. `keepBits` is `Bitwise.and`, which answers a signed 32-bit
number, so the `signedToUnsigned` is undone:

```gren
        (lowBits
            |> signedToUnsigned
            |> keepBits 32
        )
```

## Fix

Swap the two steps, as `int52ToTuple` has them:

```gren
        (lowBits
            |> keepBits 32
            |> signedToUnsigned
        )
```
