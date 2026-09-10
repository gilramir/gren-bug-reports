# `Random.int` returns its lower bound forever when the range is 2^32 + 1

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22.

`./run.sh` prints six draws from `Random.initialSeed 7` at three ranges.

Expected output:

```
six Random.int draws from Random.initialSeed 7, per range

  int 0 0xFFFFFFFF   range 2^32     2412620543 962486949 4105077394 2526171418 1015690994 2793901850
  int 0 0x100000000  range 2^32+1   0 0 0 0 0 0
  int 0 0x17FFFFFFF  range 1.5*2^32 265136895 962486949 1957593746 378687770 1015690994 646418202
```

`Random.int`'s power-of-two test is `Bitwise.and (range - 1) range == 0`, and
`Bitwise.and` is JavaScript `&`, which coerces both operands to int32. An `Int`
is a float64 and holds more than that, so at 2^32 and above both the test and the
mask it selects are answers about a truncation. For `range = 2^32 + 1` the mask
is `2^32 | 0`, which is `0`, so every draw is the lower bound.

The first row works because `-1 & 0` is `0` and a mask of `-1` is the identity —
two truncations cancelling at the one width `core` itself uses, in
`independentSeed`.
