# `Bytes.flatten` reads each input from offset 0 of its backing buffer

`_Bytes_flatten` copies the right *number* of bytes from the wrong *place*:

```js
// gren-lang/core/src/Gren/Kernel/Bytes.js
function _Bytes_flatten(arrayOfBytes) {
  var requiredSize = 0;
  for (var i = 0; i < arrayOfBytes.length; i++) {
    requiredSize += arrayOfBytes[i].byteLength;      // length: correct
  }

  var offset = 0;
  var result = new Uint8Array(requiredSize);

  for (var i = 0; i < arrayOfBytes.length; i++) {
    var currentBytes = new Uint8Array(arrayOfBytes[i].buffer);   // byteOffset dropped
    var currentByteLength = arrayOfBytes[i].byteLength;

    for (var j = 0; j < currentByteLength; j++) {
      result[offset] = currentBytes[j];              // reads from index 0 of the buffer
      offset++;
    }
  }

  return new DataView(result.buffer);
}
```

A `Bytes` is a `DataView`: a window onto an `ArrayBuffer`, described by
`byteOffset` and `byteLength`. `new Uint8Array(view.buffer)` throws the window
away and starts at index 0 of the whole buffer. `requiredSize` and the inner
loop bound both use `byteLength`, so the result is exactly as long as it should
be — and filled with whatever precedes the data.

That combination is what makes it worth reporting: the value that comes back has
the right type and the right length, and nothing about it looks wrong.

- **Package:** `gren-lang/core` (`Bytes` kernel)
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, gren-lang/node 6.1.3, Node.js
  v25.1.0, Linux x86-64

## Reproducing

```sh
./run.sh
```

No ports, no sockets, no files. `src/Flatten.gren` gets a view-backed `Bytes`
from `ChildProcess.run`, which hands back the child's stdout as a `DataView`
preserving `byteOffset`, and Node serves small allocations out of a shared 8 KiB
pool — so the offset is almost never zero. (`\0` below is a NUL byte, escaped by
the program so the output survives a terminal.)

```
a view from ChildProcess.run (byteOffset is almost never 0)
  input           length=11 text="HELLO-WORLD"
  flatten [it]    length=11 text="/\0\0\0\0\0\0\0HEL"

two views concatenated
  inputs          length=23 text="HELLO-WORLDSECOND-CHUNK"
  flatten [a, b]  length=23 text="/\0\0\0\0\0\0\0HEL/\0\0\0\0\0\0\0HELL"

the control: Bytes.fromString owns its buffer outright
  input           length=11 text="HELLO-WORLD"
  flatten [it]    length=11 text="HELLO-WORLD"
```

Read the first line: the child's stdout sits at `byteOffset` 8, so the copy
takes 8 bytes of unrelated pool contents followed by the first 3 bytes of the
actual data (`HEL`), and stops — 11 bytes, as promised, of which 3 are ours.

The second block is worse than it looks. Both children's output is in the same
pool at different offsets, and *both* reads start at index 0, so the second
chunk contributes the first chunk's neighbourhood rather than its own bytes:
one child's data appears where another's was asked for.

`run.sh` also prints the same thing in plain node, without Gren in the way:

```
child stdout : byteLength 11  byteOffset 8  buffer.byteLength 8192
what flatten reads  : "/\u0000\u0000\u0000\u0000\u0000\u0000\u0000HEL"
what it should read : "HELLO-WORLD"
```

## Why it is easy to miss

Every obvious way to *construct* a `Bytes` in a test produces a buffer the value
owns outright, at offset 0, where the bug cannot show:

- `Bytes.fromString` — `TextEncoder.encode` returns an exact-width array;
- `Bytes.Encode.encode` — allocates `new ArrayBuffer(getLength(encoder))`;
- `Bytes.flatten` itself — returns `new DataView(result.buffer)`.

Views arrive from the *outside*: `ChildProcess.run` stdout/stderr, `HttpServer`
request bodies, `FileSystem` reads through `Buffer.allocUnsafe`. So `flatten` is
correct on everything a unit test is likely to hand it, and wrong on most things
a running program will.

## The fix

Give the `Uint8Array` the window it was given:

```js
var currentBytes = new Uint8Array(
  arrayOfBytes[i].buffer,
  arrayOfBytes[i].byteOffset,
  arrayOfBytes[i].byteLength,
);
```

The inner copy loop then works unchanged. `result.set(currentBytes, offset)`
would replace the loop entirely and be faster, if you want it.

`gren-lang/node`'s `HttpServer` kernel already spells the three-argument form out
in `_HttpServer_setBodyAsBytes`, so the convention exists; it is just not applied
here.

## Impact

Silent data corruption in anything that concatenates bytes that came from
outside the program — joining a response read in chunks, assembling a file from
reads, building a payload out of a child process's output. The length checks
out, so the corruption surfaces later and somewhere else: a failed signature
verification, a parse error, a truncated image.

There is a confidentiality edge too. The bytes substituted in are the rest of a
shared pool, which in a process handling more than one thing at a time can hold
another request's or another child's data. A program can hand out bytes it never
received.

## Related

The sibling report in `2026-08-16-withBytesBody/` is the same mistake —
`new Uint8Array(view.buffer)`, with the offset dropped — in `gren-lang/node`'s
`HttpClient` kernel. It behaves differently there: the length is taken from the
buffer too, so a small request body goes out as the whole 8 KiB pool rather than
as the right number of wrong bytes. The two are independent fixes in different
packages. I found this one while checking whether `Bytes.flatten` would make a
safe workaround for that one; it would not.
