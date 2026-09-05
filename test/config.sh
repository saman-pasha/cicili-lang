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
mkdir -p "$CICILI_KB"
