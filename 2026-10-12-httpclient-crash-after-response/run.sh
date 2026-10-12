#!/bin/sh
cd "$(dirname "$0")"

devbox run gren make Main --output=app >/dev/null
devbox run -q -- sh -c 'node app; echo "exit status: $?"'
