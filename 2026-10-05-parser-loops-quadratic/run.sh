#!/bin/sh
# Times compiler-common 3.0.0's Compiler.Parse.Module.parser on two kinds of
# generated module at four sizes, then the same parser with builder.patch
# applied.
set -e
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# inputs/WideN.gren: N one-line top-level declarations.
# inputs/ListN.gren: one declaration whose body is a list of N integers.
mkdir -p inputs
for n in 10000 20000 40000 80000; do
    awk -v n="$n" 'BEGIN {
        printf "module Wide%d exposing (..)\n\n\n", n
        for (k = 0; k < n; k++) printf "x%d =\n    %d\n\n\n", k, k
    }' > "inputs/Wide$n.gren"
    awk -v n="$n" 'BEGIN {
        printf "module List%d exposing (..)\n\n\nxs =\n    [ 0\n", n
        for (k = 1; k < n; k++) printf "    , %d\n", k
        printf "    ]\n"
    }' > "inputs/List$n.gren"
done
files="inputs/Wide10000.gren inputs/Wide20000.gren inputs/Wide40000.gren inputs/Wide80000.gren
inputs/List10000.gren inputs/List20000.gren inputs/List40000.gren inputs/List80000.gren"

echo "## compiler-common 3.0.0"
echo
gren make Main --optimize --output=app >/dev/null
node app $files

# The same program against compiler-common 3.0.0 with builder.patch applied,
# as a local package.
if [ ! -d fixed/compiler-common ]; then
    mkdir -p fixed
    git -c advice.detachedHead=false clone -q --branch 3.0.0 https://github.com/gren-lang/compiler-common fixed/compiler-common
    git -C fixed/compiler-common apply ../../builder.patch
fi
sed 's|"gren-lang/compiler-common": "3.0.0"|"gren-lang/compiler-common": "local:./fixed/compiler-common"|' gren.json > fixed/gren.json
cp -r src fixed/
(cd fixed && sed -i 's|local:./fixed/compiler-common|local:./compiler-common|' gren.json && gren make Main --optimize --output=app >/dev/null)

echo
echo "## compiler-common 3.0.0 with builder.patch"
echo
node fixed/app $files
