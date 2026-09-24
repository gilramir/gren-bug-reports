# `FileSystem.makeTempDirectory` crashes the program when it fails, instead of failing the task

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

`FileSystem.makeTempDirectory` is a `Task FileSystem.Error Path`, but when node
cannot make the directory the program dies with `The "path" argument must be of
type string. Received undefined` and the program's `Task.onError` never runs.
Expected: the task fails with an `Error` whose code is `ENOENT`. Any failure
reaches it: a missing parent directory, a prefix naming a directory the user
cannot write, or a full temporary directory.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren`. Build and run with `gren make Main --output=app && node app`:

```gren
module Main exposing (main)

import FileSystem
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
                (FileSystem.makeTempDirectory fs "no-such-directory/x"
                    |> Task.map (\path -> "made " ++ Path.toPosixString path)
                    |> Task.onError (\e -> Task.succeed ("failed: " ++ FileSystem.errorCode e))
                    |> Task.andThen (\line -> Stream.writeLineAsBytes line env.stdout)
                    |> Task.onError (\_ -> Task.succeed env.stdout)
                )
```

Output:

```
$ node app
node:internal/errors:540
      throw error;
      ^

TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received undefined
    at Object.normalize (node:path:1309:5)
    at _FilePath_parse (/path/to/app:2889:40)
    at _FilePath_fromString (/path/to/app:2885:10)
    at /path/to/app:3664:40
    at FSReqCallback.oncomplete (node:fs:186:23) {
  code: 'ERR_INVALID_ARG_TYPE'
}

Node.js v22.23.2
```

## Cause

`Gren/Kernel/FileSystem.js`:

```js
fs.mkdtemp(path.join(os.tmpdir(), prefix), function (err, dir) {
  if (err) {
    callback(
      __Scheduler_fail(
        _FileSystem_constructError(__FilePath_fromString(dir), err),
      ),
    );
```

On failure `dir` is `undefined`, and `__FilePath_fromString(undefined)` calls
`path.normalize(undefined)`, which throws inside node's callback, where nothing
catches it.

## Fix

Name the error by the template the directory was to be made from:

```js
var template = path.join(os.tmpdir(), prefix);
fs.mkdtemp(template, function (err, dir) {
  if (err) {
    callback(
      __Scheduler_fail(
        _FileSystem_constructError(__FilePath_fromString(template), err),
      ),
    );
```

With this change the program above prints `failed: ENOENT`.
