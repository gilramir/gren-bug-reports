# `FileSystem.Lock.aquire` ends in `UnexpectedError ENOENT` when the lock is released while it checks it

**Repository:** `gren-lang/compiler-node`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-node` 5.0.0, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

Taking a lock that another process holds only briefly often ends in
`UnexpectedError`, when it should end with the lock taken or `AlreadyLocked`.
`aquire` creates the lock directory; if it exists, it reads its metadata to see
whether the lock is stale. If the other process removes the lock in between,
`metadata` fails with `ENOENT`, and the handler that means to retry tests for
the wrong error.

## Reproduction

`./run.sh` does all of this, using the `gren` and `node` that devbox pins.

`gren.json`: a node application with `"gren-lang/compiler-node": "5.0.0", "gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3"` (indirect `"gren-lang/compiler-common": "3.0.0", "gren-lang/url": "6.0.0"`).

`churn.js` stands in for another process that holds the lock very briefly:

```js
// Create and remove ./.lock in a tight loop, as another process holding the
// lock very briefly would.
const fs = require("node:fs");
for (;;) {
  try { fs.mkdirSync(".lock"); } catch (e) {}
  try { fs.rmdirSync(".lock"); } catch (e) {}
}
```

`src/Main.gren` tries to take the lock 2000 times, without retries, releasing it
whenever it gets it, and counts how each attempt ended:

```gren
module Main exposing (main)

{-| Try to take `.lock` 2000 times, without retries, while `churn.js` creates
and removes the same directory as fast as it can. Every attempt should end with
the lock taken or already locked; count how each one ended.
-}

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import FileSystem
import FileSystem.Lock as Lock
import FileSystem.Path as Path exposing (Path)
import Init
import Node
import Process
import Stream
import Task


main : Node.Program Model Msg
main =
    Node.defineProgram
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        }


attempts : Int
attempts =
    2000


type alias Model =
    { fsPerm : FileSystem.Permission
    , stdout : Stream.Writable Bytes
    , locks : Lock.Model
    , left : Int
    , outcomes : Dict String Int
    }


type Msg
    = LockMsg Lock.Msg
    | Next


lockPath : Path
lockPath =
    Path.empty


init : Node.Environment -> Init.Task { model : Model, command : Cmd Msg }
init env =
    Init.await FileSystem.initialize <| \fsPerm ->
        Node.startProgram
            { model =
                { fsPerm = fsPerm
                , stdout = env.stdout
                , locks = Lock.init Nothing
                , left = attempts
                , outcomes = Dict.empty
                }
            , command = Cmd.map LockMsg (Lock.aquire lockPath)
            }


update : Msg -> Model -> { model : Model, command : Cmd Msg }
update msg model =
    when msg is
        LockMsg lockMsg ->
            when Lock.update model.fsPerm lockMsg model.locks is
                Lock.Working cmd ->
                    { model = model, command = Cmd.map LockMsg cmd }

                Lock.LockAquired { model = locks } ->
                    -- Release it again straight away; the heartbeat is not needed.
                    { model = count "lock acquired" { model | locks = locks }
                    , command = Cmd.map LockMsg (Lock.release lockPath)
                    }

                Lock.LockReleased { model = locks, command } ->
                    { model = { model | locks = locks }
                    , command = Cmd.batch [ Cmd.map LockMsg command, next ]
                    }

                Lock.AlreadyLocked _ ->
                    { model = count "already locked" model, command = next }

                Lock.UnexpectedError { error } ->
                    { model = count ("UnexpectedError " ++ FileSystem.errorCode error) model
                    , command = next
                    }

        Next ->
            if model.left > 0 then
                { model = model, command = Cmd.map LockMsg (Lock.aquire lockPath) }

            else
                { model = model, command = report model }


count : String -> Model -> Model
count outcome model =
    { model
        | left = model.left - 1
        , outcomes = Dict.update outcome (\n -> Just (Maybe.withDefault 0 n + 1)) model.outcomes
    }


next : Cmd Msg
next =
    Process.sleep 1
        |> Task.perform (\_ -> Next)


report : Model -> Cmd Msg
report model =
    let
        row outcome n =
            String.padRight 28 ' ' outcome ++ String.padLeft 6 ' ' (String.fromInt n)
    in
    Dict.foldl (\outcome n rows -> Array.pushLast (row outcome n) rows) [ "outcome                      count" ] model.outcomes
        |> String.join "\n"
        |> (\text -> Stream.writeLineAsBytes text model.stdout)
        |> Task.map (\_ -> Node.exit)
        |> Task.onError (\_ -> Task.succeed Node.exit)
        |> Task.executeCmd
```

```sh
gren make Main --output=app
node churn.js &
node app
```

Output (counts vary with timing):

```
outcome                      count
UnexpectedError ENOENT         953
already locked                 156
lock acquired                  891
```

## Cause

```gren
LockMetaCheck { path, attempt, result = Err fsErr } ->
    if FileSystem.errorIsFileExists fsErr then
        -- Lock might have been removed while we asked for metadata
        update fsPerm (Lock { path = fromLockPath path, attempt = attempt + 1 }) model

    else
        UnexpectedError { path = fromLockPath path, error = fsErr }
```

The comment describes the right recovery, but reading a directory's metadata
never fails with `EEXIST`, so a lock that has been removed takes the `else`
branch.

## Fix

```gren
if FileSystem.errorIsNoSuchFileOrDirectory fsErr then
```

With it, the same program gave 325 `already locked` and 1675 `lock acquired`.
