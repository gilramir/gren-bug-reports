#!/bin/sh
# Shows the bug in two commands: the same analysis, printed two ways.
#
# Nothing here needs Erlang knowledge. `devbox` provides erlang 27; the script
# re-runs itself inside it, builds the small table of types dialyzer wants
# before it will analyse anything (a "PLT"), and then runs the analysis twice.
set -e
cd "$(dirname "$0")"

if [ -z "$IN_DEVBOX" ]; then
    exec env IN_DEVBOX=1 devbox run sh ./run.sh
fi

rm -rf out
mkdir -p out
cd out

echo "=== erlang version ==="
erl -noshell -eval 'io:format("~s / dialyzer ", [erlang:system_info(otp_release)]), halt(0).'
dialyzer --version

echo
echo "=== 1. build the PLT dialyzer needs (about ten seconds) ==="
# A PLT is dialyzer's cache of what it knows about the standard library. It
# refuses to analyse anything without one. Warnings about OTP's own code here
# are normal and do not matter; only the file it writes does.
dialyzer --build_plt --output_plt otp.plt --apps erts kernel stdlib \
    > plt-build.log 2>&1 || true
if [ ! -f otp.plt ]; then
    echo "the PLT did not build; plt-build.log has why"
    exit 1
fi
echo "otp.plt written"

echo
echo "=== 2. the ordinary run: this works ==="
# Exit status 2 means "there were warnings", which is expected here.
dialyzer --plt otp.plt --src ../src && ordinary=0 || ordinary=$?
echo "--- dialyzer exited $ordinary (2 means it had warnings, which is the point)"

echo
echo "=== 3. the same analysis with --raw: this crashes ==="
# --raw asks for the warnings as Erlang terms instead of English. That is the
# only difference from the run above.
dialyzer --plt otp.plt --src --raw ../src && raw=0 || raw=$?
echo "--- dialyzer exited $raw"

echo
echo "=== what to look for ==="
if [ -f erl_crash.dump ]; then
    echo "BUG REPRODUCED: step 3 printed 'Runtime terminating during boot'"
    echo "and left an erl_crash.dump. Step 2, the same analysis, printed the"
    echo "warning and exited 2."
    echo
    echo "the crashing call, from the message above:"
    echo "  dialyzer_cl:'-set_warning_id/2-inlined-0-'/1  (dialyzer_cl.erl:697)"
else
    echo "NOT REPRODUCED: step 3 did not crash. It may be fixed in this"
    echo "version of Erlang/OTP -- the version is printed at the top."
fi
