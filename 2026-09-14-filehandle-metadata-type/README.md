# `FileHandle.metadata` is annotated to answer a file handle, and answers the `Metadata`

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`FileSystem.FileHandle.metadata` is annotated

```gren
metadata : ReadableFileHandle a -> Task FileSystem.Error (ReadableFileHandle FileSystem.Metadata)
```

and its kernel code, `_FileSystem_fstat`, succeeds with the `Metadata` record
itself. So the annotation and the value disagree, in both directions:

| use of `metadata`'s result | type-checks | runs |
|---|---|---|
| read a field, `m.byteSize` | **no**: the type is a file handle, which has no fields | would work |
| pass it to `FileHandle.read` | **yes**: the type is a readable handle | **crashes**, `The "fd" argument must be of type number. Received undefined` |

The one thing `metadata` is for, reading the metadata, cannot be written, and
what the compiler accepts crashes. The crash happens inside `fs.read`'s
callback machinery, so the program dies rather than failing the task.

## Reproduction

`Main` opens `gren.json`, asks for its metadata, and passes the result to
`FileHandle.read`, which the annotation allows.

```
$ node app
node:internal/errors:540
      throw error;
      ^

TypeError [ERR_INVALID_ARG_TYPE]: The "fd" argument must be of type number. Received undefined
    at Object.read (node:fs:604:8)
    at _FileSystem_readHelper (…/app:3260:6)
```

## The fix

The annotation, since the kernel returns what `FileSystem.metadata` returns for
a path:

```gren
metadata : ReadableFileHandle a -> Task FileSystem.Error FileSystem.Metadata
```
