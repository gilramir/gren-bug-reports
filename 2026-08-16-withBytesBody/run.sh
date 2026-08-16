#!/bin/sh
# Builds and drives the reproduction. Expects `gren` and `curl` on PATH.
set -e
cd "$(dirname "$0")"

gren make Relay --output relay

node relay > relay.log 2>&1 &
RELAY_PID=$!
sleep 2

# Small bodies are views into Node's 8 KiB buffer pool, so withBytesBody sends
# the whole pool. Bodies of 4096 bytes and up get their own exact allocation and
# come through correctly, which is why this is easy to miss.
echo
echo "=== POST /relay — withBytesBody on the request body (expected: sent == received)"
for n in 8 100 4095 4096 5000; do
  payload=$(head -c "$n" /dev/zero | tr '\0' 'x')
  printf '%5s bytes: %s\n' "$n" "$(curl -s --data-binary "$payload" -m 5 localhost:8086/relay || echo 'no response')"
done

echo
echo "=== POST /relay-compact — same, after re-encoding through Bytes.Encode.bytes"
for n in 8 100 4095 4096 5000; do
  payload=$(head -c "$n" /dev/zero | tr '\0' 'x')
  printf '%5s bytes: %s\n' "$n" "$(curl -s --data-binary "$payload" -m 5 localhost:8086/relay-compact || echo 'no response')"
done

kill $RELAY_PID 2>/dev/null || true

echo
echo "=== Node's own pooling rule, for reference"
node -e 'console.log("Buffer.poolSize =", Buffer.poolSize, "-> pooled when size <", Buffer.poolSize >>> 1);
for (const n of [8, 4095, 4096]) {
  const b = Buffer.concat([Buffer.alloc(n)]);
  console.log(String(n).padStart(5), "byteOffset", String(b.byteOffset).padStart(5),
              " buffer.byteLength", b.buffer.byteLength,
              " new Uint8Array(b.buffer).byteLength", new Uint8Array(b.buffer).byteLength);
}'
