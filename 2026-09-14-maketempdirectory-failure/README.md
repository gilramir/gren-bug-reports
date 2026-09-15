# `FileSystem.makeTempDirectory` crashes the program when it fails, instead of failing the task

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`FileSystem.makeTempDirectory` is a `Task FileSystem.Error Path`. When node
cannot make the directory, the program dies instead of the task failing:

| call | result | expected |
|---|---|---|
| `makeTempDirectory fs "no-such-directory/x"`, where the directory under the system's temporary directory does not exist | **the program crashes**: `The "path" argument must be of type string. Received undefined` | the task fails with an `Error` whose code is `ENOENT` |

The cause is in `Gren/Kernel/FileSystem.js`:

```js
fs.mkdtemp(path.join(os.tmpdir(), prefix), function (err, dir) {
  if (err) {
    callback(
      __Scheduler_fail(
        _FileSystem_constructError(__FilePath_fromString(dir), err),
      ),
    );
```

On failure node's callback has no directory, so `dir` is `undefined`, and
`_FilePath_fromString(undefined)` calls `path.normalize(undefined)`, which
throws. It throws inside node's callback, so nothing catches it.

Any failure reaches it: a missing parent directory, a prefix naming a directory
the user cannot write, or a temporary directory that is full.

## Reproduction

```
$ node app
making a temporary directory under a prefix that does not exist
node:internal/errors:540
      throw error;
      ^

TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received undefined
    at Object.normalize (node:path:1309:5)
    at _FilePath_parse (…/app:2889:40)
    at _FilePath_fromString (…/app:2885:10)
```

The second line is the program's own output, so the crash is in
`makeTempDirectory`, and the program's error handling never runs.

## The fix

Name the error by the template the directory was to be made from, which is the
path the operation was about:

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
