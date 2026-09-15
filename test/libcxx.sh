#!/bin/sh
# The road to libc++: the standard library as it ships, flattened by cocolog's
# preprocessor and read whole by the reader (test/libcxx.pl, one check per header).
# A fresh HOME, so every header is read, not served from a summary. About a minute.
#
#   sh test/libcxx.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-libcxx-XXXXXX")
trap 'rm -rf "$D"' EXIT
export CCL_TEST_TMP="$D"
out=$(HOME="$D" "$C" --local query "ensure_loaded('$ROOT/test/libcxx.pl'), libcxx_main" 2>&1); rc=$?
echo "$out" | grep -a "^ok\|^FAIL\|^GREEN\|^RED\|ERROR" || echo "$out" | tail -5
# A GATE THAT DIES SAYS SO WITH ITS EXIT STATUS AND ITS RAW TAIL: the filter above keeps the lines
# that match, and a cocolog that cannot get memory prints `false.' and an Unknown message about a
# _G variable -- neither matches, and a crash prints nothing at all. The status told apart a killed
# run from a refused one when the libc++ gate died once at 0.84 (the finding in CLAUDE.md).
echo "$out" | grep -aq "^GREEN" || { echo "$out" | grep -aq "^RED" || { echo "RED: the gate did not finish (query exit $rc)"; printf '%s\n' "$out" | tail -20; }; exit 1; }
