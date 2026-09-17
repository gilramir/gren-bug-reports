# Fuzz.float reads a low half with its top bit set as negative

`MicroBitwiseExtra.int52FromTuple` builds a 52-bit number from a `hi` and a `lo`
half, and it applies `keepBits 32` to `lo` **after** `signedToUnsigned`.
`keepBits` is `Bitwise.and`, whose result is a signed 32-bit number, so a `lo`
of `0x80000000` or above comes out negative and the answer is `2^32` too small.
`int52ToTuple` does the two steps in the other order, so the pair does not round
trip.

`Fuzz.Float.wellShrinkingFloat` uses it for every float whose fractional flag is
clear, so `Fuzz.float` turns those choices into the wrong whole numbers:

```
$ ./run.sh
$ gren make Main && node app
{ hi = 0, lo = 2147483646 }  int52FromTuple = 2147483646  wellShrinkingFloat = 2147483646
{ hi = 0, lo = 2147483647 }  int52FromTuple = 2147483647  wellShrinkingFloat = 2147483647
{ hi = 0, lo = 2147483648 }  int52FromTuple = -2147483648  wellShrinkingFloat = -2147483648
{ hi = 0, lo = 4294967295 }  int52FromTuple = -1  wellShrinkingFloat = -1
{ hi = 1, lo = 0 }  int52FromTuple = 4294967296  wellShrinkingFloat = 4294967296
{ hi = 1, lo = 2147483648 }  int52FromTuple = 2147483648  wellShrinkingFloat = 2147483648
int52FromTuple (int52ToTuple 2147483648) = -2147483648
```

| `(hi, lo)` | result | expected |
|---|---|---|
| `(0, 0x80000000)` | `-2147483648` | `2147483648` |
| `(0, 0xFFFFFFFF)` | `-1` | `4294967295` |
| `(1, 0x80000000)` | `2147483648` | `6442450944` |

The shrinker relies on a smaller `(hi, lo)` giving a simpler float, and here
the value jumps from `2147483647` to `-2147483648` between two neighbouring
choices.

## The fix

Swap the two steps for `lo`, as `int52ToTuple` already has them:

```gren
        (lowBits
            |> keepBits 32
            |> signedToUnsigned
        )
```

- **Filed as:** not yet filed
- **Package:** `gren-lang/test` 5.0.0
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
