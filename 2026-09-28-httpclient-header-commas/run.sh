#!/bin/sh
cd "$(dirname "$0")"

# Everything below needs `gren` on PATH; devbox provides the pinned one.
if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

# gren-lang/node at the commit that closed node#71, as a local dependency.
NODE_COMMIT=ecf18b1c
if [ ! -d node-head ]; then
    git clone -q https://github.com/gren-lang/node.git node-head
fi
git -C node-head checkout -q "$NODE_COMMIT"

gren make Main --output=app >/dev/null || exit 1

echo '$ curl -sI https://github.com | grep -iE "^(date|set-cookie):" | cut -c1-100'
curl -sI https://github.com | grep -iE '^(date|set-cookie):' | cut -c1-100
echo
echo "\$ node app   # gren-lang/node $(git -C node-head rev-parse --short HEAD)"
node app
