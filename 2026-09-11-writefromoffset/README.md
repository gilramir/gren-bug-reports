# `FileSystem.FileHandle.writeFromOffset` ignores its offset and writes at position 0

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

`./run.sh` prints the figure below.

## Summary

`writeFromOffset` takes the offset as a plain `Int`:

```gren
{-| Write bytes into a specific location of a file.
-}
writeFromOffset : WriteableFileHandle a -> Int -> Bytes -> Task FileSystem.Error (WriteableFileHandle a)
writeFromOffset =
    Gren.Kernel.FileSystem.writeFromOffset
```

The kernel function behind it reads that argument as a **record**:

```js
var _FileSystem_writeFromOffset = F3(function (fh, options, bytes) {
  return __Scheduler_binding(function (callback) {
    _FileSystem_writeHelper(
      fh,
      bytes,
      0,
      bytes.byteLength,
      options.__$offset,
      callback,
    );
  });
});
```

`options` is a number, so `options.__$offset` is `undefined`. That is passed to
`fs.write` as its `position`, where `undefined` means "the file's current
position" — which for a freshly opened handle is 0.

So the offset argument has no effect at all. Every `writeFromOffset` writes
where `write` would have written, and nothing reports anything.

`readFromOffset` beside it does take a record, `{ offset, length }`, and is
correct. The kernel function for the write looks like a copy of the read's that
kept the record access after the Gren signature stopped passing one.

## Reproduction

Write ten `A`s, open the file for writing, put two `Z`s at offset 5, read it
back:

```gren
FileSystem.writeFile fsPermission (Bytes.fromString "AAAAAAAAAA") path
    |> Task.andThen
        (\_ -> FileHandle.openForWrite fsPermission FileHandle.ExpectExisting path)
    |> Task.andThen
        (\fh ->
            FileHandle.writeFromOffset fh 5 (Bytes.fromString "ZZ")
                |> Task.andThen (\_ -> FileHandle.close fh)
        )
    |> Task.andThen (\_ -> FileSystem.readFile fsPermission path)
```

```
wrote "ZZ" at offset 5 into "AAAAAAAAAA"
  expected  AAAAAZZAAA
  got       ZZAAAAAAAA
```

## Fix

Use the argument as the offset it is:

```js
var _FileSystem_writeFromOffset = F3(function (fh, offset, bytes) {
  return __Scheduler_binding(function (callback) {
    _FileSystem_writeHelper(fh, bytes, 0, bytes.byteLength, offset, callback);
  });
});
```

`write` is defined as `writeFromOffset fh 0 bytes`, so it is unaffected either
way: 0 and `undefined` both put the write at the start of a newly opened handle.
That is why the defect survives — the common path is the one case where the two
readings agree.
