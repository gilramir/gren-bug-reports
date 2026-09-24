# A cancelled task keeps running once the operation it was waiting on finishes

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-16-cancelled-task-runs-on
**Filed:** not yet.

A process killed with `Process.kill` while it waits on `FileSystem.readFile`
carries on with the rest of its task once the read finishes. The same happens to
a task in `Task.concurrent` whose sibling failed: the `concurrent` has already
failed and its caller has handled the error, and the cancelled task still runs
its next step. This holds for any operation without a cancel function, which is
most of them.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import FileSystem
import FileSystem.Path as Path
import Init
import Node
import Process
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Init.await FileSystem.initialize <| \fs ->
            let
                say text =
                    Stream.writeLineAsBytes text env.stdout
                        |> Task.map (\_ -> {})
                        |> Task.onError (\_ -> Task.succeed {})

                -- FileSystem.readFile has no cancel function
                read =
                    FileSystem.readFile fs (Path.fromPosixString "gren.json")
                        |> Task.mapError (\_ -> "read failed")
            in
            Node.endSimpleProgram
                (say "1. Process.kill"
                    |> Task.andThen (\_ -> Process.spawn (read |> Task.andThen (\_ -> say "   the killed process ran on")))
                    |> Task.andThen Process.kill
                    |> Task.andThen (\_ -> say "   killed")
                    |> Task.andThen (\_ -> Process.sleep 500)
                    |> Task.andThen (\_ -> say "2. Task.concurrent")
                    |> Task.andThen
                        (\_ ->
                            Task.concurrent
                                [ read |> Task.andThen (\_ -> say "   the cancelled sibling ran on")
                                , Task.fail "the other task failed"
                                ]
                                |> Task.map (\_ -> {})
                                |> Task.onError (\e -> say ("   concurrent failed: " ++ e))
                        )
                    |> Task.andThen (\_ -> Process.sleep 500)
                    |> Task.andThen (\_ -> say "done")
                )
```

Output:

```
1. Process.kill
   killed
   the killed process ran on
2. Task.concurrent
   concurrent failed: the other task failed
   the cancelled sibling ran on
done
```

Neither `ran on` line should appear.

## Cause

Cancelling sets the process's `__root` to `null` and calls the binding's cancel
function, if it has one. `readFile` has none, so its callback still fires, and
`_Scheduler_step` in `src/Gren/Kernel/Scheduler.js` puts the process back:

```js
} else if (rootTag === __1_BINDING) {
  proc.__root.__kill = proc.__root.__callback(function (newRoot) {
    proc.__root = newRoot;          // runs even after rawKill set __root to null
    _Scheduler_enqueue(proc);
  });
  return;
}
```

## Fix

Ignore a callback for a binding the process is no longer waiting on:

```js
} else if (rootTag === __1_BINDING) {
  var binding = proc.__root;
  binding.__kill = binding.__callback(function (newRoot) {
    if (proc.__root !== binding) {
      return;
    }
    proc.__root = newRoot;
    _Scheduler_enqueue(proc);
  });
  return;
}
```

With this patched into the compiled program, neither `ran on` line is printed.
