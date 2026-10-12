#!/bin/sh
# For each shape and size: generate src/Big.gren and time `gren make Big`
# from a clean cache. Big has no main, so it is checked but not generated.
#
# GREN_BIN names the compiler binary the gren command runs, so the same
# script times a build of the compiler with the change in README.md:
#     GREN_BIN=/path/to/patched/gren ./run.sh
set -e
cd "$(dirname "$0")"

secs() {
    start=$(date +%s.%N)
    devbox run -q -- env ${GREN_BIN:+GREN_BIN="$GREN_BIN"} gren make "$@" > build.log 2>&1 || { echo "fails"; return; }
    printf '%.1f' "$(echo "$(date +%s.%N) - $start" | bc)"
}

echo "| shape | N | gren make Big (s) |"
echo "|---|---|---|"
for shape in declarations functions let; do
    for n in 4000 16000 64000; do
        ./gen.py "$shape" "$n"
        rm -rf .gren
        echo "| $shape | $n | $(secs Big) |"
    done
done
