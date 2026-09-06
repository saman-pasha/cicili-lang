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
s1=$(date +%s); "$ROOT/bin/cicili++" "$ROOT/test/cpp/hello.cpp" -o hello2 >/dev/null 2>&1; t1=$(( $(date +%s) - s1 )); n=$(ls "$HOME/.cicili/cpp/"*.sum 2>/dev/null | wc -l | tr -d ' ')
if [ "$t1" -lt 8 ] && [ "$n" -ge 1 ]; then echo "ok   a second build reads stdio.h's summary from ~/.cicili/cpp, no preprocessing ($t1 s, $n summaries)"; else echo "FAIL a second build is served from the summary cache"; echo "     got  $t1 s, $n summaries"; failures=$((failures + 1)); fi
got=$("$ROOT/bin/cicili++" -fsyntax-only "$ROOT/test/cpp/classes.cpp" 2>&1; echo "exit $?")
if [ "$got" = "exit 0" ]; then echo "ok   cicili++ -fsyntax-only reads a file of classes, and says nothing"; else echo "FAIL cicili++ -fsyntax-only classes.cpp"; echo "     got  $got"; failures=$((failures + 1)); fi
echo "-- M6, in steps: C++ that is C with names, classes, virtual, templates, lambdas, the B-tree the C++ way, std::vector -- built and run (test/cpp/run/NAME.cpp against NAME.expect)"
for src in "$ROOT"/test/cpp/run/*.cpp; do
  n=$(basename "$src" .cpp)
  got=$("$ROOT/bin/cicili++" "$src" -o "$n" 2>&1 && { "./$n"; echo "exit $?"; })
  if [ "$got" = "$(cat "$ROOT/test/cpp/run/$n.expect")" ]; then echo "ok   $n.cpp: built through cicili++, runs, and prints what it should"; else echo "FAIL $n.cpp"; echo "$got" | diff "$ROOT/test/cpp/run/$n.expect" - 2>&1 | head -6 | sed 's/^/     /'; failures=$((failures + 1)); fi
done
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/classes.cpp" -o classes 2>&1 && { ./classes; echo "exit $?"; })
if [ "$got" = "exit 34" ]; then echo "ok   classes.cpp, the reader's fixture (virtual, override, new, delete[], operators, defaults), builds and exits 34"; else echo "FAIL classes.cpp should build and exit 34"; echo "     got  $got" | head -3; failures=$((failures + 1)); fi
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/templates.cpp" -o templates 2>&1 && { ./templates; echo "exit $?"; })
if [ "$got" = "exit 10" ]; then echo "ok   templates.cpp, the reader's fixture (a function and two class templates, an alias, a template in a namespace), builds and exits 10"; else echo "FAIL templates.cpp should build and exit 10"; echo "     got  $got" | head -3; failures=$((failures + 1)); fi
echo "-- and the forms of the later steps are refused by name, not dropped"
for pair in "control:try"; do
  n=${pair%%:*}; what=${pair#*:}
  got=$("$ROOT/bin/cicili++" -c "$ROOT/test/cpp/$n.cpp" -o "$n.o" 2>&1; echo "exit $?")
  case "$got" in *"not lowered yet: $what"*"exit 1"*) echo "ok   $n.cpp is refused: not lowered yet: $what" ;; *) echo "FAIL $n.cpp should be refused with 'not lowered yet: $what'"; echo "     got  $got" | head -3; failures=$((failures + 1)) ;; esac
done
if [ "$failures" -eq 0 ]; then echo "GREEN: cicili++"; else echo "RED: $failures failure(s)"; exit 1; fi
