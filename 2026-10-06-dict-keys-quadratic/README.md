# `Dict.keys`, `Dict.values` and `Set.toArray` take time quadratic in the size

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2 (the code is the same
in 7.5.0 and on `main` at `2bd7c75`), `gren-lang/node` 6.1.3, node 22
**Filed:** not yet.

`Dict.keys` on a dictionary of 80,000 entries takes about 11.7 seconds, and so
does `Dict.values`. Collecting the same keys with an `Array.Builder` takes 2 ms.
Each doubling of the size multiplies the time by about four. `Set.toArray` is
`Dict.keys`, so it has the same cost.

## Reproduction

`./run.sh` (it runs under `devbox`, which provides `gren` 0.6.6 and node 22)
builds and runs `src/Main.gren`. It builds a `Dict Int Int` of each size, then
times `Dict.keys`, `Dict.values` and `keysWithBuilder`:

```gren
keysWithBuilder : Dict k v -> Array k
keysWithBuilder dict =
    Dict.foldl (\key _ builder -> Builder.pushLast key builder) (Builder.empty (Dict.count dict)) dict
        |> Builder.toArray
```

Output (times vary by machine and between runs; the number in brackets is the
length of the result):

```
| entries | Dict.keys ms | Dict.values ms | keysWithBuilder ms |
|---|---|---|---|
| 10000 | 24 (10000) | 30 (10000) | 1 (10000) |
| 20000 | 349 (20000) | 350 (20000) | 1 (20000) |
| 40000 | 2775 (40000) | 2758 (40000) | 2 (40000) |
| 80000 | 11667 (80000) | 11618 (80000) | 2 (80000) |
```

The program is pinned to core 7.4.2. On 7.5.0 it stops after its first row,
because a second run of `Time.now` stops the program (reported separately,
`2026-10-06-binding-runs-once`).

## Cause

```gren
keys dict =
    foldl (\key value keyArray -> Array.pushLast key keyArray) [] dict

values dict =
    foldl (\key value valueArray -> Array.pushLast value valueArray) [] dict
```

`Array.pushLast` copies the array, so each key is copied once for every key
after it: n²/2 element copies for n entries. `Set.toArray` calls `Dict.keys`.

## Fix

Fold into an `Array.Builder` with the dictionary's count as its capacity, as in
`keysWithBuilder` above, and the same for `values`. That is the change #166's
fix made to `Task.sequence` in `b0e2a0b`.
