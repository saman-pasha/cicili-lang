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
freeit(P, expr(call(id(free), [P]))).
calls_missing(_, R) :- no_such_predicate(R).
