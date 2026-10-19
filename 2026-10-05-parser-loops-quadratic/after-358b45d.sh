#!/bin/sh
# Times record patterns against compiler-common at 358b45d's parent, at
# 358b45d, and at 358b45d with after-358b45d.patch applied. Each is a local
# package; 358b45d needs core 7.5.0 or later, so all three use core 7.6.0 and
# node 6.2.0.
set -e
cd "$(dirname "$0")"

if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./after-358b45d.sh
fi

# inputs/RpN.gren: a `when` on a record pattern of N fields, `{ a0, a1, ... }`.
# inputs/RpEqN.gren: the same with a pattern for each field,
# `{ a0 = x0, a1 = x1, ... }`.
mkdir -p inputs
for n in 8000 16000 32000 64000; do
    awk -v n="$n" 'BEGIN {
        printf "module Rp%d exposing (..)\n\n\nf r =\n    when r is\n        { a0", n
        for (k = 1; k < n; k++) printf ", a%d", k
        printf " } ->\n            0\n"
    }' > "inputs/Rp$n.gren"
    awk -v n="$n" 'BEGIN {
        printf "module RpEq%d exposing (..)\n\n\nf r =\n    when r is\n        { a0 = x0", n
        for (k = 1; k < n; k++) printf ", a%d = x%d", k, k
        printf " } ->\n            0\n"
    }' > "inputs/RpEq$n.gren"
done
files="inputs/Rp8000.gren inputs/Rp16000.gren inputs/Rp32000.gren inputs/Rp64000.gren
inputs/RpEq8000.gren inputs/RpEq16000.gren inputs/RpEq32000.gren inputs/RpEq64000.gren"

mkdir -p after
if [ ! -d after/upstream ]; then
    git clone -q https://github.com/gren-lang/compiler-common after/upstream
fi
build() {
    # $1: the build's directory under after/; $2: the commit; $3: a patch or ""
    if [ ! -d "after/$1/compiler-common" ]; then
        mkdir -p "after/$1"
        git clone -q after/upstream "after/$1/compiler-common"
        git -C "after/$1/compiler-common" -c advice.detachedHead=false checkout -q "$2"
        if [ -n "$3" ]; then
            git -C "after/$1/compiler-common" apply "../../../$3"
        fi
    fi
    rm -rf "after/$1/src"
    cp -r src "after/$1/"
    sed -e 's|"gren-lang/compiler-common": "3.0.0"|"gren-lang/compiler-common": "local:./compiler-common"|' \
        -e 's|"gren-lang/core": "7.4.2"|"gren-lang/core": "7.6.0"|' \
        -e 's|"gren-lang/node": "6.1.3"|"gren-lang/node": "6.2.0"|' \
        gren.json > "after/$1/gren.json"
    (cd "after/$1" && gren make Main --optimize --output=app >/dev/null)
}
build parent 358b45d^ ""
build 358b45d 358b45d ""
build patched 358b45d after-358b45d.patch

for b in parent 358b45d patched; do
    echo
    echo "## $b"
    echo
    node "after/$b/app" $files
done
