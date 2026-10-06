# A task like `Time.now` runs once, and the second run stops the program

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.5.0 (and `main` at
`2bd7c75`), `gren-lang/node` 6.2.0, node 22
**Filed:** not yet.

With core 7.5.0, a program that runs `Time.now` a second time stops there. It
prints nothing more and exits with status 0. The same program with core 7.4.2
runs to the end. Any task that is a single value built on a kernel binding
behaves the same way, and `Time.now` is the commonest. Timing two things one
after the other is enough to hit it.

## Reproduction

`./run.sh` (it runs under `devbox`, which provides `gren` 0.6.6 and node 22)
builds and runs `src/Main.gren`:

```gren
main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        let
            say text =
                Stream.writeLineAsBytes text env.stdout
                    |> Task.map (\_ -> {})
                    |> Task.onError (\_ -> Task.succeed {})
        in
        Node.endSimpleProgram
            (say "start"
                |> Task.andThen (\_ -> Time.now)
                |> Task.andThen (\_ -> say "first Time.now done")
                |> Task.andThen (\_ -> Time.now)
                |> Task.andThen (\_ -> say "second Time.now done")
            )
```

| core | node | output | exit |
|---|---|---|---|
| 7.4.2 | 6.1.3 | `start`, `first Time.now done`, `second Time.now done` | 0 |
| 7.4.2 | 6.2.0 | `start`, `first Time.now done`, `second Time.now done` | 0 |
| 7.5.0 | 6.1.3 | `start`, `first Time.now done` | 0 |
| 7.5.0 | 6.2.0 | `start`, `first Time.now done` | 0 |

The change is in core, not node.

## Cause

`a2eeb37` ("Scheduler improvements", the fix for #136) marks a binding as
running so that `_Scheduler_step` does not call its callback twice:

```js
} else if (rootTag === __1_BINDING) {
  if (proc.__root.__running) {
    return;
  }
  proc.__root.__running = true;
  proc.__root.__kill = proc.__root.__callback(function (newRoot) {
```

The mark is on the task, not on the process, and nothing clears it. `Time.now`
is one value, `Gren.Kernel.Time.now millisToPosix`, shared by every use. After
its first run its `__running` is `true` for good. The next process step that
reaches it returns without calling the callback and without queueing the process
again. The process waits on nothing, and node exits because nothing is pending.

## Fix

Keep the mark on the process, and clear it when the binding answers:

```js
} else if (rootTag === __1_BINDING) {
  if (proc.__waiting) {
    return;
  }
  proc.__waiting = true;
  proc.__root.__kill = proc.__root.__callback(function (newRoot) {
    if (proc.__root == null) {
      return;
    }
    proc.__waiting = false;
    proc.__root = newRoot;
    _Scheduler_enqueue(proc);
  });
```

That edit, made by hand in the compiled program, prints all three lines. A
process still never calls the callback of the binding it is waiting on twice,
which is what #136 needed. This was not run against #136's reproduction.
