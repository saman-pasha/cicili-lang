#!/bin/sh
# Build library(ccl_llvm): the embedded LLVM as a cocolog module, over llvm-c.
#
#   CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog LLVM=/usr/local/opt/llvm sh module/build-llvm.sh
#
# LLVM is Homebrew's (brew install llvm); Apple's toolchain has no llvm-c.
# The module links libLLVM-C with an rpath to it. Nothing this makes is committed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CICILI=${CICILI:-$HOME/Projects/GitHub/cicili}
COCOLOG=${COCOLOG:-$HOME/Projects/GitHub/cocolog}
LLVM=${LLVM:-$( [ -d /opt/homebrew/opt/llvm ] && echo /opt/homebrew/opt/llvm || echo /usr/local/opt/llvm )}
[ -f "$CICILI/cicili.lisp" ] || { echo "ccl_llvm: no Cicili at $CICILI (set CICILI)" >&2; exit 1; }
[ -f "$COCOLOG/lib/sdk.cicili" ] || { echo "ccl_llvm: no cocolog SDK at $COCOLOG/lib/sdk.cicili (set COCOLOG)" >&2; exit 1; }
[ -x "$LLVM/bin/llvm-config" ] || { echo "ccl_llvm: no LLVM at $LLVM (brew install llvm; set LLVM)" >&2; exit 1; }
ROOT_SAVED=$ROOT
ROOT=$COCOLOG
. "$COCOLOG/tools/cc/env.sh"
ROOT=$ROOT_SAVED
OUT=${OUT:-$ROOT/library}

ln -sfn "$COCOLOG/lib/sdk.cicili" "$HERE/sdk.cicili"
mkdir -p "$OUT"
( cd "$CICILI" && sbcl --script cicili.lisp --release "$HERE/ccl_llvm.cicili" )
"$CC" -shared -fPIC -O2 -Wno-unused-function $("$LLVM/bin/llvm-config" --cflags) \
    -o "$OUT/ccl_llvm.so" "$HERE/ccl_llvm.c" \
    $("$LLVM/bin/llvm-config" --ldflags) -lLLVM-C -Wl,-rpath,"$LLVM/lib"
echo "built $OUT/ccl_llvm.so (LLVM $("$LLVM/bin/llvm-config" --version) at $LLVM)"
