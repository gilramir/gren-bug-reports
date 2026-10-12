# `gren make` takes time quadratic in a module's definitions: `addLocals` rebuilds every name in scope for each one

A module of 64,000 top-level values takes `gren make` over a minute to check,
where 16,000 take about two and a half seconds. So does a module of 64,000
functions, and a `let` of 64,000 definitions. A one-word change to
`Canonicalize.Environment.addLocals` makes all three take one to three
seconds.

## Reproduction

`./run.sh` runs under `devbox`, which provides `gren` 0.6.6 and node 22. For
each shape and size, `gen.py SHAPE N` writes `src/Big.gren`, and `run.sh`
times `gren make Big` from an empty `.gren` cache. `Big` has no `main`, so it
is checked and nothing is generated. `GREN_BIN` names the compiler binary
the `gren` command runs, so the same script times a build with the change
below: `GREN_BIN=/path/to/gren ./run.sh`.

- **declarations:** N top-level `xK : Int` values, and `value = x0 + x(N-1)`.
- **functions:** N top-level functions of one argument, each calling the one
  before.
- **let:** one `let` of N definitions, each the one before plus one.

| shape | N | `gren make Big`, 0.6.6 (s) | with the fix below (s) |
|---|---|---|---|
| declarations | 4000 | 0.4 | 0.3 |
| declarations | 16000 | 2.4 | 0.5 |
| declarations | 64000 | 72.1 | 1.2 |
| functions | 4000 | 0.5 | 0.4 |
| functions | 16000 | 2.8 | 0.8 |
| functions | 64000 | 80.1 | 2.7 |
| let | 4000 | 0.4 | 0.3 |
| let | 16000 | 2.4 | 0.5 |
| let | 64000 | 51.4 | 1.5 |

The first column is the released 0.6.6. The second is the 0.6.6 tag built
with the change below (`cabal build`, GHC 9.10.3) and run through the same
`gren` command with `GREN_BIN`. Times vary between machines and runs.

## The cause

`addLocals` adds a definition's arguments, or a `let`'s names, to the
environment:

```haskell
addLocals names (Env home vars ts cs bs qvs qts qcs) =
  do
    newVars <-
      Map.mergeA
        (Map.mapMissing addLocalLeft)
        (Map.mapMissing (\_ homes -> homes))
        (Map.zipWithAMatched addLocalBoth)
        names
        vars
```

The second tactic keeps every name in scope that `names` does not shadow,
and it is the identity. But `Data.Map` cannot see that a function passed to
`mapMissing` is the identity, so `mergeA` applies it to every name in `vars`
and builds a new map of them, once for each definition. With N top-level
names in scope and N definitions, that is N² work.

## The fix

`Map.preserveMissing` keeps the missing entries as they are, and lets
`mergeA` keep whole subtrees of `vars` that `names` does not touch:

```diff
       Map.mergeA
         (Map.mapMissing addLocalLeft)
-        (Map.mapMissing (\_ homes -> homes))
+        Map.preserveMissing
         (Map.zipWithAMatched addLocalBoth)
         names
         vars
```

The resulting map is the same, so the change cannot alter what compiles.

---

- **Filed as:** not yet
- **Package:** `gren-lang/compiler`, `Canonicalize.Environment.addLocals`
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22.23.2
