#!/bin/sh
# the compile-time benchmark: cicili++, clang++ and rustc building the same
# two programs -- a hello, and the B-tree of bench/btree (cicili's own with
# its own arrays and ties checked; the plain-C mirror for clang++, its two
# callocs cast for C++; BTreeSet for rustc) -- at -O0 and -O3, each K times
# with the caches warm, the min and the median of the wall clock reported;
# cicili++'s first run comes first, the init phase: the C++ headers
# preprocessed and summarized once into a fresh HOME; then every compiler
# after it, the caches in place; then the front ends alone, to an object.
#   sh bench/compile/run.sh [K]      K runs per cell (default 5)
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd); K=${1:-5}
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-compile-XXXXXX"); trap 'rm -rf "$D"' EXIT
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
measure() {
    name=$1; shift
    "$@" >/dev/null 2>&1 || { echo "FAIL $name: $*"; return 1; }             # the warm-up, unmeasured
    ts=""; i=0
    while [ "$i" -lt "$K" ]; do
        t0=$(now); "$@" >/dev/null 2>&1; t1=$(now)
        ts="$ts $(echo "$t1 $t0" | awk '{printf "%.3f", $1 - $2}')"; i=$((i + 1))
    done
    echo "$ts" | tr ' ' '\n' | grep . | sort -n | awk -v n="$name" '{a[NR] = $1} END {printf "%-40s min %6.3f s   median %6.3f s\n", n, a[1], a[int((NR + 1) / 2)]}'
}
cp "$ROOT/test/cpp/hello.cpp" "$D/hello.cpp"; cp "$HERE/hello.rs" "$D/hello.rs"
cp "$ROOT/bench/btree/btree_cicili.c" "$D/btree_cicili.cpp"
sed 's/return calloc(/return (node *) calloc(/; s/= calloc(/= (node *) calloc(/' "$ROOT/bench/btree/btree_c.c" > "$D/btree.cpp"
cp "$ROOT/bench/btree/btree_rust.rs" "$D/btree.rs"
measure_cold() {                                                         # cicili++'s first run: a fresh HOME, no summaries yet
    name=$1; shift; rm -rf "$D/home"; mkdir -p "$D/home"
    t0=$(now); COCOLOG="${COCOLOG:-$HOME/Projects/GitHub/cocolog}" CICILI="${CICILI:-$HOME/Projects/GitHub/cicili}" HOME="$D/home" "$@" >"$D/cold.out" 2>&1; st=$?; t1=$(now)
    n=$(ls "$D/home/.cicili/cpp/"*.sum 2>/dev/null | wc -l | tr -d ' ')
    [ "$st" -eq 0 ] || { echo "FAIL $name:"; head -3 "$D/cold.out"; return 1; }
    echo "$t1 $t0" | awk -v n="$name" -v k="$n" '{printf "%-40s %6.3f s   (%d summaries written)\n", n, $1 - $2, k}'
}
echo "-- cicili++'s first run, the init phase: the C++ headers preprocessed and summarized into a fresh HOME"
measure_cold "cicili++ -O0 hello.cpp, first run"       "$ROOT/bin/cicili++" -O0 "$D/hello.cpp" -o "$D/c1"
measure_cold "cicili++ -O0 btree_cicili.cpp, first run" "$ROOT/bin/cicili++" -O0 "$D/btree_cicili.cpp" -o "$D/c2"
echo "-- after the init phase: simple, hello with one printf ($K runs each, the summaries in place)"
measure "cicili++ -O0 hello.cpp"      "$ROOT/bin/cicili++" -O0 "$D/hello.cpp" -o "$D/h1"
measure "clang++ -O0 hello.cpp"       clang++ -O0 "$D/hello.cpp" -o "$D/h2"
measure "rustc -C opt-level=0 hello.rs" rustc -C opt-level=0 "$D/hello.rs" -o "$D/h3"
measure "cicili++ -O3 hello.cpp"      "$ROOT/bin/cicili++" -O3 "$D/hello.cpp" -o "$D/h4"
measure "clang++ -O3 hello.cpp"       clang++ -O3 "$D/hello.cpp" -o "$D/h5"
measure "rustc -C opt-level=3 hello.rs" rustc -C opt-level=3 "$D/hello.rs" -o "$D/h6"
echo "-- after the init phase: complex, the B-tree of bench/btree, 170 lines, with deletion ($K runs each)"
measure "cicili++ -O0 btree_cicili.cpp" "$ROOT/bin/cicili++" -O0 "$D/btree_cicili.cpp" -o "$D/b1"
measure "clang++ -O0 btree.cpp"         clang++ -O0 "$D/btree.cpp" -o "$D/b2"
measure "rustc -C opt-level=0 btree.rs" rustc -C opt-level=0 "$D/btree.rs" -o "$D/b3"
measure "cicili++ -O3 btree_cicili.cpp" "$ROOT/bin/cicili++" -O3 "$D/btree_cicili.cpp" -o "$D/b4"
measure "clang++ -O3 btree.cpp"         clang++ -O3 "$D/btree.cpp" -o "$D/b5"
measure "rustc -C opt-level=3 btree.rs" rustc -C opt-level=3 "$D/btree.rs" -o "$D/b6"
echo "-- the front end alone, to an object, no link ($K runs each)"
measure "cicili++ -O0 -c btree_cicili.cpp" "$ROOT/bin/cicili++" -O0 -c "$D/btree_cicili.cpp" -o "$D/o1.o"
measure "clang++ -O0 -c btree.cpp"         clang++ -O0 -c "$D/btree.cpp" -o "$D/o2.o"
measure "rustc -C opt-level=0 --emit=obj btree.rs" rustc -C opt-level=0 --emit=obj "$D/btree.rs" -o "$D/o3.o"
measure "cicili++ -fsyntax-only btree_cicili.cpp" "$ROOT/bin/cicili++" -fsyntax-only "$D/btree_cicili.cpp"
measure "clang++ -fsyntax-only btree.cpp"         clang++ -fsyntax-only "$D/btree.cpp"
echo "-- the binaries agree: each B-tree run on 100000 keys"
for b in b4 b5 b6; do "$D/$b" 100000 | sed 's/.*ms //'; done
# a compiler written in an interpreted language, for scale: the Python ones
# this Mac can run. PY names a python3 with pycparser and shivyc installed
# (pip install pycparser shivyc), PYCPARSER_FAKE pycparser's
# utils/fake_libc_include directory (its wheel ships none); without them
# the rows are skipped
PY=${PY:-python3}
if "$PY" -c "import pycparser" 2>/dev/null && [ -n "$PYCPARSER_FAKE" ] && [ -d "$PYCPARSER_FAKE" ]; then
    echo "-- in Python: pycparser, the C parser (clang -E over its fake headers inside), read only ($K runs each)"
    cp "$ROOT/bench/btree/btree_c.c" "$D/btree_py.c"
    printf '#include <stdio.h>\nint main() { printf("hello, python\\n"); return 0; }\n' > "$D/hello_py.c"
    for f in hello_py.c btree_py.c; do t=$("$PY" "$HERE/pycparser_parse.py" "$PYCPARSER_FAKE" "$D/$f" "$K"); printf "%-40s min %6.3f s\n" "pycparser $f" "$t"; done
    measure "cicili++ -fsyntax-only hello.cpp" "$ROOT/bin/cicili++" -fsyntax-only "$D/hello.cpp"
else
    echo "-- in Python: pycparser skipped (PY=python3 with pycparser, PYCPARSER_FAKE=its utils/fake_libc_include)"
fi
if "$PY" -c "import shivyc" 2>/dev/null; then
    echo "-- in Python: ShivyC, a C compiler, to assembly (its front end alone: it refuses macOS and the B-tree's C)"
    printf 'int printf(const char *fmt);\nint main() { printf("hello, python\\n"); return 0; }\n' > "$D/hello_sh.c"
    t=$("$PY" "$HERE/shivyc_asm.py" "$D/hello_sh.c" "$K" 2>/dev/null); printf "%-40s min %6.3f s   (plus %s to start python and import it)\n" "shivyc hello_sh.c" "$t" "$( { /usr/bin/time -p "$PY" -c 'import shivyc' ; } 2>&1 | awk '/real/ {print $2 " s"}')"
    measure "cicili++ -S hello.cpp" "$ROOT/bin/cicili++" -S "$D/hello.cpp" -o "$D/h.s"
else
    echo "-- in Python: ShivyC skipped (pip install shivyc into PY)"
fi
