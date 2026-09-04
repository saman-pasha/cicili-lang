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
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-reader-XXXXXX")
trap 'rm -rf "$D"' EXIT
# every check is its own process, sharing one embedded store: a header is
# parsed by the first that needs it and loaded from the store by the rest
q() { "$C" --embed "$D/kb" query "use_module(library(cicili)), $1" 2>&1 | answer; }

echo "-- hello.c, whole"
check "cicili/2 reads the file and answers a unit" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), length(Is, N), write(answer(N)), nl")" "3"
check "a directive that is not an include is kept whole" \
  "$(q "cicili('$ROOT/test/c/rich.c', unit(Is)), member(directive(5, T), Is), write(answer(T)), nl")" "#define LIMIT 10"
check "main is a function at its line, returning int, taking void" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), member(function(L, Sto, base([], [int]), main, Ps, V, _), Is), write(answer(L-Sto-Ps-V)), nl")" "5-none-[]-false"
check "its body: a call with a string (10 codes, ending in newline), then return 0" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit(Is)), member(function(_, _, _, main, _, _, block([expr(call(id(F), [str(S), _])), return(int(R))])), Is), length(S, N), last(S, Last), write(answer(F-N-Last-R)), nl")" "printf-10-10-0"
check "cicili/3 leaves nothing when the whole file parses" \
  "$(q "cicili('$ROOT/test/c/hello.c', _, Rest), write(answer(Rest)), nl")" "[]"

echo "-- includes: found on the inclusion path, read, and their typedefs known"
check "<stdio.h> resolves to a file on the toolchain's path and is read" \
  "$(q "cicili('$ROOT/test/c/hello.c', unit([include(2, system('stdio.h'), file(P, How, U))|_])), sub_atom(P, _, _, 0, '/stdio.h'), memberchk(How, [raw, preprocessed]), U = unit(_), write(answer(yes)), nl")" "yes"
check "and printf is declared somewhere under it" \
  "$(q "cicili('$ROOT/test/c/hello.c', U), ccl_declares(U, printf, I), functor(I, F, _), write(answer(F)), nl")" "declaration"
check "and malloc under <stdlib.h>, as a function returning a pointer" \
  "$(q "cicili('$ROOT/test/c/hello.c', U), ccl_declares(U, malloc, declaration(_, _, _, [var(malloc, fn(ptr(_, _), _, _), _)])), write(answer(yes)), nl")" "yes"
printf 'typedef struct { int id; } Parcel;\n' > "$D/local.h"
printf '#include "local.h"\nint f(void) { Parcel * p = 0; return p == 0; }\n' > "$D/uses.c"
check "a quoted include is found beside the file and read raw" \
  "$(q "cicili('$D/uses.c', unit([include(1, local('local.h'), file('$D/local.h', raw, unit([typedef(1, _)])))|_])), write(answer(yes)), nl")" "yes"
check "and its typedef makes 'Parcel * p = 0;' a declaration in the includer" \
  "$(q "cicili('$D/uses.c', unit(Is)), member(function(_, _, _, f, _, _, block([I|_])), Is), functor(I, F, _), write(answer(F)), nl")" "declaration"
printf '#include "nope.h"\nint x;\n' > "$D/missing.c"
check "a header that is nowhere is missing, and the file still reads" \
  "$(q "cicili('$D/missing.c', unit([include(1, local('nope.h'), R), declaration(2, _, _, _)])), write(answer(R)), nl")" "missing"
printf '#include "b.h"\nint a;\n' > "$D/a.h"; printf '#include "a.h"\nint b;\n' > "$D/b.h"; printf '#include "a.h"\n' > "$D/cyc.c"
check "a cycle of headers is cut, not followed" \
  "$(q "cicili('$D/cyc.c', unit([include(1, _, file(_, raw, unit([include(1, _, file(_, raw, unit([include(1, _, R)|_])))|_])))])), write(answer(R)), nl")" "cyclic($D/a.h)"
check "the toolchain's inclusion path is asked of clang, once" \
  "$(q "ccl_include_path(Ds), length(Ds, N), ( N > 1 -> R = several ; R = N ), write(answer(R)), nl")" "several"

echo "-- the knowledge base remembers what was read, by modification time"
check "a later process finds hello.c's headers in the store" \
  "$(q "ccl_kb_ready, '\$ccl_ast'(P, _, meta(included(_), N, _)), sub_atom(P, _, _, 0, '/stdio.h'), N > 0, write(answer(yes)), nl")" "yes"
check "and hello.c itself, read whole, keyed by its time and the reader's version" \
  "$(q "ccl_kb_ready, '\$ccl_ast'('$ROOT/test/c/hello.c', key(T, V), meta(top, 3, [_, _])), number(T), ccl_reader_version(V), write(answer(yes)), nl")" "yes"
s=$(date +%s); q "cicili('$ROOT/test/c/hello.c', unit(Is)), length(Is, N), write(answer(N)), nl" > /dev/null; t=$(( $(date +%s) - s ))
check "so reading hello.c again, headers and all, takes under 5 s" "$( [ "$t" -lt 5 ] && echo fast || echo "slow ($t s)" )" "fast"
touch "$D/uses.c"
check "a touched file is read again, not served stale" \
  "$(q "ccl_kb_ready, '\$ccl_ast'('$D/uses.c', key(T0, _), _), cicili('$D/uses.c', _), '\$ccl_ast'('$D/uses.c', key(T1, _), _), ( T1 > T0 -> R = reread ; R = stale ), write(answer(R)), nl")" "reread"
check "and a cached read is the same AST as a fresh one" \
  "$(q "cicili('$ROOT/test/c/rich.c', A), ccl_kb_forget_file('$ROOT/test/c/rich.c'), cicili('$ROOT/test/c/rich.c', B), ( A == B -> R = same ; R = different ), write(answer(R)), nl")" "same"

echo "-- macros: a .pl included is a set of macro functions over ASTs"
cat > "$D/macros.pl" <<'EOF'
square(X, bin('*', X, X)).
swap(A, B, block([declaration(0, none, base([], [int]), [var(T, base([], [int]), A)]), expr(assign('=', A, B)), expr(assign('=', B, id(T)))])) :- ccl_gensym(tmp, T).
counter(id(N), declaration(0, static, base([], [int]), [var(N, base([], [int]), int(0))])).
pair(id(A), id(B), [declaration(0, none, base([], [int]), [var(A, base([], [int]), int(1))]), declaration(0, none, base([], [int]), [var(B, base([], [int]), int(2))])]).
sum(R) --> [X], sum_rest(X, R).
sum_rest(A, R) --> [X], !, sum_rest(bin('+', A, X), R).
sum_rest(A, A) --> [].
typename(X, str(Codes)) :- ccl_type_of(X, T), term_to_atom(T, A), atom_codes(A, Codes).
size(X, int(N)) :- ccl_type_of(X, T), ccl_size_of(T, N).
boom(_, _) :- fail.
EOF
cat > "$D/uses_macros.c" <<'EOF'
#include "macros.pl"
typedef struct point { int x; double y; } point_t;
struct node { struct node *next; point_t at; };
counter(hits);
pair(lo, hi);
int f(int a, long b, point_t p, struct node *n, char *s) {
    const char *t1 = typename(a);
    const char *t2 = typename(a + 1.5);
    const char *t4 = typename(n->at.x);
    const char *t6 = typename(f(1, 2, p, n, s) + b);
    int sz = size(p);
    swap(a, b);
    return square(a) + sum(a, 2, 3);
}
EOF
M="$D/uses_macros.c"
check "the include node names the macro file and its predicates, DCG ones too" \
  "$(q "cicili('$M', unit([include(1, local('macros.pl'), macros('$D/macros.pl', Ps))|_])), memberchk(macro(square, square, 2), Ps), memberchk(macro(swap, swap, 3), Ps), memberchk(macro(sum, sum, dcg), Ps), write(answer(yes)), nl")" "yes"
check "a macro at file scope: counter(hits); is a static int declaration" \
  "$(q "cicili('$M', unit(Is)), member(declaration(_, static, _, [var(hits, _, int(0))]), Is), write(answer(yes)), nl")" "yes"
check "a list result is spliced: pair(lo, hi); is two declarations" \
  "$(q "cicili('$M', unit(Is)), append(_, [declaration(_, _, _, [var(lo, _, int(1))]), declaration(_, _, _, [var(hi, _, int(2))])|_], Is), write(answer(yes)), nl")" "yes"
check "in an expression: square(a) is a * a" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(return(bin('+', bin('*', id(a), id(a)), _)), B), write(answer(yes)), nl")" "yes"
check "a DCG macro parses its arguments: sum(a, 2, 3) folds to (a + 2) + 3" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(return(bin('+', _, bin('+', bin('+', id(a), int(2)), int(3)))), B), write(answer(yes)), nl")" "yes"
check "as a statement: swap(a, b); is a block with a fresh temporary" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(block([declaration(_, _, _, [var(T, _, id(a))]), expr(assign('=', id(a), id(b))), expr(assign('=', id(b), id(T)))]), B), sub_atom(T, 0, 4, _, tmp_), write(answer(yes)), nl")" "yes"
check "type inference: a parameter, the usual conversions, a member through a pointer and a typedef" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(t1, _, str(S1))]), B), member(declaration(_, _, _, [var(t2, _, str(S2))]), B), member(declaration(_, _, _, [var(t4, _, str(S4))]), B), atom_codes(A1, S1), atom_codes(A2, S2), atom_codes(A4, S4), write(answer(A1/A2/A4)), nl")" "base([],[int])/base([],[double])/base([],[int])"
check "and a call's return type combined with a long" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(t6, _, str(S))]), B), atom_codes(A, S), write(answer(A)), nl")" "base([],[long])"
check "the size of a struct, LP64: int + double = 16" \
  "$(q "cicili('$M', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(sz, _, int(N))]), B), write(answer(N)), nl")" "16"
printf '#include "macros.pl"\nint g(void) { return boom(1); }\n' > "$D/bad_macro.c"
check "a macro that fails stops the read with its name and arguments" \
  "$(q "catch(cicili('$D/bad_macro.c', _), error(E, _), true), write(answer(E)), nl")" "macro_failed(boom,[int(1)])"
printf 'bang(_, _) :- throw(oops).\n' > "$D/throws.pl"
printf '#include "throws.pl"\nint k(void) { return bang(1); }\n' > "$D/throwing_macro.c"
check "a macro that throws reports the macro, its arguments and the ball" \
  "$(q "catch(cicili('$D/throwing_macro.c', _), error(E, _), true), write(answer(E)), nl")" "macro_error(bang,[int(1)],oops)"
touch "$D/macros.pl"
check "a changed macro file makes its includer's cached read a miss" \
  "$(q "( ccl_kb_cached('$M', top, _) -> R = hit ; R = miss ), write(answer(R)), nl")" "miss"

echo "-- := declares by inference"
cat > "$D/walrus.c" <<'EOF'
typedef struct point { int x; double y; } point_t;
g := 7;
int f(point_t p, char *s, const int k) {
    n := 42;
    d := n + 1.5;
    q := &p;
    y := q->y;
    t := s;
    c := k;
    for (i := 0; i < n; i++) { n += i; }
    return n + g;
}
EOF
W="$D/walrus.c"
check "n := 42; is an int declaration with that initializer" \
  "$(q "cicili('$W', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(4, none, base([], [int]), [var(n, base([], [int]), int(42))]), B), write(answer(yes)), nl")" "yes"
check "d := n + 1.5; is a double, by the usual conversions" \
  "$(q "cicili('$W', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(d, T, _)]), B), write(answer(T)), nl")" "base([],[double])"
check "q := &p; is a pointer to the typedef, and y := q->y; a double through it" \
  "$(q "cicili('$W', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(q, QT, _)]), B), member(declaration(_, _, _, [var(y, YT, _)]), B), write(answer(QT/YT)), nl")" "ptr([],base([],[typedef(point_t)]))/base([],[double])"
check "t := s; keeps the pointer type; c := k; drops the const: the new variable is its own" \
  "$(q "cicili('$W', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(t, TT, _)]), B), member(declaration(_, _, _, [var(c, CT, _)]), B), write(answer(TT/CT)), nl")" "ptr([],base([],[char]))/base([],[int])"
check "for (i := 0; ...) declares i in the for" \
  "$(q "cicili('$W', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(for(decl(base([], [int]), [var(i, base([], [int]), int(0))]), _, postinc(id(i)), _), B), write(answer(yes)), nl")" "yes"
check "g := 7; at file scope is a global int" \
  "$(q "cicili('$W', unit(Is)), member(declaration(2, none, base([], [int]), [var(g, _, int(7))]), Is), write(answer(yes)), nl")" "yes"
cat > "$D/pattern.c" <<'EOF'
typedef struct point { int x; double y; } point_t;
struct node { struct node *next; point_t at; const char *name; };
point_t make(void);
int f(point_t p, struct node *n) {
    { a, b } := p;
    { _, at: { x, y }, name: nm } := n;
    { u, v } := make();
    return a + x + u;
}
EOF
P="$D/pattern.c"
check "{ a, b } := p; binds the members by position, each a declaration by inference" \
  "$(q "cicili('$P', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(5, none, _, [var(a, base([], [int]), member(id(p), x))]), B), member(declaration(5, none, _, [var(b, base([], [double]), member(id(p), y))]), B), write(answer(yes)), nl")" "yes"
check "_ skips, field: name binds by name, a nested { } destructures a member, all through a pointer" \
  "$(q "cicili('$P', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, _, [var(x, base([], [int]), member(arrow(id(n), at), x))]), B), member(declaration(_, _, _, [var(nm, ptr([], base([const], [char])), arrow(id(n), name))]), B), \\+ member(declaration(_, _, _, [var(next, _, _)]), B), write(answer(yes)), nl")" "yes"
check "a right-hand side that is not a variable is evaluated once, into a temporary" \
  "$(q "cicili('$P', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), append(_, [declaration(_, _, _, [var(T, base([], [typedef(point_t)]), call(id(make), []))]), declaration(_, _, _, [var(u, _, member(id(T), x))]), declaration(_, _, _, [var(v, _, member(id(T), y))])|_], B), sub_atom(T, 0, 4, _, tmp_), write(answer(yes)), nl")" "yes"
printf 'typedef struct point { int x; double y; } point_t;\nint g(point_t p) { { a, b, c } := p; return a; }\n' > "$D/pattern_bad.c"
check "a pattern longer than the struct is an error naming the position" \
  "$(q "catch(cicili('$D/pattern_bad.c', _), error(E, here(_, L)), true), write(answer(E-L)), nl")" "no_member(position(3),base([],[typedef(point_t)]))-2"
printf 'typedef struct point { int x; double y; } point_t;\nint g(point_t p) { { zz: q } := p; return q; }\n' > "$D/pattern_bad2.c"
check "a field the struct has not is an error naming it" \
  "$(q "catch(cicili('$D/pattern_bad2.c', _), error(E, _), true), write(answer(E)), nl")" "no_member(zz,base([],[typedef(point_t)]))"
printf 'int h(void) {\n    z := nothing;\n    return z;\n}\n' > "$D/no_infer.c"
check "a right-hand side whose type is unknown is an error naming the variable, the file and the line" \
  "$(q "catch(cicili('$D/no_infer.c', _), error(E, here(F, L)), true), F == '$D/no_infer.c', write(answer(E-L)), nl")" "cannot_infer(z,id(nothing))-2"

echo "-- format, print, println: global macros, Rust's holes, the symbol table's types"
cat > "$D/fmt.c" <<'EOF'
#include <stdio.h>
typedef struct point { int x; double y; } point_t;
struct node { point_t at; const char *name; unsigned long id; };
int main(void) {
    n := 42;
    name := "cicili";
    p := (point_t){ 1, 2.5 };
    println("n = {} name = {name} again {0} p = {p} 100%", n);
    s := format("{} + {} = {}", 1, 2, 3);
    print("{s}\n");
    struct node nd = { p, "root", 7ul };
    println("{nd} {{braces}}");
    return 0;
}
EOF
FM="$D/fmt.c"
check "println: {} next, {name} by name, {0} by index, {p} a struct by its members, % kept, newline added" \
  "$(q "cicili('$FM', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(call(id(printf), [str(S), id(n), id(name), id(n), member(id(p), x), member(id(p), y)])), B), atom_codes(A, S), A == 'n = %d name = %s again %d p = point_t { x: %d, y: %g } 100%%\\n', write(answer(yes)), nl")" "yes"
check "format is an expression of type char *: asprintf into a fresh buffer, in a statement expression" \
  "$(q "cicili('$FM', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(declaration(_, _, _, [var(s, ptr([], base([], [char])), stmt_expr(block([declaration(_, _, _, [var(Buf, _, none)]), expr(call(id(asprintf), [addr(id(Buf)), str(S), int(1), int(2), int(3)])), expr(id(Buf))])))]), B), atom_codes(A, S), write(answer(A)), nl")" "%d + %d = %d"
check "a struct inside a struct nests; unsigned long is %lu; {{ }} are braces" \
  "$(q "cicili('$FM', unit(Is)), member(function(_, _, _, main, _, _, block(B)), Is), member(expr(call(id(printf), [str(S), member(member(id(nd), at), x), member(member(id(nd), at), y), member(id(nd), name), member(id(nd), id)])), B), atom_codes(A, S), A == 'node { at: point_t { x: %d, y: %g }, name: %s, id: %lu } {braces}\\n', write(answer(yes)), nl")" "yes"
printf 'int main(void) { n := 1; println("{} {}", n); return 0; }\n' > "$D/fmt_bad.c"
check "a hole with no argument is an error with its place" \
  "$(q "catch(cicili('$D/fmt_bad.c', _), error(macro_error(M, here(_, L)), _), true), write(answer(M-L)), nl")" "no_argument(1)-1"
printf 'int main(void) { println("{nope}"); return 0; }\n' > "$D/fmt_bad2.c"
check "a name not in scope cannot be formatted" \
  "$(q "catch(cicili('$D/fmt_bad2.c', _), error(macro_error(M, here(F, _)), _), true), F == '$D/fmt_bad2.c', write(answer(M)), nl")" "cannot_format(id(nope))"

echo "-- name { ... } at file scope is typedef struct name { ... } name;"
cat > "$D/shorthand.c" <<'EOF'
point { int x; double y; }
node { node *next; point at; };
int f(void) { point p = { 1, 2.5 }; node n = { 0, p }; { a, b } := p; return a + n.at.x; }
EOF
SH="$D/shorthand.c"
check "point { int x; double y; } is the typedef of a struct with that tag and those members" \
  "$(q "cicili('$SH', unit([typedef(1, [var(point, base([], [struct(point, [member(base([], [int]), x, none), member(base([], [double]), y, none)])]), none)])|_])), write(answer(yes)), nl")" "yes"
check "the name is a type inside its own members (node *next) and afterwards (point at); a trailing ; is fine" \
  "$(q "cicili('$SH', unit([_, typedef(2, [var(node, base([], [struct(node, [member(ptr([], base([], [typedef(node)])), next, none), member(base([], [typedef(point)]), at, none)])]), none)])|_])), write(answer(yes)), nl")" "yes"
check "and the types serve a block: a declaration, and a pattern through them" \
  "$(q "cicili('$SH', unit(Is)), member(function(_, _, _, f, _, _, block(B)), Is), member(declaration(_, _, base([], [typedef(point)]), [var(p, _, init(_))]), B), member(declaration(_, _, _, [var(a, base([], [int]), member(id(p), x))]), B), write(answer(yes)), nl")" "yes"

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
