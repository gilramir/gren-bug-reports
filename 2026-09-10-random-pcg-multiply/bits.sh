#!/bin/sh
# Where the lost bits go: `Random`'s output word, bit by bit, against the same
# generator with the wrapping multiply RXS-M-SH specifies.
set -e
cd "$(dirname "$0")"

devbox run gren run Bits
