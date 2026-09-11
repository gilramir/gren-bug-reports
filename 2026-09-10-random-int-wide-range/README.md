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
`#`; one that never did is `.`.

```
  int 0 0xFFFFFFFF     ################################################  all of it
  int 0 0x1FFFFFFFF    ########################........................  the low half
  int 0 0x7FFFFFFF     ################################################  all of it
  int 0 0x17FFFFFFF    ################................................  the low third
  int 0 0x100000000    #...............................................  only 0
  int 0 0x100000001    #...............................................  only 0 and 1
```

Within the part it reaches the draws are flat, not merely concentrated: for
the 1.5 * 2^32 row the 16 occupied buckets took between 1190 and 1294
of the 20000 draws, and the other 32 took none.

So the draws are uniform over a *prefix* of the interval and absent from the
rest. Nothing is out of range and nothing is biased within what it reaches; the
interval is simply smaller than the one that was asked for.

Read the rows in pairs, because that is the whole of it. `int 0 0x1FFFFFFFF`
asks for 2^33 values and is served the stream of `int 0 0xFFFFFFFF`.
`int 0 0x17FFFFFFF` asks for 1.5 × 2^32 and is served the stream of
`int 0 0x7FFFFFFF` — not approximately, but the same numbers, because `m` is
2^31 and a mask of `2^31 - 1` is exactly what the narrower call applies:

```
  int 0 0xFFFFFFFF      2412620543  962486949 4105077394 2526171418 1015690994 2793901850
  int 0 0x1FFFFFFFF     2412620543  962486949 4105077394 2526171418 1015690994 2793901850
  int 0 0x7FFFFFFF       265136895  962486949 1957593746  378687770 1015690994  646418202
  int 0 0x17FFFFFFF      265136895  962486949 1957593746  378687770 1015690994  646418202
  int 0 0x100000000              0          0          0          0          0          0
  int 0 0x100000001              1          1          0          0          0          0
```

`int 0 0x100000000` is the sharp one, and it is the same arithmetic with nothing
left over: `range` is 2^32 + 1, `m` is 1, the mask is `m - 1` = 0, and every draw
is `lo`. A generator that has stopped generating, with no error and no warning.
`int 0 0x100000001` is one step along, `m` = 2, mask 1, and the whole of a
four-billion-wide interval is `{0, 1}`.

What `int` decided in each case, which is the rule above applied six times:

```
  call                 range         range mod 2^32   (range-1) & range         mask
  int 0 0xFFFFFFFF     2^32                       0                   0   4294967295
  int 0 0x1FFFFFFFF    2^33                       0                   0   4294967295
  int 0 0x7FFFFFFF     2^31              2147483648                   0   2147483647
  int 0 0x17FFFFFFF    1.5 * 2^32        2147483648                   0   2147483647
  int 0 0x100000000    2^32 + 1                   1                   0            0
  int 0 0x100000001    2^32 + 2                   2                   0            1
```

**The first row works only by coincidence**, and it is the row that matters most,
because it is the call the module itself makes — `Random.int 0 0xFFFFFFFF` in
`independentSeed`. `range - 1` truncates to `-1` and `range` truncates to `0`, so
`-1 & 0` is `0`: the test says "power of two", which for 2^32 is the right answer
reached for the wrong reason, and a mask of `-1` then leaves `peel`'s 32 bits
alone, which is also right. Two wrongs, one usable result, at exactly the one
width `core` depends on.

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
