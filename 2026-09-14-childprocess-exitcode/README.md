# `ChildProcess.run` puts `null` or a string into `exitCode : Int` after a timeout, a signal or too much output

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`ChildProcess.run` fails with `ProgramError { exitCode : Int, … }` whenever the
program was started and did not succeed. When the program did not exit with a
code, which is what `runDuration` and a signal do, and when it wrote more than
`maximumBytesWrittenToStreams`, `exitCode` is not an `Int`:

| how the program ended | `String.fromInt e.exitCode` | `e.exitCode + 1` | `e.exitCode > 0` |
|---|---|---|---|
| `sh -c "exit 3"` | `3` | `4` | `True` |
| stopped by `runDuration = Milliseconds 100` | **`null`** | **`1`** | `False` |
| wrote past `maximumBytesWrittenToStreams = 4` | **`ERR_CHILD_PROCESS_STDIO_MAXBUFFER`** | **`ERR_CHILD_PROCESS_STDIO_MAXBUFFER1`** | `False` |
| killed by a signal (`kill -9 $$`) | **`null`** | **`1`** | `False` |

Every value in the last three rows is one no `Int` can be, so a program that
checks the exit code gets an answer that means nothing, and arithmetic on it
yields a string. A program cannot tell a timeout from a signal, or either from
too much output, except by inspecting a value its type says is a number.

The cause is in `Gren/Kernel/ChildProcess.js`, where `execFile`'s error becomes
the `ProgramError`:

```js
__$exitCode: err.code,
```

Node's `err.code` is the exit code only when the process exited. After a
timeout or a signal it is `null`, and `err.killed` and `err.signal` say what
happened. When the output passed `maxBuffer` it is the error's own code, the
string `ERR_CHILD_PROCESS_STDIO_MAXBUFFER`.

## Reproduction

```
$ node app
exit 3: ProgramError, exitCode = 3, exitCode + 1 = 4, exitCode > 0 = True
killed by runDuration: ProgramError, exitCode = null, exitCode + 1 = 1, exitCode > 0 = False
past maximumBytesWrittenToStreams: ProgramError, exitCode = ERR_CHILD_PROCESS_STDIO_MAXBUFFER, exitCode + 1 = ERR_CHILD_PROCESS_STDIO_MAXBUFFER1, exitCode > 0 = False
killed by a signal: ProgramError, exitCode = null, exitCode + 1 = 1, exitCode > 0 = False
```

## The fix

The smallest fix keeps the type and gives a number every time:

```js
__$exitCode: typeof err.code === "number" ? err.code : -1,
```

`-1` is what `ChildProcess.spawn` already reports, through its exit message,
for a process that has no exit code to give. That still leaves the three cases
indistinguishable from each other. Telling them apart needs another
`FailedRun` variant, or a field that carries `err.signal` and whether the limit
on output was reached, which is an API change for the maintainers to choose.
