# `gren make` can exit without printing `Success!`: the wait for the build's reporter thread passes when the thread has not started

`compiler#304` reported a `gren make` that ended on `Compiling (2)` instead of
`Success!`. `compiler#326` closed it by having `attemptWithStyle` wait with
`readMVar mvar` before it returns. That wait does not wait for a reporter
thread that has not started yet, so the line can still be lost. Machines under
load hit it, because a build whose modules are cached is over in milliseconds.

## Reproduction

The thread starting late is a matter of scheduling, so `delay.patch` makes it
start late every time: it puts `threadDelay 300000` at the start of the
thread `trackBuild` forks, and changes nothing else. `./run.sh` runs under
`devbox`, which provides `gren` 0.6.6 and node 22. It builds `Main`, a
program that does nothing, three times from an empty `.gren`, and prints each
build's whole output with `cat -A`, so a carriage return shows as `^M`.
`GREN_BIN` names the compiler binary the `gren` command runs, so the same
script runs a compiler built from source.

The compiler binaries were built from `gren-lang/compiler` `main` at
`8da05185` with `cabal build -f dev`, GHC 9.10.3.

| compiler | each of the three builds prints |
|---|---|
| released 0.6.6 | `Compiling ...^MCompiling (1)^MSuccess! Compiled 1 module.` |
| `main` with `delay.patch` | nothing; the exit status is 0 |
| `main` with `delay.patch` and `fix.patch` | `Compiling ...^MCompiling (1)^MSuccess! Compiled 1 module.` |

Without `--output=/dev/null`, the build with `delay.patch` prints only the
`Main ───> app` line, with no `Success!` above it.

## The cause

```haskell
    Terminal mvar ->
      do
        chan <- newChan

        _ <- forkIO $
          do
            takeMVar mvar
            putStrFlush "Compiling ..."
            buildLoop chan 0
            putMVar mvar ()

        result <- callback (Key (writeChan chan . Left))
        writeChan chan (Right result)
        return result
```

The thread takes `mvar` when it starts and puts it back after `buildLoop` has
written the final line. `attemptWithStyle`, and `reportGenerate`, wait for
that line with `readMVar mvar`. That only blocks while the thread holds
`mvar`. If the thread has not run yet, `mvar` is still full, `readMVar`
returns at once, and `main` returns. The program exits before the thread
writes anything. A thread that has started but not finished is waited for
correctly, which is why `#326` fixed most of what `#304` saw.

A build that fails loses its line the same way. With a type error added to
`Main` (`wrong : Int` defined as `"a"`), the released compiler prints the
`TYPE MISMATCH` report on stderr and `Compiling ...^MDetected problems in 1
module.` on stdout. The build with `delay.patch` prints the report and leaves
stdout empty, exit status 1 either way. With `fix.patch` as well, stdout is the
released compiler's again.

## The fix

`trackBuild` waits for its thread to finish before it returns
(`fix.patch`). After that the thread has put `mvar` back, so every
`readMVar mvar` after it finds the final line written.

```haskell
        chan <- newChan
        finished <- newEmptyMVar

        _ <- forkIO $
          do
            takeMVar mvar
            putStrFlush "Compiling ..."
            buildLoop chan 0
            putMVar mvar ()
            putMVar finished ()

        result <- callback (Key (writeChan chan . Left))
        writeChan chan (Right result)
        takeMVar finished
        return result
```
