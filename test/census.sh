#!/bin/sh
# A census of what the reader makes of C++ headers: sh test/census.sh '<vector>' '<string>'
# Runs under a fresh HOME so every header is read flattened (no summary), one cocolog process.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-census-XXXXXX")
trap 'rm -rf "$D"' EXIT
case "$1" in
  *.cpp) CCL_CENSUS_FLAT="$1" "$C" --local query "ensure_loaded('$ROOT/test/census.pl'), census_main" 2>&1 | grep -av "^Warning\|^true\|^false\|^$"; exit 0 ;;   # a flattened file (cicili++ -E)
esac
for h in "$@"; do echo "#include $h"; done > "$D/inv.cpp"
HOME="$D" CCL_CENSUS_FILE="$D/inv.cpp" "$C" --local query "ensure_loaded('$ROOT/test/census.pl'), census_main" 2>&1 | grep -av "^Warning\|^true\|^false\|^$"
