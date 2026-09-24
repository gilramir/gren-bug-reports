# `Task.sequence` takes time quadratic in the number of tasks

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-16-task-sequence-quadratic
**Filed:** not yet.

`Task.sequence` over 80,000 tasks that each succeed at once takes about 11
seconds; `Task.concurrent` over the same array takes about 30 ms. Doubling the
number of tasks multiplies `sequence`'s time by 4 to 12.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Node
import Stream
import Task exposing (Task)
import Time


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        let
            say text =
                Stream.writeLineAsBytes text env.stdout
                    |> Task.map (\_ -> {})
                    |> Task.onError (\_ -> Task.succeed {})

            ms task =
                Time.now
                    |> Task.andThen (\t0 -> task |> Task.andThen (\_ -> Time.now) |> Task.map (\t1 -> String.fromInt (Time.posixToMillis t1 - Time.posixToMillis t0)))

            row n =
                let
                    tasks =
                        Array.initialize n 0 Task.succeed
                in
                ms (Task.sequence tasks)
                    |> Task.andThen (\s -> ms (Task.concurrent tasks) |> Task.map (\c -> s ++ " | " ++ c))
                    |> Task.andThen (\sc -> ms (sequenceByHalves tasks) |> Task.map (\h -> sc ++ " | " ++ h))
                    |> Task.andThen (\times -> say ("| " ++ String.fromInt n ++ " | " ++ times ++ " |"))
        in
        Node.endSimpleProgram
            (Array.foldl (\n before -> before |> Task.andThen (\_ -> row n))
                (say "| tasks | Task.sequence ms | Task.concurrent ms | sequenceByHalves ms |\n|---|---|---|---|")
                [ 10000, 20000, 40000, 80000 ]
            )


{-| The fix: run the first half, then the second, and append. -}
sequenceByHalves : Array (Task x a) -> Task x (Array a)
sequenceByHalves tasks =
    when Array.length tasks is
        0 ->
            Task.succeed []

        1 ->
            when Array.first tasks is
                Just task ->
                    Task.map (\x -> [ x ]) task

                Nothing ->
                    Task.succeed []

        n ->
            let
                half =
                    n // 2
            in
            sequenceByHalves (Array.slice 0 half tasks)
                |> Task.andThen (\first -> Task.map (\second -> first ++ second) (sequenceByHalves (Array.slice half n tasks)))
```

Output (times vary by machine and between runs):

```
| tasks | Task.sequence ms | Task.concurrent ms | sequenceByHalves ms |
|---|---|---|---|
| 10000 | 29 | 3 | 5 |
| 20000 | 341 | 3 | 10 |
| 40000 | 2648 | 6 | 13 |
| 80000 | 11200 | 29 | 23 |
```

## Cause

`sequence` is a right fold that adds each result to the front of the array built
so far:

```gren
sequence =
    Array.foldr (\task combined -> task |> andThen (\x -> map (Array.pushFirst x) combined)) (succeed [])
```

`Array.pushFirst` copies the array, so each result is copied once for every task
after it: n²/2 element copies for n tasks.

## Fix

`sequenceByHalves` in the program above: run the first half, then the second, and
append. Each result is copied once per level, O(n log n), and the tasks still run
one at a time in order. Over 1,000 tasks it gives the same results as
`Task.sequence`, and with failures at indices 700 and 900 it stops at the same
first failure.
