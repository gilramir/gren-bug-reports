# `Random` is not the PCG it documents: `peel`'s multiply overflows float64

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22, Linux x86-64.

**`./check.sh` is the test to run before the fix and after it.** It exits 0 only
when all eight of its checks pass, and against core as it stands it fails all
eight; "Checking the fix" below says what it asserts and shows both outputs.

`./run.sh` shows the defect in one multiply and in eight dice rolls, and
`./bits.sh` counts it bit by bit over 100000 draws made through the published
API. Every figure below names the command that prints it.

## Summary

`Random.peel` is the heart of the module — the function that turns a seed into a
random 32-bit number. It implements PCG's RXS-M-XS, and its own comment cites the
reference:

```gren
-- This is the RXS-M-SH version of PCG, see section 6.3.4 of the paper
-- and line 184 of pcg_variants.h in the 0.94 (non-minimal) C implementation,
-- the latter of which is the source of the magic constant.
word =
    (Bitwise.xor state (Bitwise.shiftRightZfBy ((Bitwise.shiftRightZfBy 28 state) + 4) state)) * 277803737
```

That `*` does not do what the algorithm needs. Rounding destroys up to seven
bits at the bottom of the value, and it destroys them before the step that was
meant to read them, so the low bits of the numbers `Random` hands out are not
the ones RXS-M-XS specifies. The measurement below says how thoroughly. Bit 0 of
the multiply's result should be set in half of all draws; it is set in 0.74
percent of them, because in the other 99 percent the product was too large for a
float64 to hold and the bit was rounded to zero.

The numbers are still well spread out — this is **not** a "random numbers come
out in a pattern" report. What is broken is that `Random` is not the generator
its documentation names, so the cited reference cannot be used to predict, test
or reproduce the stream.

## What `peel` is supposed to do

PCG stands for Permuted Congruential Generator, and the two words are its two
halves.

The *congruential* half is `next`: an ordinary linear congruential generator,
`state * 1664525 + increment`, kept to 32 bits. An LCG is fast and its period is
guaranteed, but on its own it is a poor source of random numbers, and its low
bits are the worst part of it — taken modulo a power of two, bit 0 of an LCG
merely alternates, bit 1 repeats every four steps, and only the top bits look
random at all.

The *permuted* half is `peel`, and it is the idea the generator is named for.
Rather than replace the LCG, take its state and run it through a cheap, fixed
scrambling function chosen so that the quality concentrated in the top bits is
spread over the whole word. So the shifting in `peel` is not a flourish added to
make the numbers look more random. It is the algorithm — the P in PCG — and each
step in it has a job. The variant here is `pcg_output_rxs_m_xs_32_32`, which in
`imneme/pcg-c`'s `pcg_variants.h` reads:

```c
inline uint32_t pcg_output_rxs_m_xs_32_32(uint32_t state)
{
    uint32_t word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
```

`Random.gren`'s two lines are that function transliterated, and its name is the
initials of its three steps.

**RXS, a random xorshift.** `state ^ (state >> ((state >> 28) + 4))`. Xoring a
number with a shifted copy of itself drags high bits down into low positions,
which is exactly what an LCG's state needs. What makes it *random* is that the
distance is not fixed: it is read off the top four bits of the state itself, so
it varies between 4 and 19 according to the data. That is deliberate. A shift by
a constant is a linear operation, and a well-known family of statistical tests
exists to detect precisely that kind of linearity; letting the data choose the
distance breaks it.

**M, a multiply.** `* 277803737`, modulo 2^32. The constant is odd, which makes
multiplying by it reversible, so no information is lost and the generator's
period is untouched. Where the xorshift carried information downwards, a
multiply carries it upwards, so between them every bit of the input can reach
every bit of the output.

**XS, a second xorshift, this time by a fixed 22.** `word ^ (word >> 22)`. This
one is a repair, and "Undoing `peel`'s last step" below says what it repairs and
why 22.

A note on the name while we are here. The comment calls the variant RXS-M-SH,
and there is no such output function: the suffixes used in `pcg_variants.h` are
`_m`, `_xs`, `_rr`, `_rs` and `_xsl_rr`, with no `_sh` among them, and the body
quoted above is the `_xs` one. The last step is a xorshift, so RXS-M-XS is the
name. Worth correcting in passing, though it is cosmetic beside the arithmetic.

## What the algorithm asks for, and what Gren does

RXS-M-XS says: multiply the working value by `277803737`, and **keep only the
bottom 32 bits of the answer**. Throwing the top away is the point — that is what
"modulo 2^32" means, and it is free in C, where a `uint32_t` multiply wraps round
on its own.

Both of the references cited in `Random.gren`'s own comment say so. In the
paper, §6.3.4's permutation takes a w-bit word and returns one, so every step
inside it, the multiply included, is mod 2^w. In `pcg_variants.h` the types
carry it: the state, the product and the return are all `uint32_t`, and C
defines unsigned arithmetic as wrapping modulo 2^32 rather than widening
(C11 §6.2.5p9).

Gren's `Int` is a JavaScript number, which is a float64. A float64 holds about 15
to 16 decimal digits — 53 binary digits — and this product needs up to 60. So the
answer comes back rounded, and rounding keeps the digits at the *top* and drops
the ones at the *bottom*: exactly the ones the algorithm wanted.

It is the pocket-calculator problem. Ask a ten-digit calculator for
`123456789 × 987654321` and it answers `1.219326311e17`. The true product is
`121932631112635269`, and if you now ask it for the last four digits, it cannot
tell you — it never kept them. RXS-M-XS's next step asks precisely that.

One value, both ways:

```
2000000001 * 277803737, low 32 bits
  exact                     3672205017
  Gren / JavaScript float   3672204992
```

The full product is 555607474277803737, a little under 2^59, and float64 returns
555607474277803712 — a multiple of 64, its last six bits zeroed, off by the 25
that rounding to the nearest multiple of 64 discarded. Those six bits are inside
the low 32 the algorithm keeps. `Math.imul(2000000001, 277803737)` in the same
node process returns
`-622762279`, which is `3672205017` read as a signed 32-bit integer — the
wrapping multiply keeps exactly the bits the float64 one loses.

`./run.sh` prints both numbers. The defect needs no seeds and no `Random` at all;
`src/Main.gren` reduces it to two declarations:

```gren
state : Int
state =
    -- computed rather than literal, so this is not constant folding, and below
    -- 2^31 so that `Bitwise.xor`'s signed result is the number it reads as
    Bitwise.xor 2000000000 1


-- RXS-M-XS's middle step: multiply by the magic constant, keep 32 bits
lowBits : Int -> Int
lowBits n =
    Bitwise.shiftRightZfBy 0 (n * 277803737)
```

`lowBits state` is `3672204992` where it should be `3672205017`.

## What it does to the stream

Eight `Random.int 1 6` draws from `Random.initialSeed 7`:

| | stream |
|---|---|
| `gren-lang/core` 7.4.2 | `6 4 5 5 3 3 6 4` |
| RXS-M-XS, exact arithmetic | `4 3 5 1 5 5 6 3` |

Both rows come from `./run.sh`. The second is `reference.js`, an independent
implementation of the same generator in JavaScript `BigInt` — `next`, `peel`, the
`2^32 % range` rejection threshold and `initialSeed` transcribed from
`Random.gren` with every step taken mod 2^32 and nothing else changed.

## Which bits are missing

The rest of this section is one measurement, printed by `./bits.sh`. It takes a
little setting up, because the interesting value is one the module keeps to
itself; the payoff is that the evidence is then made entirely of numbers stock
`gren-lang/core` hands out, with nothing to take on trust.

### Reaching `peel`'s output from outside the module

`peel` is not exported. `Random`'s exposing list is `int`, `float`, `uniform`,
`weighted`, `step`, `initialSeed` and so on — no `peel`, no `next`. Everything
the public API returns is `peel`'s output already chewed up: `Random.int 1 6`
hands back a number from one to six, which is 32 bits of work reduced to three.

But one public call returns it whole. This is `int`'s fast path:

```gren
range = hi - lo + 1

if (Bitwise.and (range - 1) range) == 0 then
    { value = (Bitwise.shiftRightZfBy 0 (Bitwise.and (range - 1) (peel seed0))) + lo, ... }
```

Call it as `Random.int 0 4294967295`, so `range` is 2^32:

- **The test.** `Bitwise.and` compiles to JavaScript `&`, which converts both
  sides to a signed 32-bit integer first. `range - 1` is 4294967295, which
  converts to `-1` — all 32 bits set. `range` is 4294967296, whose only set bit
  sits just outside the 32-bit window, so it converts to `0`. `-1 & 0` is `0`, so
  the power-of-two branch is taken.
- **The mask.** It masks with `range - 1`, which is that same `-1`, all ones.
  Anding with all ones changes nothing.
- **The rest.** `shiftRightZfBy 0` is the `>>> 0` that reads the result back as
  unsigned, and `+ lo` adds zero.

So `Random.int 0 4294967295` returns `peel seed0` itself, untouched, through a
documented function called with ordinary arguments.

This is *not* the sibling defect noted at the end, which concerns ranges above
2^32. At exactly 2^32 the truncation happens and the answer is still right: 2^32
really is a power of two and the mask really is all ones, so the draw is a
correct uniform value over 0 to 2^32-1.

### Undoing `peel`'s last step

`peel` finishes by xoring `word` with a copy of itself shifted right 22 places:

```gren
Bitwise.shiftRightZfBy 0 (Bitwise.xor (Bitwise.shiftRightZfBy 22 word) word)
```

It does that because a multiply only stirs upwards. Change one bit of what goes
in, and the product can change at that place and at every place above it, never
below — the same way that in long multiplication a digit affects its own column
and the carries going left. So when the multiply is done the top of `word` is
well mixed and the bottom barely is. Shifting right by 22 lays the top ten bits
over the bottom ten, and the xor mixes them in, which spreads the good stirring
across all 32. The distance, 22, is the one PCG picks for a 32-bit word.

Shifting a 32-bit value right by 22 twice pushes everything off the end, so this
step is its own inverse: doing it a second time gives `word` back. The number
`Random` hands out still contains the damaged word, reversibly scrambled, and
`word = p ^ (p >>> 22)` recovers it.

Worked through on the first draw from `Random.initialSeed 7`. Forwards first,
the way `peel` builds the number it returns:

```
  word                    1000 1111 1100 1101 1010 1000 1100 0000   2412619968
  word >>> 22             0000 0000 0000 0000 0000 0010 0011 1111          575
  p = word ^ (word>>>22)  1000 1111 1100 1101 1010 1010 1111 1111   2412620543
```

The xor can only alter the bottom ten bits, because `word >>> 22` is ten bits
long and the twenty-two above it are zero. So everything in `p` from bit 22 up
is `word`'s, carried through untouched — and shifting `p` right by 22 therefore
lands on the same ten bits the first shift did, `575` both times. Xoring by the
same value twice cancels:

```
  p                       1000 1111 1100 1101 1010 1010 1111 1111   2412620543
  p >>> 22                0000 0000 0000 0000 0000 0010 0011 1111          575
  p ^ (p >>> 22)          1000 1111 1100 1101 1010 1000 1100 0000   2412619968
```

and `word` is back. `2412620543` is the number `Random.int 0 4294967295` really
does return for that seed today, and `2412619968` is the damaged word behind it.
Count its trailing zeros: six. The product was 336921971827517646, just over
2^58, so float64 held 53 of its bits and rounded the last six away — and they
were six of the bits the final xorshift was there to fold good ones onto.

The same state with a wrapping multiply, for comparison — the two outputs are
the pair that shows up as draw 1 of the known-answer check further down:

```
  word, as written        1000 1111 1100 1101 1010 1000 1100 0000   2412619968
  word, with imul         1000 1111 1100 1101 1010 1000 1100 1110   2412619982
  output, as written      1000 1111 1100 1101 1010 1010 1111 1111   2412620543
  output, with imul       1000 1111 1100 1101 1010 1010 1111 0001   2412620529
```

In the broken output, bits 0 to 5 read `111111` and so do bits 22 to 27: the
repair copied rather than mixed. In the fixed one the low bits are `110001`
against the same `111111` above them, which is what two independent sources
look like.

This is also the step the defect lands on, which is what makes it worse than a
handful of wrong bits. Xoring with a zero does nothing, so where rounding has
flattened the bottom of `word`, the repair has nothing to mix in and simply
copies the top bits down unchanged:

    output bit k  =  word bit k xor word bit k+22  =  0 xor word bit k+22

and output bit k+22 is that same bit again, the shift never reaching further
down than bit 9. The step whose whole purpose is to protect the low bits is
turned into a bit-duplicator: **the low bits of a number `Random` returns are
copies of bits 22 and up of that same number.** How often depends on how many
bits rounding took, which depends on the size of the product — bit 0 is a copy
of bit 22 in 99.26 percent of draws, thinning to bit 6, a copy of bit 28 in
52.19 percent. Everything measured below is that paragraph counted.

### The count

100000 draws of `Random.int 0 4294967295` from `Random.initialSeed 7`, counting
how often each bit is 1. Bit 0 is the ones place; bit 31 is the top. A healthy
bit is set in about half of the draws.

```
           Random's  recovered `word`
           output    as written                       with imul
  bit  0    50.05%     0.74% |                    |    50.07% |##########          |
  bit  1    50.14%     1.11% |                    |    49.81% |##########          |
  bit  2    50.06%     2.57% |#                   |    50.09% |##########          |
  bit  3    49.94%     5.71% |#                   |    50.05% |##########          |
  bit  4    50.05%    11.44% |##                  |    49.73% |##########          |
  bit  5    50.00%    23.67% |#####               |    50.14% |##########          |
  bit  6    50.02%    47.81% |##########          |    49.75% |##########          |
  bit  7    49.98%    50.13% |##########          |    49.95% |##########          |
  bit  8    50.15%    49.92% |##########          |    49.87% |##########          |
  bit  9    50.06%    50.01% |##########          |    50.04% |##########          |
  ...       bits 10 through 31 stay within 0.29 points of 50% in all three columns
```

The middle column is the recovered word as `Random` computes it today, the right
column the same generator with a wrapping multiply and nothing else changed.

`Random`'s own output, on the left, is 32 fair coins. That is why this went
unnoticed, and why no distribution test would have caught it. The word it was
made from is not: bit 0 is set in 0.74 percent of draws rather than 50, bit 1 in
1.11, and so on up to bit 6. Those are the digits the rounding replaced with
zeros. The effect thins out going up because how many bits are lost depends on
how big the product is: almost every product clears 2^53 and loses at least one
bit, but only the largest reach 2^59 and lose seven.

### The same thing as a picture

The same recovered word, one draw per row, written out in binary with `#` for a
set bit and `.` for a clear one, bit 31 on the left:

```
  as written                           with imul
  #...######..##.##.#.#...##......     #...######..##.##.#.#...##..###.
  ..###..#.#.####..##...#..#......     ..###..#.#.####..##...#..#..####
  ####.#..#.#.###.#......#.#......     ####.#..#.#.###.#......#..##.#..
  #..#.##.#..#..#..#.#..##.#......     #..#.##.#..#..#..#.#..##.#..#.#.
  ..####..#...#.#...##.##.........     ..####..#...#.#...##.##....#....
  #.#..##.#....####...##.##.......     #.#..##.#....####...##.#.##.###.
  .#.#.....#.###..##.#..###.......     .#.#.....#.###..##.#..##.##.#.#.
  ####....####.#......#.##........     ####....####.#......#.#.#####..#
  .#...##...##...######.#.###.....     .#...##...##...######.#.##.#.##.
  ......#.###......###..##........     ......#.###......###..##...#....
  .#.##...#.###..#.##.##.#.#......     .#.##...#.###..#.##.##.#.#...##.
  ##..##.#.###.#..#..##.##.#......     ##..##.#.###.#..#..##.##..##.#..
  #...###.#.#..###...#..####......     #...###.#.#..###...#..###.##...#
  ####.#...####..#.###....##......     ####.#...####..#.###....#.#####.
  #....#...#.##..#.#..##...#......     #....#...#.##..#.#..##...#......
  ##.#.##...#.####....###......#..     ##.#.##...#.####....###.......##
  .#.##...#...##.###.#.#..##......     .#.##...#...##.###.#.#..#.#...#.
  ......####..........#####.......     ......####..........#####.#.###.
  #.##.##.####.#.##...#.####......     #.##.##.####.#.##...#.####...#..
  ####.#....####.#####...##.......     ####.#....####.#####...#.####...
  ..#.###.#..####.....#.#.##......     ..#.###.#..####.....#.#.##.####.
  ###.##..##.#..##..###...##......     ###.##..##.#..##..###...#.#.#..#
                           ^^^^^^^
                           bits 0-6, the room float64 ran out of. The
                           lower the bit, the more completely it is gone.
```

Left is `Random` today; right is the same seed with the multiply fixed. Every row
on the left ends in blanks, bar the one that keeps a `#` at bit 2 — a draw whose
product was small enough to lose fewer bits, the 2.57 percent in the count above.

### Stated without undoing anything

The recovered word's bit k is just output bit k xor output bit k+22, so a zero
there means two bits of `Random`'s own published output that are equal. Reading
the same measurement that way: **bit 0 of `Random.int 0 4294967295` equals bit 22
in 99.26 percent of draws**, against 49.93 for RXS-M-XS, in which they are
independent. No recovery step, no reference implementation, just two bits of the
output.

### Why the right-hand column can be trusted

`src/Bits.gren` draws through the published API and walks its own transcription
of `peel` alongside. The transcription **with `*` reproduces all 100000 draws
exactly**, which is printed as a self-check at the top of `./bits.sh`. That is
what licenses reading the `imul` column beside it as the same generator with one
operator changed rather than as a second opinion about what PCG is.

## Cause

`*` on `Int` compiles to JavaScript `*`, which is the float64 operation. The
other multiply in the module is safe by luck rather than by design:
`state0 * 1664525` in `next` reaches only 2^52.6, just under the exact range.

## Suggested fix

`Math.imul` is the 32-bit wrapping multiply, which is the multiply RXS-M-XS is
specified with — §6.3.4's w-bit permutation and `pcg_variants.h`'s `uint32_t`
product, both cited above. A one-line change to `peel`'s kernel path, or to
whatever helper the module is given:

```js
var word = Math.imul(state ^ (state >>> ((state >>> 28) + 4)), 277803737);
```

`Math.imul` returns a *signed* 32-bit integer, so whatever reads `word` has to
finish with the `>>> 0` the module already writes.

This changes `Random`'s stream for every seed, which is the point — it is the
difference between the documented algorithm and an approximation of it — so it
wants a changelog line. Anything depending on the old numbers was depending on
float64 rounding.

A narrower alternative is to leave `peel` alone and correct the comment to say
that the low bits are not PCG's. That is worse: the reference implementation is
the only specification the function has.

## Checking the fix

`./check.sh` is the before-and-after. It prints a verdict per check and exits 0
only when every one of them passes; against `gren-lang/core` 7.4.2 it fails all
eight. It asserts two different kinds of thing on purpose:

**A. A property, carrying no expected values at all.** Over 100000 draws of
`Random.int 0 4294967295` from `Random.initialSeed 7` it measures how often
output bit k agrees with output bit k+22, for k from 0 to 6. That pair is
independent in any correct RXS-M-XS, so the answer has to be near 50 percent,
and there is nothing here to take on faith — no reference implementation, no
pinned numbers. This is the check that says whether the fix worked. The
tolerance is 1.50 percentage points, about ten standard errors at this sample
size, so it will not fail by chance; today the first six bits miss it by between
26 and 49 points.

**B. A known answer.** The first eight draws of `Random.int 1 6` and of
`Random.int 0 4294967295` from `Random.initialSeed 7`, against values from the
generator with a wrapping multiply. This is the one worth keeping in the test
suite afterwards, since it pins the whole stream rather than one property of it.
The expected values were produced twice over, once in JavaScript `BigInt` and
once with `Math.imul`, agreeing exactly.

Against core as it stands:

```
     bit  0 vs bit 22    99.26%   want 50.00% +/- 1.50   FAIL
     bit  1 vs bit 23    98.89%   want 50.00% +/- 1.50   FAIL
     bit  2 vs bit 24    97.43%   want 50.00% +/- 1.50   FAIL
     bit  3 vs bit 25    94.29%   want 50.00% +/- 1.50   FAIL
     bit  4 vs bit 26    88.56%   want 50.00% +/- 1.50   FAIL
     bit  5 vs bit 27    76.33%   want 50.00% +/- 1.50   FAIL
     bit  6 vs bit 28    52.19%   reported, not asserted: the shallowest

   Random.int 0 4294967295, from Random.initialSeed 7
     draw          got         want
        1   2412620543   2412620529   <
        2    962486949    962486954   <
        3   4105077394   4105077478   <
        4   2526171418   2526171408   <

RESULT  FAIL, 8 of 8 checks
```

With `peel`'s multiply made to wrap:

```
     bit  0 vs bit 22    49.93%   want 50.00% +/- 1.50   pass
     bit  1 vs bit 23    50.19%   want 50.00% +/- 1.50   pass
     bit  2 vs bit 24    49.91%   want 50.00% +/- 1.50   pass
     bit  3 vs bit 25    49.95%   want 50.00% +/- 1.50   pass
     bit  4 vs bit 26    50.27%   want 50.00% +/- 1.50   pass
     bit  5 vs bit 27    49.86%   want 50.00% +/- 1.50   pass
     bit  6 vs bit 28    50.26%   reported, not asserted: the shallowest

   Random.int 0 4294967295, from Random.initialSeed 7
     draw          got         want
        1   2412620529   2412620529
        2    962486954    962486954
        3   4105077478   4105077478
        4   2526171408   2526171408

RESULT  pass, all 8 checks
```

Note in part B how close the wrong numbers are to the right ones — they differ
in their last two or three digits, which is this defect seen from the other end.

That second block is measured, not predicted. It is `gren-lang/core` 7.4.2 built
as a local package with one line of `peel` changed: the multiply replaced by the
same operation done in 16-bit halves, which is what `Math.imul` computes. In the
compiled output there is exactly one line to change, and it is the one quoted
under "Suggested fix" above:

```js
var word = (state ^ (state >>> ((state >>> 28) + 4))) * 277803737;
```

## Running the examples

This directory is a stock Gren application; `devbox` pins `gren` 0.6.6 and node
22, so the scripts need nothing else installed.

| Figure | Command |
|---|---|
| `3672204992` against `3672205017` | `./run.sh` |
| the eight `Random.int 1 6` draws | `./run.sh` |
| the reference stream under them | `./run.sh`, which calls `node reference.js` |
| the worked example of the last step | `./bits.sh`, first lines of its output |
| the bit counts | `./bits.sh` |
| the bitmap | `./bits.sh` |
| the 99.26 percent figure | `./bits.sh`, last paragraph of its output |
| the 100000/100000 self-check | `./bits.sh`, first lines of its output |
| the before-and-after verdicts | `./check.sh`, which exits 0 only if all eight pass |

| File | What it is |
|---|---|
| `src/Main.gren` | the two declarations above, and the eight draws |
| `src/Bits.gren` | the measurement: draws through the public API, and a transcription of `peel` with `*` and with a wrapping multiply |
| `src/Check.gren` | the acceptance check: a property that needs no expected values, and a known-answer test |
| `reference.js` | the generator in `BigInt`, for the expected stream |

## A second, independent defect in the same module

`2026-09-10-random-int-wide-range` beside this directory: `Random.int`'s
power-of-two test and the mask it selects are both answers about an int32
truncation, so a range at or above 2^32 is mishandled. It was found while reading
`Random` for this one and shares nothing with it mechanically — fixing either
leaves the other standing, which is why they are two reports.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Node.js v22, Linux x86-64
