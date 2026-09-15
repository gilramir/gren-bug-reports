// What `_Bytes_getHostEndianness` in gren-lang/core's src/Gren/Kernel/Bytes.js
// computes, next to what it means to compute.

function row(expression, value) {
  console.log("| `" + expression + "` | `" + JSON.stringify(value) + "` |");
}

console.log("| expression | on this host |");
console.log("|---|---|");
row("new Uint8Array(new Uint32Array([0x11223344]))", Array.from(new Uint8Array(new Uint32Array([0x11223344]))));
row("new Uint8Array(new Uint32Array([0x11223344]).buffer)", Array.from(new Uint8Array(new Uint32Array([0x11223344]).buffer)));
row("new Uint8Array(new Uint32Array([1]))[0]", new Uint8Array(new Uint32Array([1]))[0]);
row("new Uint8Array(new Uint32Array([1]).buffer)[0]", new Uint8Array(new Uint32Array([1]).buffer)[0]);
