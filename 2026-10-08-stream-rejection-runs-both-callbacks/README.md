# A rejected `Stream` operation calls back twice since 7.5.0

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.5.0 (and `main` at
`2bd7c75`), `gren-lang/node` 6.2.0, node 22
**Filed:** not yet. It follows up
[core#142](https://github.com/gren-lang/core/issues/142), closed by `7c95136`,
and bears on [core#169](https://github.com/gren-lang/core/issues/169), which
proposes the same change for `Crypto`.

## Summary

`7c95136` fixed core#142, where an exception thrown after a stream write was
caught by the write's own `.catch`. It moved the `.catch` in front of the
`.then` in `read`, `write`, `closeWritable` and `pipeTo`:

```js
promise
  .catch((err) => { callback(__Scheduler_fail(...)); })
  .then(() => { callback(__Scheduler_succeed(stream)); });
```

A `.catch` whose handler returns normally resolves the promise it makes, so the
`.then` after it runs as well. When the stream operation is rejected, the
binding calls back twice: first with the `Cancelled` failure, then, a microtask
later, with success. The scheduler's binding callback checks only that the
process is alive, so the second call replaces whatever the process is waiting
on by then, which is the first binding the error handler reached.

| operation rejected | 7.4.2 | 7.5.0 |
|---|---|---|
| `write`, `closeWritable`, `pipeTo` | fails once | fails, then a binding in `onError` is answered with the `Writable` (or `{}`) and skipped |
| `read` | fails once | fails, then the `.then` destructures `undefined` and node exits with a `TypeError` |

## Reproduction

`~/prj/gren-bug-reports/2026-10-08-stream-rejection-runs-both-callbacks`:
`./run.sh` builds and runs two programs under `devbox`, which provides `gren`
0.6.6 and node 22. Changing `gren.json` to core 7.4.2 and node 6.1.3 gives the
7.4.2 output.

`Write` writes to a stream it has closed. Its `onError` prints the error,
sleeps 200 ms and prints again, while a second process prints after 100 ms:

```gren
Process.spawn (Process.sleep 100 |> Task.andThen (\_ -> say "100 ms have passed"))
    |> Task.andThen (\_ -> Stream.identityTransformation)
    |> Task.andThen
        (\t ->
            Stream.closeWritable (Stream.writable t)
                |> Task.andThen (\_ -> Stream.write "x" (Stream.writable t))
                |> Task.andThen (\_ -> say "the write succeeded")
                |> Task.onError
                    (\e ->
                        say ("the write failed: " ++ Stream.errorToString e)
                            |> Task.andThen (\_ -> Process.sleep 200)
                            |> Task.andThen (\_ -> say "slept 200 ms")
                    )
        )
```

core 7.4.2:

```
the write failed: Cancelled: TypeError [ERR_INVALID_STATE]: Invalid state: WritableStream is closed
100 ms have passed
slept 200 ms
```

core 7.5.0:

```
the write failed: Cancelled: TypeError [ERR_INVALID_STATE]: Invalid state: WritableStream is closed
slept 200 ms
100 ms have passed
```

The second callback answered the `say` that `onError` was waiting on, so the
program went on to the sleep early, and the `say`'s own completion then
answered the sleep, which never took its 200 ms.

`Read` cancels a transformation's writable side, which errors its readable
side, and reads:

```gren
Stream.cancelWritable "boom" (Stream.writable t)
    |> Task.andThen (\_ -> Stream.read (Stream.readable t))
    |> Task.andThen (\v -> say ("read: " ++ v))
    |> Task.onError (\e -> say ("the read failed: " ++ Stream.errorToString e))
    |> Task.andThen (\_ -> say "after the read")
```

core 7.4.2 prints the two lines and exits 0. core 7.5.0 prints them and then:

```
      .then(({ done, value }) => {
               ^

TypeError: Cannot destructure property 'done' of 'undefined' as it is undefined.
```

and exits 1.

## Fix

Give both handlers to one `.then`. Only one of them runs, and an exception
thrown by either is not caught by the other, which was core#142:

```js
promise.then(
  () => { callback(__Scheduler_succeed(stream)); },
  (err) => { callback(__Scheduler_fail(__Stream_Cancelled(_Stream_cancellationErrorString(err)))); },
);
```

`read` is the same with its `({ done, value })` handler first. The change
core#169 asks for in the `Crypto` kernel would want this form too; the
`.catch`-then-`.then` order would bring the same double callback there.
