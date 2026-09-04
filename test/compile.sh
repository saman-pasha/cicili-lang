#!/bin/sh
# The compiler's gate: every test/c/run/NAME.c goes through the four
# predicates -- cicili_ast, cicili_ir, cicili_compile, cicili_link -- to a
# binary that is run; what it prints and returns must be test/c/run/NAME.expect
# (its stdout, then a last line `exit N'). GREEN or RED.
#
#   sh test/compile.sh          all of them
#   sh test/compile.sh funcs    one
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-compile-XXXXXX")
trap 'rm -rf "$D"' EXIT
failures=0
if [ $# -gt 0 ]; then names="$*"; else names=$(ls "$ROOT/test/c/run"/*.c | sed 's|.*/||; s|\.c$||'); fi
for n in $names; do
  src="$ROOT/test/c/run/$n.c"
  # one store for the whole gate: the headers are parsed by the first program that needs them
  err=$("$C" --embed "$D/kb" query "use_module(library(cicili)), cicili_ast('$src', A), cicili_ir([A], IR), cicili_compile(IR, '$D/$n.o', ['-O1']), cicili_link(['$D/$n.o'], [], '$D/$n'), write(built), nl" 2>&1 | grep -a "ERROR\|built" | head -1)
  if [ "$err" != "built" ]; then
    printf 'FAIL %-12s %s\n' "$n" "$(echo "$err" | cut -c1-140)"; failures=$((failures + 1)); continue
  fi
  got=$( "$D/$n" arg1 arg2 2>&1; echo "exit $?" )
  if [ -f "$ROOT/test/c/run/$n.expect" ]; then
    if [ "$got" = "$(cat "$ROOT/test/c/run/$n.expect")" ]; then
      printf 'ok   %-12s %s\n' "$n" "$(echo "$got" | tail -1)"
    else
      printf 'FAIL %-12s output differs\n' "$n"; echo "$got" | diff "$ROOT/test/c/run/$n.expect" - | head -8 | sed 's/^/     /'; failures=$((failures + 1))
    fi
  else
    printf 'FAIL %-12s no %s.expect; it printed:\n' "$n" "$n"; echo "$got" | sed 's/^/     /'; failures=$((failures + 1))
  fi
done
if [ "$failures" -eq 0 ]; then echo "GREEN: compile"; else echo "RED: $failures failure(s)"; exit 1; fi
