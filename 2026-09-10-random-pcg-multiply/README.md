# `Random` is not the PCG it documents: `peel`'s multiply overflows float64

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22.

`./run.sh` prints the multiply both ways and eight draws, then `reference.js`
prints the same generator implemented in `BigInt` for comparison.

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


A second, independent defect in the same module is in
`2026-09-10-random-int-wide-range` beside this one: `Random.int`'s power-of-two
test truncates to int32, so a range at or above 2^32 is mishandled.
