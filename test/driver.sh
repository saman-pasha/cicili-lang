#!/bin/sh
# The driver's gate: bin/cicili with clang's arguments. GREEN or RED.
#
#   sh test/driver.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-driver-XXXXXX")
trap 'rm -rf "$D"' EXIT
failures=0
check() { if [ "$2" = "$3" ]; then printf 'ok   %-56s %s\n' "$1" "$(echo "$2" | head -1 | cut -c1-40)"; else printf 'FAIL %-56s\n     got  %s\n     want %s\n' "$1" "$2" "$3"; failures=$((failures + 1)); fi; }
cd "$D" && export CICILI_KB="$D/KB"
CICILI="$ROOT/bin/cicili"; R="$ROOT/test/c"

check "--version names cicili-lang, a version, and its back end" "$("$CICILI" --version | sed 's/^cicili-lang 0\.[0-9][0-9]* (cocolog; LLVM [0-9.]*)$/shape ok/')" "shape ok"
s0=$(date +%s); first=$("$CICILI" "$R/run/hello.c" -o hello && ./hello); t_first=$(( $(date +%s) - s0 ))
check "cicili hello.c -o hello: a binary that runs" "$first" "hello, cicili-lang"
check "and with no -o, a.out, as clang" "$("$CICILI" "$R/run/forty2.c"; ./a.out; echo "exit $?")" "exit 42"
check "-c makes NAME.o in the working directory" "$("$CICILI" -c "$R/run/forty2.c" && ls forty2.o)" "forty2.o"
check "-S makes NAME.s with _main in it" "$("$CICILI" -S "$R/run/forty2.c" && grep -c '^_main:' forty2.s)" "1"
check "-emit-llvm -c makes NAME.ll with the IR" "$("$CICILI" -emit-llvm -c "$R/run/forty2.c" && grep -c 'define i32 @main' forty2.ll)" "1"
check "-fsyntax-only refuses a program the safe part refuses, exit 1, one line" "$("$CICILI" -fsyntax-only "$R/safe/use_after_free.c" 2>&1 | grep -c 'error: use after move of')-$("$CICILI" -fsyntax-only "$R/safe/use_after_free.c" >/dev/null 2>&1; echo $?)" "1-1"
check "the diagnostic is file:line: error: what, clang's shape" "$("$CICILI" -fsyntax-only "$R/safe/leak.c" 2>&1 | head -1 | sed "s|$R/||")" "safe/leak.c:2: error: owner leaked: 'p' in return(int(0)) (function main)"
check "two .c files and -O2 link into one program" "$("$CICILI" -O2 "$R/link/main.c" "$R/link/lib.c" -o app && ./app)" "42"
check "a .o from -c links with a .c" "$("$CICILI" -c "$R/link/lib.c" -o lib.o && "$CICILI" "$R/link/main.c" lib.o -o app2 && ./app2)" "42"
check "-I adds to the inclusion path (a typedef from box.h)" "$("$CICILI" -I "$R/inc" "$R/inc/uses_box.c" -o boxed && ./boxed)" "42"
check "-shared -O1 makes a library" "$("$CICILI" -shared -O1 "$R/link/lib.c" -o libtwice.dylib && file libtwice.dylib | grep -c 'dynamically linked shared library')" "1"
check "-ast-dump prints the unit" "$("$CICILI" -ast-dump "$R/run/forty2.c" | grep -c '^unit(\[function(')" "1"
check "an unknown argument is an error, as clang says it" "$("$CICILI" --frobnicate x.c 2>&1)" "cicili: error: unknown argument: '--frobnicate'"
check "no input files is an error" "$("$CICILI" -c 2>&1)" "cicili: error: no input files"
check "a syntax error names the file and the line" "$(printf 'int f(void) { return ; ; }\nint h( { }\n' > bad.c; "$CICILI" -c bad.c 2>&1 | head -1)" "bad.c:2: error: syntax error: could not read this item (gave up near line 2)"
# the store: the first build parsed the headers; a later one loads them -- at least three times faster
s1=$(date +%s); "$CICILI" "$R/run/hello.c" -o hello2 >/dev/null; t_second=$(( $(date +%s) - s1 ))
check "the store: a second build of hello.c is at least 3x faster than the first ($t_first s -> $t_second s)" "$( [ $(( t_second * 3 )) -le "$t_first" ] && echo faster || echo "not faster")" "faster"
if [ "$failures" -eq 0 ]; then echo "GREEN: driver"; else echo "RED: $failures failure(s)"; exit 1; fi
