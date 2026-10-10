#!/bin/sh
# For each shape and size: generate src/Big.gren, and time `gren make` from
# a clean cache, once for the whole program and once for Big alone, which
# has no main and so is checked but not generated.
set -e
cd "$(dirname "$0")"

secs() {
    start=$(date +%s.%N)
    devbox run -q -- gren make "$@" > build.log 2>&1 || { echo "fails"; return; }
    printf '%.1f' "$(echo "$(date +%s.%N) - $start" | bc)"
}

echo "| shape | N | gren make Main (s) | gren make Big (s) |"
echo "|---|---|---|---|"
row() {
    ./gen.py "$1" "$2"
    rm -rf .gren
    main=$(secs Main --output=app)
    rm -rf .gren
    big=$(secs Big)
    echo "| $1 | $2 | $main | $big |"
}
for n in 4000 16000 64000; do row declarations $n; done
for n in 4000 16000 64000; do row let $n; done
for n in 1000 4000 16000; do row when-int $n; done
for n in 1000 4000 16000; do row variants $n; done
for n in 1000 4000 16000; do row when-variants $n; done
