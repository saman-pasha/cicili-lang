/* type inference inside a #cocolog macro: ccl_type_of/2 answers an argument's
   C type from the scope as it stands, and the macro shapes its expansion by
   it -- a conversion chosen by type, a temporary declared with the type, a
   size folded at read time */
#include <stdio.h>
#cocolog
%% show(e): printf with the conversion e's type asks for
show(E, call(id(printf), [str(F), E])) :- ccl_type_of(E, T), conv(T, C), atom_codes(C, Cs), append(Cs, [10], F).
conv(T, '%s') :- ccl_resolve_type(T, ptr(_, base(_, [char]))), !.
conv(T, '%g') :- ccl_is_float(T), !.
conv(T, '%ld') :- ccl_resolve_type(T, base(_, S)), memberchk(long, S), !.
conv(T, '%d') :- ccl_is_integer(T), !.
conv(_, '%p').
%% swap(a, b): through a temporary of a's own type
swap(A, B, block([declaration(0, none, Base, [var(Tmp, T, A)]), expr(0, assign('=', A, B)), expr(0, assign('=', B, id(Tmp)))])) :-
    ccl_type_of(A, T), ccl_base_of(T, Base), ccl_gensym(swap, Tmp).
%% bytes(e): sizeof e's type, a constant at read time
bytes(E, int(N)) :- ccl_type_of(E, T), ccl_size_of(T, N).
#end
int main(void) {
    int a = 3, b = 4;
    long big = 1234567890123;
    double d = 2.5;
    const char *s = "hi";
    show(a); show(big); show(d); show(s);
    swap(a, b);
    show(a);
    printf("%d %d %d\n", bytes(a), bytes(d), bytes(s));
    return 0;
}
