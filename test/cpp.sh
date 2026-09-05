#!/bin/sh
# The gate for cicili++, the C++ reader (M5): the checks are test/cpp.pl, one
# clause per construct, one process in memory (no store: the C++ headers are
# too big for the AST cache as cocolog's store stands, see bin/cicili++); then
# the build only the command can make: a C++ file that is C, through cicili++
# to a binary.
#
#   sh test/cpp.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-cpp-XXXXXX")
trap 'rm -rf "$D"' EXIT
export CCL_TEST_ROOT="$ROOT" CCL_TEST_TMP="$D"
out=$("$C" --local query "ensure_loaded('$ROOT/test/cpp.pl'), cpp_main" 2>&1)
echo "$out" | grep -a "^ok\|^FAIL\|^--\|^SKIP\|^     \|^GREEN\|^RED\|ERROR" || echo "$out" | tail -5
failures=$(echo "$out" | grep -ac "^FAIL")
echo "$out" | grep -aq "^GREEN\|^RED" || { echo "RED: the gate did not finish"; exit 1; }
echo "-- cicili++, the command"
cd "$D"
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/hello.cpp" -o hello 2>&1 && ./hello)
if [ "$got" = "hello, cicili++" ]; then echo "ok   cicili++ hello.cpp -o hello: a binary that runs, linked through c++"; else echo "FAIL cicili++ hello.cpp -o hello"; echo "     got  $got"; failures=$((failures + 1)); fi
got=$("$ROOT/bin/cicili++" -fsyntax-only "$ROOT/test/cpp/classes.cpp" 2>&1; echo "exit $?")
if [ "$got" = "exit 0" ]; then echo "ok   cicili++ -fsyntax-only reads a file of classes, and says nothing"; else echo "FAIL cicili++ -fsyntax-only classes.cpp"; echo "     got  $got"; failures=$((failures + 1)); fi
if [ "$failures" -eq 0 ]; then echo "GREEN: cicili++"; else echo "RED: $failures failure(s)"; exit 1; fi
