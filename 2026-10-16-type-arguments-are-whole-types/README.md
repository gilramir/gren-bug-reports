# A type's arguments are parsed as whole types

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` `main` at
`d8dedc6` (and 3.0.0), `gren-lang/core` 7.6.0, `gren-lang/node` 6.2.0, node 22

`./run.sh` fetches `compiler-common` at `d8dedc6` and builds and runs
`src/Main.gren` under `devbox`. Each row is an annotation, `x : T`, given to
`Compiler.Parse.Declaration.parser`, and the tree it built: `->` in
parentheses, and an application as its head with each argument in brackets.

```
Dict String Int	Dict [String [Int]]
Dict String Int -> Int	Dict [String [(Int -> Int)]]
Result String Int -> Maybe Int -> Bool	Result [String [(Int -> Maybe [(Int -> Bool)])]]
Maybe Maybe Int	Maybe [Maybe [Int]]
Dict String (Int -> Int)	Dict [String [((Int -> Int))]]
```

`gren make` reads `Dict String Int -> Int` as `(Dict String Int) -> Int`, and
`Maybe Maybe Int` as `Maybe` given two arguments, which it refuses with
`TOO FEW ARGS` for the inner `Maybe`.
