# A `Bytes` value crossing a port carries its whole backing buffer, not the bytes it holds

`gren` 0.6.6, `gren-lang/core` 7.4.2, node 22, Linux x86-64.

## Summary

A program decodes a message's body with `Bytes.Decode.bytes` and sends it to
the host through a port. The host receives the whole message, not the body.
In the other direction, a host that sends a Node `Buffer` into a port gives the
program 8192 bytes instead of what the `Buffer` held:

| direction | port | received | expected |
|---|---|---|---|
| program → host | `toHost body` | **5 bytes `[0, 0, 7, 8, 9]`** | 3 bytes `[7, 8, 9]` |
| program → host | `roundTrip body` (task port input) | **5 bytes `[0, 0, 7, 8, 9]`** | 3 bytes `[7, 8, 9]` |
| host → program | `flags`: a view of `[4, 5]` | **10 bytes `[0, 1, 2, 3, 4, ...]`** | 2 bytes `[4, 5]` |
| host → program | `roundTrip` result: a view of `[4, 5]` | **10 bytes `[0, 1, 2, 3, 4, ...]`** | 2 bytes `[4, 5]` |
| host → program | `fromHost`: a view of `[4, 5]` | **10 bytes `[0, 1, 2, 3, 4, ...]`** | 2 bytes `[4, 5]` |
| host → program | `fromHost`: `Buffer.from([4, 5])` | **8192 bytes `[47, 0, 0, 0, 0, ...]`** | 2 bytes `[4, 5]` |

`body` is `Bytes.Decode.bytes 3` after `Bytes.Decode.bytes 2` over
`[0, 0, 7, 8, 9]`, and `Bytes.length body` is `3`. Inside the program it is
three bytes; it stops being three bytes when it crosses a port.

A `Bytes` value is a `DataView`, and a `DataView` is a window onto an
`ArrayBuffer`: `byteOffset` and `byteLength` are part of the value.
`Bytes.Decode.bytes` returns such a window (`_Bytes_read_bytes`), and so does
any host code built on a Node `Buffer`, since Node allocates small `Buffer`s
out of a shared 8 KiB pool. `Platform.js` copies a port's bytes five times, and
each copy is of the whole backing buffer:

```js
flags = new DataView(rawFlags.buffer.slice());                  // flags
  ? new DataView(rawValue.buffer.slice())                       // outgoing port
value = new DataView(incomingValue.buffer.slice());             // incoming port
  ? new DataView(input.buffer.slice())                          // task port input
checkedValue = new DataView(value.buffer.slice());              // task port result
```

`ArrayBuffer.prototype.slice()` with no arguments copies the entire buffer, so
the window is lost and every byte around it comes along.

This is the mistake [core#137](https://github.com/gren-lang/core/issues/137)
reports in `Bytes.flatten`, in a different file; fixing either leaves the other.

## Reproduction

`./run.sh` builds the program and runs `host.js`, which sends `[4, 5]` into the
program three ways, receives the program's 3-byte body two ways, and prints
the table above:

```
$ node host.js
direction        port                                  received                        expected
program -> host  toHost body                           5 bytes [0, 0, 7, 8, 9]         3 bytes [7, 8, 9]
program -> host  roundTrip body (input)                5 bytes [0, 0, 7, 8, 9]         3 bytes [7, 8, 9]
host -> program  flags: a view of [4, 5]               10 bytes [0, 1, 2, 3, 4, ...]   2 bytes [4, 5]
host -> program  roundTrip result: a view of [4, 5]    10 bytes [0, 1, 2, 3, 4, ...]   2 bytes [4, 5]
host -> program  fromHost: a view of [4, 5]            10 bytes [0, 1, 2, 3, 4, ...]   2 bytes [4, 5]
host -> program  fromHost: Buffer.from([4, 5])         8192 bytes [47, 0, 0, 0, 0, ...]  2 bytes [4, 5]
```

`host.js` reads each `DataView` it receives through its own `byteOffset` and
`byteLength`, which is the correct way, so what it prints is what the port
handed over.

## The fix

Copy the window, not the buffer, in all five places:

```js
new DataView(v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength))
```

With that change to the five lines of the compiled `main.js`, every row of the
table matches its expected column.
