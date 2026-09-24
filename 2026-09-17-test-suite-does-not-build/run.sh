#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf test
git -c advice.detachedHead=false clone --quiet --branch 5.0.0 --depth 1 https://github.com/gren-lang/test.git test
cd test/tests

# 1. The suite's own script.
echo '$ ./run-tests.sh'
./run-tests.sh 2>&1

# 2. The same build with a module name, against the suite's gren.json
# (the download progress left out).
echo '$ gren make TestsMain --output=/dev/null'
gren make TestsMain --output=/dev/null 2>&1 | sed -n '/^-- /,$p'

# 3. The same build with tests/gren.json moved to the current releases.
cat > gren.json <<'JSON'
{
    "type": "application",
    "platform": "node",
    "source-directories": ["src"],
    "gren-version": "0.6.6",
    "dependencies": {
        "direct": {
            "gren-lang/core": "7.4.2",
            "gren-lang/node": "6.1.3",
            "gren-lang/test": "local:..",
            "gren-lang/test-runner-node": "7.0.0"
        },
        "indirect": {
            "gren-lang/url": "6.0.0"
        }
    }
}
JSON
echo "\$ gren make TestsMain --output=/dev/null 2>&1 | grep -o -- '-- [A-Z].*'"
gren make TestsMain --output=/dev/null 2>&1 | grep -o -- '-- [A-Z].*'
