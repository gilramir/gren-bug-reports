#!/bin/sh
set -e
cd "$(dirname "$0")"

echo "--- a program: the third line is never printed, and the exit code is 0"
devbox run gren run Main
echo "exit code: $?"

echo
echo "--- the REPL, where the exception is visible"
devbox run -- sh -c 'gren repl < session.repl'
