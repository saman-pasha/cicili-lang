#!/bin/sh
# The gate for the reader. The checks are a cocolog program, test/reader.pl:
# one process over one fresh knowledge base runs every one of them -- the
# grammar, includes, the cache, macros, :=, patterns, format, name { } --
# with each header parsed once. This wrapper adds the one check a single
# process cannot make: that a LATER process finds what the first one read.
#
#   sh test/reader.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-reader-XXXXXX")
trap 'rm -rf "$D"' EXIT
export CCL_TEST_ROOT="$ROOT" CCL_TEST_TMP="$D"

out=$("$C" --embed "$D/kb" run "$ROOT/test/reader.pl" main 2>&1)
echo "$out" | grep -a "^ok\|^FAIL\|^--\|^SKIP\|^     \|^GREEN\|^RED\|ERROR" || echo "$out" | tail -5
failures=$(echo "$out" | grep -ac "^FAIL")
echo "$out" | grep -aq "^GREEN\|^RED" || { echo "RED: the gate did not finish"; exit 1; }

echo "-- a later process, the same store"
s=$(date +%s)
got=$("$C" --embed "$D/kb" query "use_module(library(cicili)), ccl_kb_ready, '\$ccl_ast'(P, _, meta(included(_), _, _)), sub_atom(P, _, _, 0, '/stdio.h'), cicili_ast('$ROOT/test/c/hello.c', U), ccl_declares(U, printf, _), write(answer(yes)), nl" 2>&1 | grep -aoE 'answer\(.*\)' | head -1)
t=$(( $(date +%s) - s ))
if [ "$got" = "answer(yes)" ] && [ "$t" -lt 5 ]; then
  printf 'ok   %s\n' "a later process finds hello.c's headers in the store and reads it in ${t} s"
else
  printf 'FAIL a later process finds hello.c'"'"'s headers in the store and reads it in under 5 s\n     got  %s in %s s\n' "$got" "$t"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then echo "GREEN: reader"; else echo "RED: $failures failure(s)"; exit 1; fi
