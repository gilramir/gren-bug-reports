# `Bytes.getHostEndianness` answers `LE` on every host

`gren-lang/core`'s kernel decides the host's byte order like this
(`src/Gren/Kernel/Bytes.js`):

```js
var _Bytes_getHostEndianness = F2(function (le, be) {
  return __Scheduler_binding(function (callback) {
    callback(
      __Scheduler_succeed(
        new Uint8Array(new Uint32Array([1]))[0] === 1 ? le : be,
      ),
    );
  });
});
```

The test means to write the 32-bit integer 1 and look at its first byte in
memory. It does not look at memory. Constructing a `Uint8Array` from another
typed array copies its **elements**, converting each value to the new element
type (ECMAScript, `InitializeTypedArrayFromTypedArray`, when the two element
types differ). The one element is 1, and 1 as a byte is 1, so the comparison is
true on a big-endian host as well, and `getHostEndianness` answers `LE` there.

What the expressions give, from `./run.sh`:

| expression | on this host |
|---|---|
| `new Uint8Array(new Uint32Array([0x11223344]))` | `[68]` |
| `new Uint8Array(new Uint32Array([0x11223344]).buffer)` | `[68,51,34,17]` |
| `new Uint8Array(new Uint32Array([1]))[0]` | `1` |
| `new Uint8Array(new Uint32Array([1]).buffer)[0]` | `1` |

The first row is one element, `0x44`, the value's low eight bits, and not four
bytes: the copy read no byte order. The second row is a view of the same memory,
and reads the host's order: `44 33 22 11` here, and `11 22 33 44` on a
big-endian machine. On a little-endian host the last two rows agree, which is
why this has gone unnoticed; on a big-endian one the third is still `1` and
the fourth is `0`.

## The fix

```js
new Uint8Array(new Uint32Array([1]).buffer)[0] === 1 ? le : be
```

`elm/bytes` has the same line.

- **Filed as:** not yet filed
- **Package:** `gren-lang/core` 7.4.2
- **Versions:** node 22.23.2, little-endian x86-64
