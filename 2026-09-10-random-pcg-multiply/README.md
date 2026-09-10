# `Random` is not the PCG it documents, and `Random.int` truncates above 2^32

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22.

Two findings in one module. `./run.sh` prints both, then `reference.js` prints the
same generator implemented in `BigInt` for comparison.

Expected output:

```
the multiply, low 32 bits of 2000000001 * 277803737
  Gren             3672204992
  exact            3672205017

eight Random.int 1 6 draws from Random.initialSeed 7
  Gren             6 4 5 5 3 3 6 4

ranges at or past 2^32, where the power-of-two test truncates
  int 0 0xFFFFFFFF    2412620543 962486949 4105077394 2526171418 1015690994 2793901850
  int 0 0x100000000   0 0 0 0 0 0
  int 0 0x17FFFFFFF   265136895 962486949 1957593746 378687770 1015690994 646418202

--- the same generator in exact arithmetic, for comparison ---
true PCG, d6 seed 7      : 4 3 5 1 5 5 6 3
```

**The multiply.** `peel` multiplies a 32-bit word by `277803737` modulo 2^32, but
`*` is the float64 operation, so the product reaches 2^60 and the low bits are
gone before `>>> 22` reads them. `Math.imul(2000000001, 277803737)` in the same
node process returns `-622762279`, which is `3672205017` read as a signed 32-bit
integer: the wrapping multiply keeps exactly the bits the float64 one loses. The
eight draws differ from the reference generator for that reason.

**`Random.int` above a range of 2^32.** `Bitwise.and` coerces both operands to
int32, so the power-of-two test and the mask it picks are both answers about a
truncation. `int 0 0x100000000` has `range - 1 == 2^32`, which masks to `0`, so
every draw is the lower bound. `int 0 0x17FFFFFFF` masks to `0x7FFFFFFF` and can
only reach the low third of its interval. `int 0 0xFFFFFFFF` — the one the module
itself calls, in `independentSeed` — works, because `-1 & 0` is `0` and a mask of
`-1` is the identity.
