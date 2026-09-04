# Sourced by every gate: where the neighbours are, and this checkout's
# library/ at the FRONT of COCOLOG_LIBRARY, whatever the caller had behind
# it -- the way cocolog's own test/library-path.sh does.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CICILI=${CICILI:-$HOME/Projects/GitHub/cicili}
COCOLOG=${COCOLOG:-$HOME/Projects/GitHub/cocolog}
C="$COCOLOG/cocolog"
COCOLOG_LIBRARY="$ROOT/library${COCOLOG_LIBRARY:+:$COCOLOG_LIBRARY}"
export COCOLOG_LIBRARY CICILI COCOLOG
