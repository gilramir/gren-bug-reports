#!/bin/sh
# Builds and runs the reproduction. Expects `gren` on PATH. No ports, no curl.
set -e
cd "$(dirname "$0")"

gren make Flatten --output flatten

echo
echo "=== node flatten — expected: every 'flatten' line matches its input"
node flatten

echo
echo "=== where the wrong bytes come from, in plain node"
node -e 'const {exec} = require("child_process");
// The async exec is the one ChildProcess.run uses; its buffer comes from the pool.
exec("printf %s HELLO-WORLD", {encoding: "buffer"}, (err, out) => {
  console.log("child stdout : byteLength", out.byteLength, " byteOffset", out.byteOffset,
              " buffer.byteLength", out.buffer.byteLength);
  const wrong = new Uint8Array(out.buffer).subarray(0, out.byteLength);
  const right = new Uint8Array(out.buffer, out.byteOffset, out.byteLength);
  console.log("what flatten reads  :", JSON.stringify(Buffer.from(wrong).toString("latin1")));
  console.log("what it should read :", JSON.stringify(Buffer.from(right).toString("latin1")));
});'
