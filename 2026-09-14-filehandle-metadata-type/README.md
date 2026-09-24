# `FileHandle.metadata` is annotated to return a file handle, but returns the `Metadata`

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

`FileSystem.FileHandle.metadata` is annotated

```gren
metadata : ReadableFileHandle a -> Task FileSystem.Error (ReadableFileHandle FileSystem.Metadata)
```

but its kernel code, `_FileSystem_fstat`, succeeds with the `Metadata` record
itself. So reading a field of the result, the one thing `metadata` is for, does
not compile, and passing the result to `FileHandle.read`, which does compile,
crashes the program instead of failing the task.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren`, which reads the size of `gren.json` through a file handle. Build with `gren make Main --output=app`:

```gren
module Main exposing (main)

import FileSystem
import FileSystem.FileHandle as FileHandle
import FileSystem.Path as Path
import Init
import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Init.await FileSystem.initialize <| \fs ->
            Node.endSimpleProgram
                (FileHandle.openForRead fs (Path.fromPosixString "gren.json")
                    |> Task.andThen FileHandle.metadata
                    |> Task.map (\m -> "byteSize = " ++ String.fromInt m.byteSize)
                    |> Task.onError (\e -> Task.succeed (FileSystem.errorToString e))
                    |> Task.andThen (\line -> Stream.writeLineAsBytes line env.stdout)
                    |> Task.onError (\_ -> Task.succeed env.stdout)
                )
```

Output:

```
$ gren make Main --output=app
Compiling ...-- TYPE MISMATCH ------------------------------------------------- src/Main.gren

This function cannot handle the argument sent through the (|>) pipe:

17|                 (FileHandle.openForRead fs (Path.fromPosixString "gren.json")
18|                     |> Task.andThen FileHandle.metadata
19|                     |> Task.map (\m -> "byteSize = " ++ String.fromInt m.byteSize)
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
The argument is:

    Task.Task
        FileSystem.Error
        (FileHandle.ReadableFileHandle FileSystem.Metadata)

But (|>) is piping it to a function that expects:

    Task.Task FileSystem.Error { a | byteSize : Int }

Detected problems in 1 module.
```

`src/ReadFromMetadata.gren` is the same program with `Task.map (\m -> ...)`
replaced by what the annotation allows:

```gren
                    |> Task.andThen FileHandle.read
                    |> Task.map (\_ -> "read from the metadata")
```

It compiles, and crashes:

```
$ gren make ReadFromMetadata --output=app && node app
node:internal/errors:540
      throw error;
      ^

TypeError [ERR_INVALID_ARG_TYPE]: The "fd" argument must be of type number. Received undefined
    at Object.read (node:fs:604:8)
    at _FileSystem_readHelper (/path/to/app:3260:6)
    at Object.b (/path/to/app:3239:5)
    at _Scheduler_step (/path/to/app:298:25)
    at _Scheduler_enqueue (/path/to/app:279:7)
    at /path/to/app:300:9
    at /path/to/app:3484:9
    at FSReqCallback.oncomplete (node:fs:197:5) {
  code: 'ERR_INVALID_ARG_TYPE'
}

Node.js v22.23.2
```

## Fix

The annotation, since the kernel returns what `FileSystem.metadata` returns for
a path:

```gren
metadata : ReadableFileHandle a -> Task FileSystem.Error FileSystem.Metadata
```
