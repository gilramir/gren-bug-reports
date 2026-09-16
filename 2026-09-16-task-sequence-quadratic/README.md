# `Task.sequence` takes time quadratic in the number of tasks

`Task.sequence` is a right fold that adds each result to the front of the array
built so far:

```gren
sequence =
    Array.foldr (\task combined -> task |> andThen (\x -> map (Array.pushFirst x) combined)) (succeed [])
```

`Array.pushFirst` copies the array, so the results are copied once for each
task after them: n²/2 element copies for n tasks. Doubling the tasks multiplies
the time by 4 to 12, and 80,000 tasks that each succeed at once take 11 to 14
seconds, where `Task.concurrent` over the same array takes about 25 ms.

## Reproduction

`src/Main.gren` times `Task.sequence`, `Task.concurrent` and the fix below over
arrays of `Task.succeed`, doubling the length, then checks that the fix gives
the same results and stops at the same failure as `Task.sequence`.

```
$ ./run.sh
$ node app
  tasks   sequence ms  concurrent ms  by halves ms
  10000          44             3           7
  20000         426             3           8
  40000        3284             8          14
  80000       14495            21          26
same results and same first failure: yes
```

The times vary between runs. A first run gave 29, 352, 2606 and 11127 ms for
`sequence`.

## The fix

Run the first half, then the second, and append. Each result is copied once
per level, which is O(n log n):

```gren
sequence : Array (Task x a) -> Task x (Array a)
sequence tasks =
    when Array.length tasks is
        0 ->
            succeed []

        1 ->
            when Array.first tasks is
                Just task ->
                    map (\x -> [ x ]) task

                Nothing ->
                    succeed []

        n ->
            let
                half =
                    n // 2
            in
            sequence (Array.slice 0 half tasks)
                |> andThen (\first -> map (\second -> first ++ second) (sequence (Array.slice half n tasks)))
```

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** `gren` 0.6.6, `gren-lang/node` 6.1.3, node 22
