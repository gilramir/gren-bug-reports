# `Random.int` uses its range modulo 2^32: wide ranges silently narrow, and 2^32 + 1 returns `lo` forever

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22, Linux x86-64.

`./run.sh` prints every figure below.

## Summary

`Random.int` chooses between two algorithms with a power-of-two test, and masks
with `range - 1` when it takes the fast path:

```gren
                range =
                    hi - lo + 1
            in
                -- fast path for power of 2
                if (Bitwise.and (range - 1) range) == 0 then
                    { value = (Bitwise.shiftRightZfBy 0 (Bitwise.and (range - 1) (peel seed0))) + lo, seed = next seed0 }
```

`Bitwise.and` is JavaScript `&`, which coerces **each** operand to a signed
32-bit integer on its own. An `Int` is a float64 and holds far more than that, so
for a range of 2^32 or wider neither the test nor the mask is about `range` at
all. Both are about `range` modulo 2^32.

Write `m` for `range mod 2^32`. When `range` is at least 2^32 and `m` is not
zero, `(range - 1) mod 2^32` is `m - 1`, so the test computes `(m - 1) & m == 0`
— **it asks whether `m` is a power of two, not whether `range` is** — and the
mask that follows is `m - 1`. One rule covers every case:

> The fast path is taken whenever `range mod 2^32` is zero or a power of two, and
> the mask applied is `(range - 1) mod 2^32`. Everything above bit 31 of `range`
> is discarded.

So a caller who asks for a range wider than 2^32 does not get an error, a clamp,
or a biased answer. They get a **different, narrower question answered exactly**,
with no way to tell from the result that it happened.

## What that produces

Each row below is one call's own requested interval, from 0 on the left to `hi`
on the right, cut into 48 equal buckets — 48 because it divides by both 2 and 3,
so every boundary here lands on a bucket edge. 20000 draws from
`Random.initialSeed 7` are dropped in. A bucket that ever received a draw is
`#`; one that never did is `.`. **`ok` marks a call that reaches its whole
requested interval and `BAD` one that does not.**

```
  ok  int 0 0xFFFFFFFF   ################################################  all of it
  BAD int 0 0x1FFFFFFFF  ########################........................  the low half
  ok  int 0 0x7FFFFFFF   ################################################  all of it
  BAD int 0 0x17FFFFFFF  ################................................  the low third
  BAD int 0 0x100000000  #...............................................  only 0
  BAD int 0 0x100000001  #...............................................  only 0 and 1
```

Within the part it reaches the draws are flat, not merely concentrated: for
the 1.5 * 2^32 row the 16 occupied buckets took between 1190 and 1294
of the 20000 draws, and the other 32 took none.

So the draws are uniform over a *prefix* of the interval and absent from the
rest. Nothing is out of range and nothing is biased within what it reaches; the
interval is simply smaller than the one that was asked for.

Two of the six are correct, and they are the two whose range is a genuine power
of two no wider than 2^32: `0xFFFFFFFF` is 2^32 exactly, `0x7FFFFFFF` is 2^31.
The other four are wrong, and all four are wrong in the same way — **each is
some narrower call, answered exactly.** For two of them that narrower call is
sitting in the table beside it. Five draws from the same seed, the pairs
adjacent:

```
  ok  int 0 0xFFFFFFFF    2412620543  962486949 4105077394 2526171418 1015690994
  BAD int 0 0x1FFFFFFFF   2412620543  962486949 4105077394 2526171418 1015690994
  ok  int 0 0x7FFFFFFF     265136895  962486949 1957593746  378687770 1015690994
  BAD int 0 0x17FFFFFFF    265136895  962486949 1957593746  378687770 1015690994
  BAD int 0 0x100000000            0          0          0          0          0
  BAD int 0 0x100000001            1          1          0          0          0
```

`int 0 0x1FFFFFFFF` asks for 2^33 values and is handed the stream of
`int 0 0xFFFFFFFF`. `int 0 0x17FFFFFFF` asks for 1.5 × 2^32 and is handed the
stream of `int 0 0x7FFFFFFF` — not approximately, but the same numbers, because
`m` is 2^31 and a mask of `2^31 - 1` is exactly what the narrower call applies.
There is nothing in either output to say which question it answered.

`int 0 0x100000000` is the sharp one, and it is the same arithmetic with nothing
left over: `range` is 2^32 + 1, `m` is 1, the mask is `m - 1` = 0, and every draw
is `lo`. A generator that has stopped generating, with no error and no warning.
`int 0 0x100000001` is one step along, `m` = 2, mask 1, and the whole of a
four-billion-wide interval is `{0, 1}`. Those two are narrower calls as much as
the other pair is: `int 0 0x100000000` is `Random.int 0 0` and
`int 0 0x100000001` is `Random.int 0 1`, exactly.

"Correct" here means the interval is the one asked for. The values filling it
still carry the separate defect in `peel` noted at the end, which is why the
`ok` rows are `ok` about range handling and not about `Random` as a whole.

What `int` decided in each case, which is the rule above applied six times:

```
      call                 range         range mod 2^32   (range-1) & range         mask
  ok  int 0 0xFFFFFFFF     2^32                       0                   0   4294967295
  BAD int 0 0x1FFFFFFFF    2^33                       0                   0   4294967295
  ok  int 0 0x7FFFFFFF     2^31              2147483648                   0   2147483647
  BAD int 0 0x17FFFFFFF    1.5 * 2^32        2147483648                   0   2147483647
  BAD int 0 0x100000000    2^32 + 1                   1                   0            0
  BAD int 0 0x100000001    2^32 + 2                   2                   0            1
```

## The one row that works, and why it has to keep working

`int 0 0xFFFFFFFF` is not a hypothetical caller. It is the only `Random.int`
call in the whole of `core`, and `independentSeed` makes it three times for
every seed it hands out:

```gren
independentSeed : Generator Seed
independentSeed =
    Generator <|
        \seed0 ->
            let
                gen =
                    int 0 0xFFFFFFFF

                makeIndependentSeed state b c =
                    next <| Seed { state = state, increment = Bitwise.shiftRightZfBy 0 (Bitwise.or 1 (Bitwise.xor b c)) }
            in
            step (map3 makeIndependentSeed gen gen gen) seed0
```

That is the `m = 0` case of the rule, and it is worth following both truncations
through, because neither one is an answer about `range`:

```
range      = 0xFFFFFFFF - 0 + 1 = 4294967296     -- 2^32, exact in a float64
range - 1                       = 4294967295

the test   Bitwise.and (range - 1) range
  range - 1 as int32            = -1             -- all 32 bits set
  range     as int32            =  0             -- its one set bit is bit 32, out of range
  -1 & 0                        =  0             -- reads as "power of two": fast path

the mask   Bitwise.and (range - 1) (peel seed0)
  range - 1 as int32            = -1
  -1 & x                        =  x             -- the identity; the enclosing
                                                 -- shiftRightZfBy 0 puts the sign back
```

Three coercions happen across those two lines, and only one of them loses
anything.

`range - 1` is 4294967295, which already fits in 32 bits — it *is* all ones — so
reading it as `-1` changes how the bits are interpreted, not what they are. That
happens twice, once in the test and once in the mask, and both times it is
harmless: all ones is exactly the mask a 32-bit range calls for.

`range` is the one that loses. Its only set bit is bit 32, the coercion discards
it, and what the test actually sees is `0`.

That loss is harmless here and nowhere else above 2^32. The test asks whether
`(range - 1) & range` is zero, and in exact arithmetic it is, because 4294967295
and 4294967296 share no bits — so the branch taken is the right branch. It is
reached by a different question, though. The test that was meant to run passes
because 2^32 is a power of two; the test that did run passes because `0` has no
bits at all.

So this is not two errors cancelling. It is one coercion that happens to be
lossless, and one that throws away the only bit that mattered and still lands on
the correct branch. The defect is fully present in this row — at this one width
it has nothing left to damage.

That is what makes the repair delicate rather than obvious, and it is why
"Suggested fix" below opens with a guard that does not work. Whatever replaces
the test has to keep 2^32 on the fast path, because 2^32 is where `core` itself
lives.

## Cause

`Bitwise.and`, `.or`, `.xor`, `.complement` and the shifts are the JavaScript
operators, which are defined on int32. `Random.int` is the only place in `core`
that hands one a value derived from user-supplied bounds rather than from a
32-bit quantity it produced itself, so it is the only place where the coercion is
reachable from the outside.

Underneath that is a missing contract. `peel` yields 32 bits, so at most 2^32
distinct values are reachable however they are post-processed, and no range wider
than that is satisfiable by this generator at all. `int` never checks; the
coercion then reinterprets the excess instead of refusing it.

## Suggested fix — and one that looks right and is worse

The obvious guard is a trap, so it is worth writing down before anyone tries it:

```gren
-- do NOT do this
if range <= 4294967296 && Bitwise.and (range - 1) range == 0 then
```

It keeps 2^32 on the fast path, where it works, and sends everything wider to the
rejection-sampling branch — which is **worse than the bug**. That branch's
threshhold is `2^32 % range`, computed as
`remainderBy range (Bitwise.shiftRightZfBy 0 -range)`, and `peel` only ever
produces values in `[0, 2^32)`:

| range | threshhold | `peel` values accepted | acceptance rate |
|---|---|---|---|
| 2^32+1 | 4294967295 | 1 | 2.3 × 10⁻¹⁰ |
| 1.5 × 2^32 | 2147483648 | 2147483648 | 0.5 |

`accountForBias` recurses, so the first row is a hang or a blown stack rather
than a wrong number.

The 1.5 × 2^32 range is uniform under neither branch — the fast path reaches the
low third of the interval, the rejection branch would reach the low two thirds.
There are not enough bits, and no arrangement of masks and remainders makes more.

So the fix is to make that limit real rather than to reroute around it:

- reject, or saturate, when `hi - lo + 1 > 2^32`, and say which; and
- document the limit on `int` itself. `maxInt`'s "the `maxInt` that works well is
  `2147483647`" is the only warning in the module, and it is attached to a
  constant nobody reads on the way to calling `int`.

Returning `lo` forever is the one outcome that should not survive either way: it
is the failure that gets diagnosed three modules away from its cause.

## Running it

This directory is a stock Gren application; `devbox` pins `gren` 0.6.6 and node
22. `./run.sh` prints every block above, and `src/Main.gren` is the whole of it.

## A second, independent defect in the same module

`2026-09-10-random-pcg-multiply` beside this directory, filed as
[core#146](https://github.com/gren-lang/core/issues/146) — `peel`'s multiply by
`277803737` is a float64 multiply on a 32-bit word, so it loses the low bits
PCG's RXS-M-XS specifies and `Random`'s stream is not the algorithm its comment
cites. This report was found while reading `Random` for that one. They share
nothing mechanically: fixing either leaves the other standing.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Node.js v22, Linux x86-64
