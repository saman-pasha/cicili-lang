#!/bin/sh
# The compiler's gate. ONE cocolog process (test/compile.pl) reads, checks,
# lowers, compiles and links every test/c/run/NAME.c to a binary, over the
# user's store, and checks that every test/c/safe/NAME.c is refused; this
# wrapper then runs each binary and compares what it printed and returned
# with test/c/run/NAME.expect, and each refusal with test/c/safe/NAME.expect.
# GREEN or RED.
#
#   sh test/compile.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-compile-XXXXXX")
trap 'rm -rf "$D"' EXIT
export CCL_TEST_ROOT="$ROOT" CCL_TEST_TMP="$D"
failures=0
out=$("$C" --embed "$CICILI_KB" query "ensure_loaded('$ROOT/test/compile.pl'), compile_main" 2>&1)
echo "$out" | grep -aq "^done$" || { echo "RED: the gate did not finish"; echo "$out" | grep -a "FAIL\|ERROR\|error" | head -5; exit 1; }

echo "-- built, run, and checked"
for src in "$ROOT/test/c/run"/*.c; do
  n=$(basename "$src" .c)
  if ! echo "$out" | grep -aq "^built $n$"; then
    printf 'FAIL %-14s %s\n' "$n" "$(echo "$out" | grep -a "^FAIL $n:" | cut -c1-140)"; failures=$((failures + 1)); continue
  fi
  got=$( "$D/$n" arg1 arg2 2>&1; echo "exit $?" )
  if [ -f "$ROOT/test/c/run/$n.expect" ] && [ "$got" = "$(cat "$ROOT/test/c/run/$n.expect")" ]; then
    printf 'ok   %-14s %s\n' "$n" "$(echo "$got" | tail -1)"
  else
    printf 'FAIL %-14s output differs\n' "$n"; echo "$got" | diff "$ROOT/test/c/run/$n.expect" - 2>&1 | head -6 | sed 's/^/     /'; failures=$((failures + 1))
  fi
done

echo "-- refused, by the ownership check"
for src in "$ROOT/test/c/safe"/*.c; do
  n=$(basename "$src" .c)
  got=$(echo "$out" | grep -a "^refused $n \|^compiled $n$\|^FAIL $n:" | head -1 | sed "s/^refused $n //; s/^compiled $n$/compiled/")
  want=$(cat "$ROOT/test/c/safe/$n.expect")
  if [ "$got" = "$want" ]; then printf 'ok   %-18s %s\n' "$n" "$got"; else printf 'FAIL %-18s got %s want %s\n' "$n" "$(echo "$got" | cut -c1-80)" "$want"; failures=$((failures + 1)); fi
done
if [ "$failures" -eq 0 ]; then echo "GREEN: compile"; else echo "RED: $failures failure(s)"; exit 1; fi
