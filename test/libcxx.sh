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
out=$(HOME="$D" "$C" --local query "ensure_loaded('$ROOT/test/libcxx.pl'), libcxx_main" 2>&1)
echo "$out" | grep -a "^ok\|^FAIL\|^GREEN\|^RED\|ERROR" || echo "$out" | tail -5
echo "$out" | grep -aq "^GREEN" || { echo "$out" | grep -aq "^RED" || echo "RED: the gate did not finish"; exit 1; }
