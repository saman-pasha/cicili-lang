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
out=$("$C" --local query "ensure_loaded('$ROOT/test/cpp.pl'), cpp_main" 2>&1); rc=$?
echo "$out" | grep -a "^ok\|^FAIL\|^--\|^SKIP\|^     \|^GREEN\|^RED\|ERROR" || echo "$out" | tail -5
failures=$(echo "$out" | grep -ac "^FAIL")
# a gate that DIES says so with its exit status and its raw tail, as the libc++ one does (0.84's finding):
# a cocolog that cannot get memory answers `false.' and prints an Unknown message about a _G variable,
# neither of which the filter above keeps, and a crash prints nothing at all
echo "$out" | grep -aq "^GREEN\|^RED" || { echo "RED: the gate did not finish (query exit $rc)"; printf '%s\n' "$out" | tail -20; exit 1; }
echo "-- cicili++, the command"
cd "$D"
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/hello.cpp" -o hello 2>&1 && ./hello)
if [ "$got" = "hello, cicili++" ]; then echo "ok   cicili++ hello.cpp -o hello: a binary that runs, linked through c++"; else echo "FAIL cicili++ hello.cpp -o hello"; echo "     got  $got"; failures=$((failures + 1)); fi
s1=$(date +%s); "$ROOT/bin/cicili++" "$ROOT/test/cpp/hello.cpp" -o hello2 >/dev/null 2>&1; t1=$(( $(date +%s) - s1 )); n=$(ls "$HOME/.cicili/cpp/"*.sum 2>/dev/null | wc -l | tr -d ' ')
if [ "$t1" -lt 8 ] && [ "$n" -ge 1 ]; then echo "ok   a second build reads stdio.h's summary from ~/.cicili/cpp, no preprocessing ($t1 s, $n summaries)"; else echo "FAIL a second build is served from the summary cache"; echo "     got  $t1 s, $n summaries"; failures=$((failures + 1)); fi
got=$("$ROOT/bin/cicili++" -fsyntax-only "$ROOT/test/cpp/classes.cpp" 2>&1; echo "exit $?")
if [ "$got" = "exit 0" ]; then echo "ok   cicili++ -fsyntax-only reads a file of classes, and says nothing"; else echo "FAIL cicili++ -fsyntax-only classes.cpp"; echo "     got  $got"; failures=$((failures + 1)); fi
echo "-- M6, in steps: C++ that is C with names, classes, virtual, templates, lambdas, the B-tree the C++ way, a bag of names, members of class type, C++20, C++23, template template parameters, overloads as C++ chooses, libc++'s std::swap -- built and run (test/cpp/run/NAME.cpp against NAME.expect)"
# A FIXTURE'S BUILD HAS A TIME CAP (0.93): on libc++ 18 two <algorithm> fixtures ran past thirty minutes, and a gate with no
# cap hangs for the owner (0.92 kept a fixture out of the tree for exactly that). The cap is CPP_FIXTURE_SECS (2400: the
# slowest fixture seen on macOS is stdalgorithm3 at about 1700 s); past it the build's whole process tree is killed --
# cocolog is the command's grandchild, so a signal to the command alone leaves it running -- and the fixture FAILs with
# `TIMEOUT after N s', which names the environment's cost rather than hiding it.
CPP_FIXTURE_SECS=${CPP_FIXTURE_SECS:-2400}
ccl_needs_met() {   # ccl_needs_met COND [flags]: does the box's library meet a preprocessor condition? <version> is the library's smallest header, and the marker survives -E only where COND holds
  cond=$1; shift; f=$(mktemp -t needs.XXXXXX.cpp)
  printf '#include <version>\n#if %s\nccl_needs_met\n#endif\n' "$cond" > "$f"
  "$ROOT/bin/cicili++" "$@" -E "$f" 2>/dev/null | grep -q ccl_needs_met; r=$?; rm -f "$f"; return $r
}
skipped=0
ccl_kill_tree() { for c in $(pgrep -P "$1" 2>/dev/null); do ccl_kill_tree "$c"; done; kill -9 "$1" 2>/dev/null; }
ccl_capped() {   # ccl_capped SECS CMD...: the command's output on stdout, its exit status returned; past SECS the tree is killed, the output ends `TIMEOUT after SECS s' and the status is 124
  secs=$1; shift; out=$(mktemp); st=$(mktemp)
  ( "$@" > "$out" 2>&1; echo $? > "$st" ) & p=$!
  t=0; while kill -0 "$p" 2>/dev/null; do sleep 1; t=$((t + 1)); if [ "$t" -ge "$secs" ]; then ccl_kill_tree "$p"; echo "TIMEOUT after ${secs} s" >> "$out"; echo 124 > "$st"; break; fi; done
  wait "$p" 2>/dev/null; cat "$out"; r=$(cat "$st"); rm -f "$out" "$st"; return "$r"
}
for src in "$ROOT"/test/cpp/run/*.cpp; do
  n=$(basename "$src" .cpp)
  flags=$(cat "$ROOT/test/cpp/run/$n.flags" 2>/dev/null)
  inp="$ROOT/test/cpp/run/$n.stdin"; [ -f "$inp" ] || inp=/dev/null   # a fixture that READS gives its input as NAME.stdin (stdcin.cpp); the rest read nothing
  if [ -f "$ROOT/test/cpp/run/$n.needs" ] && ! ccl_needs_met "$(cat "$ROOT/test/cpp/run/$n.needs")" $flags; then   # A FIXTURE BEYOND THE BOX'S LIBRARY IS SKIPPED BY NAME (0.95): NAME.needs holds a preprocessor condition over the library's own macros (`_LIBCPP_VERSION >= 210000': optional<T &> is C++26's and libc++ 18 refuses it), and a box whose library fails it prints the fixture as skipped -- neither ok nor a failure, never a RED for what the environment lacks
    echo "skip $n.cpp: needs $(cat "$ROOT/test/cpp/run/$n.needs"), which this box's library does not meet"; skipped=$((skipped + 1)); continue; fi
  bout=$(ccl_capped "$CPP_FIXTURE_SECS" "$ROOT/bin/cicili++" $flags "$src" -o "$n"); bst=$?
  if [ "$bst" -eq 0 ]; then got=$(printf '%s' "$bout"; "./$n" < "$inp"; echo "exit $?"); else got=$bout; fi
  case "$got" in *"TIMEOUT after"*) echo "FAIL $n.cpp: $(printf '%s' "$got" | tail -1), the build never finished (the environment's cost, named rather than hidden)"; failures=$((failures + 1)); continue ;; esac
  if [ "$got" = "$(cat "$ROOT/test/cpp/run/$n.expect")" ]; then echo "ok   $n.cpp: built through cicili++, runs, and prints what it should"; else echo "FAIL $n.cpp"; echo "$got" | diff "$ROOT/test/cpp/run/$n.expect" - 2>&1 | head -6 | sed 's/^/     /'; failures=$((failures + 1)); fi
done
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/classes.cpp" -o classes 2>&1 && { ./classes; echo "exit $?"; })
if [ "$got" = "exit 34" ]; then echo "ok   classes.cpp, the reader's fixture (virtual, override, new, delete[], operators, defaults), builds and exits 34"; else echo "FAIL classes.cpp should build and exit 34"; echo "     got  $got" | head -3; failures=$((failures + 1)); fi
got=$("$ROOT/bin/cicili++" "$ROOT/test/cpp/templates.cpp" -o templates 2>&1 && { ./templates; echo "exit $?"; })
if [ "$got" = "exit 10" ]; then echo "ok   templates.cpp, the reader's fixture (a function and two class templates, an alias, a template in a namespace), builds and exits 10"; else echo "FAIL templates.cpp should build and exit 10"; echo "     got  $got" | head -3; failures=$((failures + 1)); fi
echo "-- and the forms of the later steps are refused by name, not dropped"
for pair in "control:try" "coro:coroutine" "concept_fail:constraint_not_satisfied" "deduced_this:deduced_this" "constrained_fail:constraint_not_satisfied"; do
  n=${pair%%:*}; what=${pair#*:}
  got=$("$ROOT/bin/cicili++" -c "$ROOT/test/cpp/$n.cpp" -o "$n.o" 2>&1; echo "exit $?")
  case "$got" in *"not lowered yet: $what"*"exit 1"*) echo "ok   $n.cpp is refused: not lowered yet: $what" ;; *) echo "FAIL $n.cpp should be refused with 'not lowered yet: $what'"; echo "     got  $got" | head -3; failures=$((failures + 1)) ;; esac
done
[ "$skipped" -gt 0 ] && echo "-- $skipped fixture(s) skipped: beyond this box's library (NAME.needs)"
if [ "$failures" -eq 0 ]; then echo "GREEN: cicili++"; else echo "RED: $failures failure(s)"; exit 1; fi
