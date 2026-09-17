#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf test
git -c advice.detachedHead=false clone --quiet --branch 5.0.0 --depth 1 https://github.com/gren-lang/test.git test
cd test/tests

echo '$ grep gren-version gren.json'
grep '"gren-version"' gren.json

# The versions tests/gren.json names (core 5.0.0, node 4.0.0,
# test-runner-node 4.0.0) do not install on gren 0.6.6, so point the suite at
# the current releases first, which is what any contributor would do.
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

echo '$ gren make TestsMain'
gren make TestsMain --output=app 2>&1 | grep '^-- '
