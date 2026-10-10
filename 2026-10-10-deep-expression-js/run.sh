#!/bin/sh
# For each shape and depth: generate src/Main.gren, build it with gren make,
# and run it with node. Prints one row per shape.
set -e
cd "$(dirname "$0")"

echo "| shape | 500 | 1000 | 2000 | 4000 |"
echo "|---|---|---|---|---|"
for shape in else-if plus pipe list just; do
    row="| $shape |"
    for n in 500 1000 2000 4000; do
        ./gen.py "$shape" "$n"
        if ! devbox run -q -- gren make Main --output=app > build.log 2>&1; then
            cell="build fails"
        elif devbox run -q -- node app > run.log 2>&1; then
            cell="runs"
        elif grep -q "Maximum call stack size exceeded" run.log; then
            cell="RangeError"
        else
            cell="fails"
        fi
        row="$row $cell |"
    done
    echo "$row"
done
