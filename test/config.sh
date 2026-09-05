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
  v="$(sed -n 's/^ccl_reader_version(\([0-9]*\))\..*/\1/p' "$ROOT/library/ccl_syntax.pl" | head -1).$(sed -n 's/^ccl_lowering_version(\([0-9]*\))\..*/\1/p' "$ROOT/library/ccl_ir.pl" | head -1)"
  stamp="$1.version"
  [ -f "$1/data.bin" ] && [ "$(cat "$stamp" 2>/dev/null)" != "$v" ] && rm -rf "$1"
  mkdir -p "$1"; [ "$(cat "$stamp" 2>/dev/null)" = "$v" ] || echo "$v" > "$stamp"
}
ccl_kb_prepare "$CICILI_KB"
