#!/bin/sh
# The gate for the reader: cicili/2 reads a C file whole into an AST, and
# cicili/3 answers where it stopped. One check per thing the grammar must
# take; then real C from the neighbours, read entirely. GREEN or RED.
#
#   sh test/reader.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
failures=0
check() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %-58s %s\n' "$1" "$(echo "$2" | cut -c1-40)"
  else
    printf 'FAIL %-58s\n     got  %s\n     want %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}
answer() { grep -aoE 'answer\(.*\)' | head -1 | sed 's/^answer(//; s/)$//'; }
q() { "$C" --local query "use_module(library(cicili)), $1" 2>&1 | answer; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-reader-XXXXXX")
trap 'rm -rf "$D"' EXIT

echo "-- hello.c, whole"
check "cicili/2 reads the file and answers a unit" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), length(Is, N), write(answer(N)), nl")" "3"
check "the directives are kept whole" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit([directive(2, T)|_])), write(answer(T)), nl")" "#include <stdio.h>"
check "main is a function at its line, returning int, taking void" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), member(function(L, Sto, base([], [int]), main, Ps, V, _), Is), write(answer(L-Sto-Ps-V)), nl")" "5-none-[]-false"
check "its body: a call with a string (10 codes, ending in newline), then return 0" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), member(function(_, _, _, main, _, _, block([expr(call(id(F), [str(S), _])), return(int(R))])), Is), length(S, N), last(S, Last), write(answer(F-N-Last-R)), nl")" "printf-10-10-0"
check "cicili/3 leaves nothing when the whole file parses" \
  "$(q "cicili('$ROOT/test/c/hello.c', _, Rest), write(answer(Rest)), nl")" "[]"

echo "-- rich.c: the grammar, one construct at a time"
R="$ROOT/test/c/rich.c"
check "a typedef of a basic type" \
  "$(q "cicili('$R', unit(Is)), member(typedef(_, [var(ulong, T, none)]), Is), write(answer(T)), nl")" "base([],[unsigned,long])"
check "a typedef of a struct with members" \
  "$(q "cicili('$R', unit(Is)), member(typedef(_, [var(point_t, base([], [struct(point, Ms)]), none)]), Is), length(Ms, N), Ms = [member(_, x, _)|_], write(answer(N)), nl")" "2"
check "an enum with a value" \
  "$(q "cicili('$R', unit(Is)), member(declare(_, base([], [enum(color, Es)])), Is), member(enumerator('GREEN', V), Es), write(answer(V)), nl")" "int(5)"
check "a bitfield member and a self-pointer" \
  "$(q "cicili('$R', unit(Is)), member(declare(_, base([], [struct(node, Ms)])), Is), member(member(ptr([], base([], [struct(node, none)])), next, none), Ms), member(member(_, flags, int(3)), Ms), write(answer(yes)), nl")" "yes"
check "a static function" \
  "$(q "cicili('$R', unit(Is)), member(function(_, static, base([], [int]), square, [param(base([], [int]), n)], false, _), Is), write(answer(yes)), nl")" "yes"
check "a function-pointer parameter, inside out" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, apply, [param(T, f), _], _, _), Is), write(answer(T)), nl")" "ptr([],fn(base([],[int]),[param(base([],[int]),anon)],false))"
check "a prototype is a declaration of a function type" \
  "$(q "cicili('$R', unit(Is)), member(declaration(_, none, _, [var(apply, fn(_, _, _), none)]), Is), write(answer(yes)), nl")" "yes"
check "an array of pointers with a designated initializer" \
  "$(q "cicili('$R', unit(Is)), member(declaration(_, none, base([const], [char]), [var(names, arr(none, ptr([], _)), init(L))]), Is), length(L, N), last(L, item([at(int(3))], _)), write(answer(N)), nl")" "3"
check "designators by field" \
  "$(q "cicili('$R', unit(Is)), member(declaration(_, _, _, [var(origin, _, init([item([field(x)], int(0))|_]))]), Is), write(answer(yes)), nl")" "yes"
check "a float with an exponent, a hex integer, a char escape" \
  "$(q "cicili('$R', unit(Is)), member(declaration(_, _, _, [var(ratio, _, float(F))]), Is), member(declaration(_, _, _, [var(big, _, int(B))]), Is), member(declaration(_, _, _, [var(sep, _, chr(Ch))]), Is), write(answer(F-B-Ch)), nl")" "1500.0-255-10"
check "the typedef name is a type from then on" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(declaration(_, none, base([], [typedef(point_t)]), _), B), write(answer(yes)), nl")" "yes"
check "for, if/else-if, continue, break, compound assignment" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(for(assign('=', id(i), int(0)), bin('<', id(i), id('LIMIT')), postinc(id(i)), block([if(_, continue, if(_, break, none)), expr(assign('+=', id(total), call(id(square), [id(i)])))])), B), write(answer(yes)), nl")" "yes"
check "while, do-while" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(while(bin('>', id(total), int(100)), expr(_)), B), member(do(block([expr(postinc(id(total)))]), bin('<', id(total), int(5))), B), write(answer(yes)), nl")" "yes"
check "switch with cases, a fallthrough and a default" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(switch(id(argc), block([case(int(1), expr(_)), break, case(int(2), default(expr(assign('=', id(total), neg(id(total))))))])), B), write(answer(yes)), nl")" "yes"
check "the conditional, casts, sizeof of a type and of an expression" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(assign('=', id(total), cond(bin('>', id(argc), int(1)), cast(base([], [int]), id(ratio)), bin('+', cast(_, sizeof_type(base([], [typedef(point_t)]))), sizeof(member(id(p), x)))))), B), write(answer(yes)), nl")" "yes"
check "the operator levels: shift, or, and, unary not, xor" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(assign('=', id(mask), bin('^', bin('&', bin('|', bin('<<', id(mask), int(2)), int(3)), bitnot(bin('<<', int(1), int(4)))), int(15)))), B), write(answer(yes)), nl")" "yes"
check "member, address-of, arrow" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(assign('=', arrow(member(id(n), next), flags), int(5))), B), member(expr(assign('=', member(id(n), next), addr(id(n)))), B), write(answer(yes)), nl")" "yes"
check "the comma operator, logical operators, goto and a label" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(assign('=', id(i), comma(id(total), comma(id(mask), int(3))))), B), member(if(not(bin('||', bin('&&', id(i), id(total)), not(id(mask)))), goto(done), none), B), member(label(done, return(_)), B), write(answer(yes)), nl")" "yes"
check "adjacent string literals are one string" \
  "$(q "cicili('$R', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(call(id(printf), [_, _, str(S)])), B), atom_codes(A, S), write(answer(A)), nl")" "ab"

echo "-- where it stops"
printf 'int f(void) { return 1; }\nint g(void) { return ; ; }\nint h( { }\n' > "$D/bad.c"
check "cicili/3 answers the tokens from the first thing it could not read" \
  "$(q "cicili('$D/bad.c', unit(Is), [tok(_, _, L)|_]), length(Is, N), write(answer(N-L)), nl")" "2-3"
check "cicili/2 makes that a syntax error naming the line, and where it gave up" \
  "$(q "catch(cicili('$D/bad.c', _), error(E, _), true), write(answer(E)), nl")" "syntax_error(cicili($D/bad.c,line(3),near(3)))"
printf 'int x = 1;\nchar *s = "unterminated\n' > "$D/lex.c"
check "a lexical error names its line too" \
  "$(q "catch(cicili('$D/lex.c', _), error(syntax_error(cicili(_, lexical, line(L))), _), true), write(answer(L)), nl")" "2"

echo "-- real C from the neighbours, read entirely"
for f in "$CICILI/test/c/main.c" "$CICILI/test/c/shared.c" "$CICILI/test/c/macro.c" "$CICILI/example/cimath.c" "$CICILI/example/numpy_example.c"; do
  name=$(echo "$f" | sed "s|$CICILI/||")
  if [ -f "$f" ]; then
    check "$name" "$(q "cicili('$f', unit(Is), Rest), length(Is, N), ( Rest == [] -> R = whole ; Rest = [tok(_, _, L)|_], ccl_farthest(F), R = stopped_at(L, near(F)) ), write(answer(N-R)), nl" | sed 's/^[0-9]*-//')" "whole"
  else
    echo "SKIP $name (not here)"
  fi
done

if [ "$failures" -eq 0 ]; then echo "GREEN: reader"; else echo "RED: $failures failure(s)"; exit 1; fi
