# `ChildProcess.spawn` with `NoShell` looks for a program named after the program and its arguments

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

`ChildProcess.spawn` with `shell = NoShell` works for a program with no
arguments and fails for any program given arguments: `spawn cp "test" [ "1",
"-eq", "1" ]` asks node for a program named `test 1 -eq 1`, which does not
exist. The same call with `DefaultShell` works. (That the failure crashes the
program instead of reaching `onExit` is a separate bug, reported separately.)

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren`. Build and run with `gren make Main --output=app && node app`:

```gren
module Main exposing (main)

import Bytes exposing (Bytes)
import ChildProcess exposing (Shell(..))
import Init
import Node
import Stream
import Task


rows : Array { label : String, shell : Shell, program : String, arguments : Array String }
rows =
    [ { label = "`DefaultShell`, `test 1 -eq 1`", shell = DefaultShell, program = "test", arguments = [ "1", "-eq", "1" ] }
    , { label = "`NoShell`, `true`", shell = NoShell, program = "true", arguments = [] }
    , { label = "`NoShell`, `test 1 -eq 1`", shell = NoShell, program = "test", arguments = [ "1", "-eq", "1" ] }
    ]


type Msg
    = Spawn Int
    | Exited { row : Int, code : Int }
    | Started


type alias Model =
    { cp : ChildProcess.Permission, stdout : Stream.Writable Bytes }


main : Node.Program Model Msg
main =
    Node.defineProgram { init = init, update = update, subscriptions = \_ -> Sub.none }


init : Node.Environment -> Init.Task { model : Model, command : Cmd Msg }
init env =
    Init.await ChildProcess.initialize <| \cp ->
        Node.startProgram
            { model = { cp = cp, stdout = env.stdout }
            , command = print env.stdout "| spawn | exit code | expected |\n|---|---|---|" (Spawn 0)
            }


print : Stream.Writable Bytes -> String -> Msg -> Cmd Msg
print stdout line next =
    Stream.writeLineAsBytes line stdout |> Task.attempt (\_ -> next)


update : Msg -> Model -> { model : Model, command : Cmd Msg }
update msg model =
    when msg is
        Spawn i ->
            { model = model
            , command =
                when Array.get i rows is
                    Just r ->
                        ChildProcess.spawn model.cp r.program r.arguments
                            { shell = r.shell
                            , workingDirectory = ChildProcess.InheritWorkingDirectory
                            , environmentVariables = ChildProcess.InheritEnvironmentVariables
                            , runDuration = ChildProcess.NoLimit
                            , connection = ChildProcess.Ignored (\_ -> Started)
                            , onExit = \code -> Exited { row = i, code = code }
                            }

                    Nothing ->
                        Cmd.none
            }

        Exited { row = i, code } ->
            { model = model
            , command =
                when Array.get i rows is
                    Just r ->
                        print model.stdout ("| " ++ r.label ++ " | " ++ String.fromInt code ++ " | 0 |") (Spawn (i + 1))

                    Nothing ->
                        Cmd.none
            }

        Started ->
            { model = model, command = Cmd.none }
```

Output:

```
$ node app
| spawn | exit code | expected |
|---|---|---|
| `DefaultShell`, `test 1 -eq 1` | 0 | 0 |
| `NoShell`, `true` | 0 | 0 |
node:events:497
      throw er; // Unhandled 'error' event
      ^

Error: spawn test 1 -eq 1 ENOENT
    at ChildProcess._handle.onexit (node:internal/child_process:285:19)
    at onErrorNT (node:internal/child_process:483:16)
    at process.processTicksAndRejections (node:internal/process/task_queues:89:21)
Emitted 'error' event on ChildProcess instance at:
    at ChildProcess._handle.onexit (node:internal/child_process:291:12)
    at onErrorNT (node:internal/child_process:483:16)
    at process.processTicksAndRejections (node:internal/process/task_queues:89:21) {
  errno: -2,
  code: 'ENOENT',
  syscall: 'spawn test 1 -eq 1',
  path: 'test 1 -eq 1',
  spawnargs: []
}

Node.js v22.23.2
```

## Cause

`Gren/Kernel/ChildProcess.js`. Since 6833e85 ("Fix deprecation warning when
spawning child processes") the program and its arguments are joined into one
string whatever the shell option is:

```js
var cmd = [options.__$program].concat(options.__$arguments).join(" ");

var subproc = childProcess.spawn(cmd, {
  // ...
  shell: _ChildProcess_handleShell(shell),
```

A shell splits that string again; without one, node treats the whole string as
the file to run.

## Fix

Join only when there is a shell to split the string again:

```js
var shellOption = _ChildProcess_handleShell(shell);

var subproc = shellOption
  ? childProcess.spawn(
      [options.__$program].concat(options.__$arguments).join(" "),
      { /* options, with shell: shellOption */ },
    )
  : childProcess.spawn(options.__$program, options.__$arguments, {
      /* options, with shell: false */
    });
```
