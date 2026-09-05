#!/bin/sh
# the B-tree benchmark: cicili -O3, clang -O3 on the same algorithm, Rust's BTreeSet
#   sh bench/btree/run.sh [N]
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); N=${1:-1000000}
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-bench-XXXXXX"); trap 'rm -rf "$D"' EXIT
"$ROOT/bin/cicili" -O3 "$HERE/btree_cicili.c" -o "$D/cicili" || exit 1
clang -O3 "$HERE/btree_c.c" -o "$D/c" || exit 1
rustc -C opt-level=3 "$HERE/btree_rust.rs" -o "$D/rust" 2>/dev/null || exit 1
for round in 1 2 3; do for b in cicili c rust; do "$D/$b" "$N"; done; done
