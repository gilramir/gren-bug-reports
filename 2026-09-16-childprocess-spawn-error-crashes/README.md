# `ChildProcess.spawn` crashes the program when the program to spawn cannot be started

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

A `ChildProcess.spawn` with `NoShell` whose program cannot be started (it does
not exist, or is not executable) ends the whole Gren program with node's
`Unhandled 'error' event`. Neither `onExit` nor the connection message arrives,
so the application cannot handle the failure. With `DefaultShell` the shell
starts, fails to find the program and exits 127, which `onExit` receives.

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
    [ { label = "`DefaultShell`, `no-such-program`", shell = DefaultShell, program = "no-such-program", arguments = [] }
    , { label = "`NoShell`, `no-such-program`", shell = NoShell, program = "no-such-program", arguments = [] }
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
                        print model.stdout ("| " ++ r.label ++ " | " ++ String.fromInt code ++ " | non-zero |") (Spawn (i + 1))

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
| `DefaultShell`, `no-such-program` | 127 | non-zero |
node:events:497
      throw er; // Unhandled 'error' event
      ^

Error: spawn no-such-program ENOENT
    at ChildProcess._handle.onexit (node:internal/child_process:285:19)
    at onErrorNT (node:internal/child_process:483:16)
    at process.processTicksAndRejections (node:internal/process/task_queues:89:21)
Emitted 'error' event on ChildProcess instance at:
    at ChildProcess._handle.onexit (node:internal/child_process:291:12)
    at onErrorNT (node:internal/child_process:483:16)
    at process.processTicksAndRejections (node:internal/process/task_queues:89:21) {
  errno: -2,
  code: 'ENOENT',
  syscall: 'spawn no-such-program',
  path: 'no-such-program',
  spawnargs: []
}

Node.js v22.23.2
```

## Cause

Node reports a failed spawn asynchronously, as an `error` event on the
`ChildProcess`, and `Gren/Kernel/ChildProcess.js` installs no listener for it;
an `error` event with no listener throws. The kernel handles only a spawn that
throws synchronously, by sending `onExit` the error's `errno`:

```js
} catch (e) {
  callback(
    __Scheduler_succeed(
      __Scheduler_rawSpawn(
        sendExitToApp(typeof e.errno === "undefined" ? -1 : e.errno),
      ),
    ),
  );
```

## Fix

Listen for the event and report it the same way:

```js
subproc.on("error", function (e) {
  __Scheduler_rawSpawn(
    sendExitToApp(typeof e.errno === "undefined" ? -1 : e.errno),
  );
});
```

If the process never started, no `exit` follows the `error`, so `onExit` is sent
once. An `error` after the process has started (such as a failed `kill`) can be
followed by `exit`, so a complete fix sends `onExit` for an `error` only if no
`exit` has arrived.
