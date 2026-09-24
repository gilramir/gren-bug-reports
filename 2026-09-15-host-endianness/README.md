# `Bytes.getHostEndianness` answers `LE` on big-endian hosts too

**Repository:** `gren-lang/core`
**Found against:** `gren-lang/core` 7.4.2, node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-15-host-endianness
**Filed:** not yet.

A program that picks a byte order with `Bytes.getHostEndianness`, for example to
read a native-endian file or buffer, gets `LE` on every host. On a big-endian
host that is wrong, and the program decodes its data with the wrong byte order.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Bytes
import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Node.endSimpleProgram
            (Bytes.getHostEndianness
                |> Task.andThen
                    (\endianness ->
                        when endianness is
                            Bytes.LE ->
                                Stream.writeLineAsBytes "getHostEndianness: LE" env.stdout

                            Bytes.BE ->
                                Stream.writeLineAsBytes "getHostEndianness: BE" env.stdout
                    )
                |> Task.map (\_ -> {})
                |> Task.onError (\_ -> Task.succeed {})
            )
```

Output on this machine (x86-64, little-endian), which is correct:

```
getHostEndianness: LE
```

On a big-endian host it prints the same line, where it should print
`getHostEndianness: BE`. No big-endian host was available to run it on; that
follows from the kernel code below.

## Cause

`_Bytes_getHostEndianness` in `src/Gren/Kernel/Bytes.js` tests:

```js
new Uint8Array(new Uint32Array([1]))[0] === 1 ? le : be
```

Constructing a `Uint8Array` from another typed array copies its *elements*,
converting each value (ECMAScript `InitializeTypedArrayFromTypedArray`); it does
not look at memory. The one element is 1, and 1 as a byte is 1, so the test is
true on every host. In node on this machine:

```
> new Uint8Array(new Uint32Array([0x11223344]))
Uint8Array(1) [ 68 ]
> new Uint8Array(new Uint32Array([0x11223344]).buffer)
Uint8Array(4) [ 68, 51, 34, 17 ]
```

The first is one element, `0x44`, the value's low byte: no byte order was read.
The second is a view of the same memory and does read the host's order (`44 33
22 11` here, `11 22 33 44` on a big-endian host).

## Fix

```js
new Uint8Array(new Uint32Array([1]).buffer)[0] === 1 ? le : be
```

`elm/bytes` has the same line.
