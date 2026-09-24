# `ChildProcess.run` puts `null` or a string into `exitCode : Int` after a timeout, a signal or too much output

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

`ChildProcess.run` fails with `ProgramError { exitCode : Int, … }` when the
program did not succeed. When the program was stopped by `runDuration` or a
signal, or wrote more than `maximumBytesWrittenToStreams`, `exitCode` is `null`
or the string `"ERR_CHILD_PROCESS_STDIO_MAXBUFFER"`, so `String.fromInt`,
arithmetic and comparisons on it give nonsense (`exitCode + 1` is a string
concatenation), and a program cannot tell a timeout from a signal from too much
output.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren`. Build and run with `gren make Main --output=app && node app`:

```gren
module Main exposing (main)

import ChildProcess exposing (FailedRun(..))
import Init
import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Init.await ChildProcess.initialize <| \cp ->
            let
                defaults =
                    ChildProcess.defaultRunOptions

                options =
                    { defaults | shell = ChildProcess.NoShell }

                row label program arguments opts =
                    ChildProcess.run cp program arguments opts
                        |> Task.map (\_ -> "succeeded | | ")
                        |> Task.onError
                            (\failure ->
                                when failure is
                                    ProgramError e ->
                                        Task.succeed
                                            (String.fromInt e.exitCode
                                                ++ " | "
                                                ++ String.fromInt (e.exitCode + 1)
                                                ++ " | "
                                                ++ (if e.exitCode > 0 then "True" else "False")
                                            )

                                    InitError e ->
                                        Task.succeed ("InitError " ++ e.errorCode ++ " | | ")
                            )
                        |> Task.andThen (\cells -> print ("| " ++ label ++ " | " ++ cells ++ " |"))

                print line =
                    Stream.writeLineAsBytes line env.stdout
                        |> Task.onError (\_ -> Task.succeed env.stdout)
            in
            Node.endSimpleProgram
                (print "| run | exitCode | exitCode + 1 | exitCode > 0 |\n|---|---|---|---|"
                    |> Task.andThen (\_ -> row "`sh -c \"exit 3\"`" "sh" [ "-c", "exit 3" ] options)
                    |> Task.andThen (\_ -> row "`sleep 5`, `runDuration = Milliseconds 100`" "sleep" [ "5" ] { options | runDuration = ChildProcess.Milliseconds 100 })
                    |> Task.andThen (\_ -> row "`echo \"more than four bytes\"`, `maximumBytesWrittenToStreams = 4`" "echo" [ "more than four bytes" ] { options | maximumBytesWrittenToStreams = 4 })
                    |> Task.andThen (\_ -> row "`sh -c \"kill -9 $$\"`" "sh" [ "-c", "kill -9 $$" ] options)
                )
```

Output:

```
$ node app
| run | exitCode | exitCode + 1 | exitCode > 0 |
|---|---|---|---|
| `sh -c "exit 3"` | 3 | 4 | True |
| `sleep 5`, `runDuration = Milliseconds 100` | null | 1 | False |
| `echo "more than four bytes"`, `maximumBytesWrittenToStreams = 4` | ERR_CHILD_PROCESS_STDIO_MAXBUFFER | ERR_CHILD_PROCESS_STDIO_MAXBUFFER1 | False |
| `sh -c "kill -9 $$"` | null | 1 | False |
```

## Cause

`Gren/Kernel/ChildProcess.js`, where `execFile`'s error becomes the
`ProgramError`:

```js
__$exitCode: err.code,
```

Node's `err.code` is the exit code only when the process exited. After a
timeout or a signal it is `null` (and `err.killed` / `err.signal` say what
happened). When the output passed `maxBuffer` it is the error's own code, the
string `ERR_CHILD_PROCESS_STDIO_MAXBUFFER`.

## Fix

The smallest fix keeps the type and always gives a number:

```js
__$exitCode: typeof err.code === "number" ? err.code : -1,
```

`-1` is what `ChildProcess.spawn` already reports, through `onExit`, for a
process with no exit code. That still leaves the three cases indistinguishable;
telling them apart needs another `FailedRun` variant or a field carrying
`err.signal` and whether the output limit was hit, which is an API choice.
