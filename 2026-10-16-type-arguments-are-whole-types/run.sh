#!/bin/sh
set -e
cd "$(dirname "$0")"

# compiler-common's main, which has fixes not yet released, at the commit this
# was checked against.
COMMIT=d8dedc6e
if [ ! -d compiler-common ]; then
    mkdir compiler-common
    curl -sL "https://github.com/gren-lang/compiler-common/archive/$COMMIT.tar.gz" \
        | tar -xz --strip-components=1 -C compiler-common
fi

devbox run gren run Main
