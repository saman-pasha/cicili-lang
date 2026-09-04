#!/bin/sh
# M0: the LLVM end of the pipeline, on this machine, before the compiler exists.
# Apple's clang consumes textual LLVM IR and drives the backend to a native
# binary -- no LLVM install. Emitting .ll and driving clang IS the plan's
# back end (compilation, not transpilation: the output is IR, not C).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
clang "$HERE/forty2.ll" -o "$HERE/forty2"
"$HERE/forty2"; rc=$?
if [ "$rc" = 42 ]; then echo "GREEN: LLVM IR -> native binary -> exit 42"; else echo "RED: exit $rc"; exit 1; fi
