# Sourced by every gate: where the neighbours are, and this checkout's
# library/ at the FRONT of COCOLOG_LIBRARY, whatever the caller had behind
# it -- the way cocolog's own test/library-path.sh does.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CICILI=${CICILI:-$HOME/Projects/GitHub/cicili}
COCOLOG=${COCOLOG:-$HOME/Projects/GitHub/cocolog}
C="$COCOLOG/cocolog"
COCOLOG_LIBRARY="$ROOT/library${COCOLOG_LIBRARY:+:$COCOLOG_LIBRARY}"
export COCOLOG_LIBRARY CICILI COCOLOG

# the knowledge base every gate uses: the user's, ~/.cicili/KB, so the system
# headers are read once, the first run being the initialization phase, and
# served as static data to every later run (owner's rule); a gate that wants
# a fresh one sets CICILI_KB itself
export CICILI_KB="${CICILI_KB:-$HOME/.cicili/KB}"
# stamped with the reader's grammar version and started afresh when it
# changes, as bin/cicili does (its kb_prepare is this one's twin): cocolog's
# store never reclaims a retracted row, and a fat store slows every
# predicate's first call
ccl_kb_prepare() {
  v=$(awk '/^ccl_reader_version\(/ { sub(/^ccl_reader_version\(/, ""); sub(/\).*/, ""); r = $0 } /^ccl_lowering_version\(/ { sub(/^ccl_lowering_version\(/, ""); sub(/\).*/, ""); l = $0 } END { print r "." l }' "$ROOT/library/ccl_syntax.pl" "$ROOT/library/ccl_ir.pl")
  stamp="$1.version"; have=""
  [ -f "$stamp" ] && read -r have < "$stamp"
  if [ -f "$1/data.bin" ] && [ "$have" != "$v" ]; then rm -rf "$1"; have=""; fi
  [ -d "$1" ] || mkdir -p "$1"
  [ "$have" = "$v" ] || echo "$v" > "$stamp"
}
ccl_kb_prepare "$CICILI_KB"
