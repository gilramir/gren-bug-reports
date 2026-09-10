# `Random` is not the PCG it documents: `peel`'s multiply overflows float64

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22.

`./run.sh` prints the multiply both ways and eight draws, then `reference.js`
prints the same generator implemented in `BigInt` for comparison. `./bits.sh`
shows where the lost bits go, counted over 100000 draws through the public API.

Expected output:

```
the multiply, low 32 bits of 2000000001 * 277803737
  Gren             3672204992
  exact            3672205017

eight Random.int 1 6 draws from Random.initialSeed 7
  Gren             6 4 5 5 3 3 6 4

--- the same generator in exact arithmetic, for comparison ---
true PCG, d6 seed 7      : 4 3 5 1 5 5 6 3
```

`peel` multiplies a 32-bit word by `277803737` modulo 2^32, but
`*` is the float64 operation, so the product reaches 2^60 and the low bits are
gone before `>>> 22` reads them. `Math.imul(2000000001, 277803737)` in the same
node process returns `-622762279`, which is `3672205017` read as a signed 32-bit
integer: the wrapping multiply keeps exactly the bits the float64 one loses. The
eight draws differ from the reference generator for that reason.


## Where the bits go

`peel` ends with `p = word ^ (word >>> 22)`, and a 32-bit value shifted right
by 22 twice is zero, so that step is its own inverse: `word = p ^ (p >>> 22)`
recovers the pre-xor word from a number `Random` hands out. Counting bits over
the recovered word is what `./bits.sh` does, and it needs no reference
implementation to see the hole -- only to show what should have been in it.

```
`Random`'s 32-bit output word, 100000 draws from Random.initialSeed 7.

self-check: `peel` transcribed with `*` reproduces 100000/100000 of them, so the only
difference in the `imul` column below is the multiply.


How often each bit is 1. `word` is peel's value before its last step,
recovered from the output by `word = p ^ (p >>> 22)`.

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
  bit 10    49.86%    49.86% |##########          |    49.89% |##########          |
  bit 11    50.03%    50.03% |##########          |    50.06% |##########          |
  bit 12    49.91%    49.91% |##########          |    49.91% |##########          |
  bit 13    49.81%    49.81% |##########          |    49.84% |##########          |
  bit 14    50.26%    50.26% |##########          |    50.26% |##########          |
  bit 15    49.79%    49.79% |##########          |    49.78% |##########          |
  bit 16    49.84%    49.84% |##########          |    49.84% |##########          |
  bit 17    50.28%    50.28% |##########          |    50.28% |##########          |
  bit 18    49.71%    49.71% |##########          |    49.71% |##########          |
  bit 19    50.07%    50.07% |##########          |    50.07% |##########          |
  bit 20    49.99%    49.99% |##########          |    49.99% |##########          |
  bit 21    50.24%    50.24% |##########          |    50.25% |##########          |
  bit 22    50.05%    50.05% |##########          |    50.05% |##########          |
  bit 23    50.16%    50.16% |##########          |    50.16% |##########          |
  bit 24    50.07%    50.07% |##########          |    50.07% |##########          |
  bit 25    49.92%    49.92% |##########          |    49.92% |##########          |
  bit 26    50.11%    50.11% |##########          |    50.11% |##########          |
  bit 27    49.91%    49.91% |##########          |    49.91% |##########          |
  bit 28    49.98%    49.98% |##########          |    49.98% |##########          |
  bit 29    49.89%    49.89% |##########          |    49.89% |##########          |
  bit 30    50.21%    50.21% |##########          |    50.21% |##########          |
  bit 31    49.83%    49.83% |##########          |    49.83% |##########          |

The output looks like 32 fair coins, which is why this went unnoticed. The
word it was made from does not: below bit 7 the bits are not there to be
shifted. 277803737 is 2^28.05, so the product of it and a 32-bit word reaches
2^60.05, a float64 holds 53 bits of that, and the lowest seven are rounded
away before `>>> 22` goes looking for them.

Equivalently, without recovering anything: `word` bit k is output bit k xor
output bit k+22, so a zero there is two bits of `Random`'s own output that are
always equal. Bit 0 equals bit 22 in 99.26% of the draws above, against 49.93% for
RXS-M-SH, in which they are independent.


The same recovered `word`, one draw per row, bit 31 leftmost:

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

Read without recovering anything, the same measurement says that `word` bit k
is output bit k xor output bit k+22, so a zero there is two bits of `Random`'s
own output that are always equal.

A second, independent defect in the same module is in
`2026-09-10-random-int-wide-range` beside this one: `Random.int`'s power-of-two
test truncates to int32, so a range at or above 2^32 is mishandled.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Node.js v22, Linux x86-64
