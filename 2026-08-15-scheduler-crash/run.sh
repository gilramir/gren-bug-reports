#!/bin/sh
# Builds and drives both programs. Expects `gren` and `curl` on PATH.
set -e
cd "$(dirname "$0")"

gren make Crash --output crash
gren make Control --output control

echo
echo "=== Crash (HttpServer + one Node subscription) — expected: dies on request 2"
node crash > crash.log 2>&1 &
CRASH_PID=$!
sleep 2
echo "request 1: $(curl -s -o /dev/null -w '%{http_code}' -m 3 localhost:8085/ || echo 'no response')"
sleep 1
echo "request 2: $(curl -s -o /dev/null -w '%{http_code}' -m 3 localhost:8085/ || echo 'no response')"
kill $CRASH_PID 2>/dev/null || true
echo "--- crash.log:"
cat crash.log

echo
echo "=== Control (same program, no Node subscription) — expected: all fine"
node control > control.log 2>&1 &
CONTROL_PID=$!
sleep 2
i=1
while [ $i -le 5 ]; do
  printf "request %s: %s\n" "$i" "$(curl -s -o /dev/null -w '%{http_code}' -m 3 localhost:8084/ || echo 'no response')"
  i=$((i + 1))
done
kill $CONTROL_PID 2>/dev/null || true
echo "--- control.log:"
cat control.log
