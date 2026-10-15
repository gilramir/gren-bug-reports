# `String.Parser.loop`'s example takes time quadratic in the number of statements, and `core` has no collecting parser or `Result` fold

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.6.0, `gren-lang/node`
6.2.0, node 22
**Filed:** not yet.

The example in `String.Parser.loop`'s documentation, a loop that collects
statements by `Array.pushLast` onto its state, takes 12.9 seconds to parse
80,000 statements. The same loop with the statements in an `Array.Builder`
takes 1.3 seconds. Each doubling of the input multiplies the first by about
four and the second by about two.

The same happens to a fold through `Result` whose step pushes onto the array
it is handed, which is how a library collects the answers of a step that can
fail when `core` has nothing for it: 11.9 seconds for 80,000 elements, against
1 ms collected into a `Builder`.

## Reproduction

`./run.sh` (it runs under `devbox`, which provides `gren` 0.6.6 and node 22)
builds and runs `src/Main.gren`. For each size it parses `"1; "` repeated that
many times with the documented loop, `int` as the statement, and with the same
loop over a `Builder`, then folds `Array.range 1 n` with `resultFoldl` and with
`sequenceMap` (both below):

```gren
statementsHelp : Array Int -> Parser (Step (Array Int) (Array Int))
statementsHelp stmts =
    P.oneOf
        [ P.succeed (\stmt -> Loop (Array.pushLast stmt stmts))
            |> P.keep P.int
            |> P.skip P.spaces
            |> P.skip (P.token ";")
            |> P.skip P.spaces
        , P.succeed {}
            |> P.map (\_ -> Done stmts)
        ]

resultFoldl : (i -> a -> Result e a) -> a -> Array i -> Result e a
resultFoldl callback initialAcc items =
    Array.foldl (\item acc -> acc |> Result.andThen (callback item)) (Ok initialAcc) items
```

Output (milliseconds; times vary by machine and between runs; the number in
brackets is the length of the result):

```
| n | loop, as documented | loop, with a Builder | fold, pushing | fold, into a Builder |
|---|---|---|---|---|
| 10000 | 192 (10000) | 157 (10000) | 21 (10000) | 1 (10000) |
| 20000 | 667 (20000) | 303 (20000) | 344 (20000) | 1 (20000) |
| 40000 | 3434 (40000) | 610 (40000) | 2764 (40000) | 2 (40000) |
| 80000 | 12944 (80000) | 1304 (80000) | 11901 (80000) | 1 (80000) |
```

## Cause

`Array.pushLast` copies the array, so a loop that pushes once a step copies
each element once for every element after it. The documentation is what
people copy: the same shape was in `compiler-common`'s parser loops and in
`gren-format-lib`'s folds.

## Fix

Three small changes:

1. **`loop`'s documentation** keeps its statements in an `Array.Builder`, as
   `withBuilder` in `src/Main.gren` does, and says why.
2. **A collecting parser**, so that a plain run of items needs no loop at all:

   ```gren
   {-| Zero or more of a parser, in order. It stops at the first item that
   fails without chomping, or that succeeds without chomping (not kept, so it
   cannot loop forever); an item that fails after chomping fails it. -}
   many : Parser c x a -> Parser c x (Array a)
   many (Parser parse) =
     Parser <| \s -> manyHelp False parse (Builder.empty 0) s

   manyHelp p parse items s0 =
     when parse s0 is
       Good { pred = p1, value = item, state = s1 } ->
         if s1.offset == s0.offset then
           Good { pred = p, value = Builder.toArray items, state = s0 }
         else
           manyHelp (p || p1) parse (Builder.pushLast item items) s1

       Bad { pred = p1, bag = x } ->
         if p1 then
           Bad { pred = True, bag = x }
         else
           Good { pred = p, value = Builder.toArray items, state = s0 }
   ```

   in `String.Parser.Advanced` (which then imports `Array.Builder as Builder`),
   and `many = A.many` in `String.Parser`.
3. **A collecting `Result` fold** beside `Result.sequence`, which stops at the
   first `Err`:

   ```gren
   sequenceMap : (a -> Result err ok) -> Array a -> Result err (Array ok)
   ```

   with the body of `sequenceMap` in `src/Main.gren`.
