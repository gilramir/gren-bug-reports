# `Random` is not the PCG it documents: `peel`'s multiply overflows float64

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22.

`./run.sh` prints the multiply both ways and then eight `Random.int 1 6` draws,
followed by the same generator implemented in `BigInt` for comparison.

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

`Math.imul(2000000001, 277803737)` in the same node process returns
`-622762279`, which is `3672205017` read as a signed 32-bit integer: the wrapping
multiply keeps exactly the bits the float64 one loses.
