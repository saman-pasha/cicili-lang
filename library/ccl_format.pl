%% cicili-lang -- library(ccl_format): format, print and println, the global
%% macros: in every file, without an include, like `:=' (the parser
%% registers this file at the start of every unit, ccl_standard_macros/0).
%%
%%   println("n = {} name = {name} again {0} p = {p}", n);
%%   s := format("{} + {} = {}", 1, 2, 3);
%%
%% The format string has Rust's holes: `{}' is the next argument, `{0}' the
%% argument at that index (from 0), `{name}' the variable of that name in
%% scope; `{{' and `}}' are braces. Each hole becomes the printf conversion
%% for the inferred type of its argument -- %d %u %ld %lu %lld %llu for the
%% integers, %c for a char, %g for a float or double, %s for a char pointer
%% or array, %p for another pointer -- and a struct (or a typedef of one) is
%% printed as `point_t { x: 1, y: 2.5 }', its members by their own types,
%% nested structs the same way. An argument whose type cannot be inferred or
%% formatted stops the read with cannot_format(Expr).
%%
%%   print(Fmt, Args...)    printf(Fmt', Args')                 a statement
%%   println(Fmt, Args...)  the same with a newline appended
%%   format(Fmt, Args...)   ({ char *b; asprintf(&b, Fmt', Args'); b; })
%%                          an expression of type char *, malloc'd
%%
%% These are DCG macros: the arguments are the list they parse. A predicate
%% named ccl_macro_X is the macro X, so `format' can be a macro although
%% format/2,3 is a builtin.
%%
%%   f(clone(p))            f(({ own T *c = malloc(sizeof(T)); *c = *p; c; }))
%%
%% clone(p), for `own T *p' (or any pointer): a fresh copy of what p points
%% to, a new owner, so a function with an own parameter takes the copy and p
%% stays the caller's (owner's rule). malloc must be declared (stdlib.h). A
%% struct with an own member is refused -- the copy would own the same memory
%% twice -- and so is anything that is not a pointer: cannot_clone(Expr).

ccl_macro_print(call(id(printf), [str(F)|Args])) --> [str(Fmt)], ccl_fmt_args(As), { ccl_fmt_compile(Fmt, As, F, Args) }.
ccl_macro_println(call(id(printf), [str(F)|Args])) --> [str(Fmt)], ccl_fmt_args(As), { ccl_fmt_compile(Fmt, As, F0, Args), append(F0, [10], F) }.
ccl_macro_format(stmt_expr(block([declaration(0, none, base([], [char]), [var(B, ptr([], base([], [char])), none)]),
                                  expr(0, call(id(asprintf), [addr(id(B)), str(F)|Args])),
                                  expr(0, id(B))]))) -->
    [str(Fmt)], ccl_fmt_args(As), { ccl_fmt_compile(Fmt, As, F, Args), ccl_gensym(fmt, B) }.
ccl_fmt_args([A|As]) --> [A], !, ccl_fmt_args(As).
ccl_fmt_args([]) --> [].

%% the format string -> pieces: lit(Codes) | next | index(N) | name(Atom)
ccl_fmt_compile(Fmt, As, F, Args) :-
    ccl_fmt_pieces(Fmt, Pieces),
    ccl_fmt_holes(Pieces, As, 0, F, Args).
ccl_fmt_pieces([], []).
ccl_fmt_pieces([0'{, 0'{|T], [lit([0'{])|Ps]) :- !, ccl_fmt_pieces(T, Ps).
ccl_fmt_pieces([0'}, 0'}|T], [lit([0'}])|Ps]) :- !, ccl_fmt_pieces(T, Ps).
ccl_fmt_pieces([0'{|T], [H|Ps]) :- !, ccl_fmt_hole(T, H, T1), ccl_fmt_pieces(T1, Ps).
ccl_fmt_pieces([0'%|T], [lit([0'%, 0'%])|Ps]) :- !, ccl_fmt_pieces(T, Ps).       % a literal % is %% to printf
ccl_fmt_pieces([C|T], [lit([C])|Ps]) :- ccl_fmt_pieces(T, Ps).
ccl_fmt_hole([0'}|T], next, T) :- !.
ccl_fmt_hole(T, H, Rest) :-
    ccl_fmt_upto_close(T, Inner, Rest),
    ( Inner \== [], ccl_fmt_digits(Inner) -> number_codes(N, Inner), H = index(N) ; atom_codes(A, Inner), H = name(A) ).
ccl_fmt_upto_close([0'}|T], [], T) :- !.
ccl_fmt_upto_close([C|T], [C|Cs], R) :- ccl_fmt_upto_close(T, Cs, R).
ccl_fmt_upto_close([], _, _) :- ccl_macro_error(unclosed_hole).
ccl_fmt_digits([]).
ccl_fmt_digits([D|Ds]) :- D >= 0'0, D =< 0'9, ccl_fmt_digits(Ds).

%% the holes -> conversions and arguments; Next counts the `{}'s
ccl_fmt_holes([], _, _, [], []).
ccl_fmt_holes([lit(Cs)|Ps], As, N, F, Args) :- !, ccl_fmt_holes(Ps, As, N, F1, Args), append(Cs, F1, F).
ccl_fmt_holes([next|Ps], As, N, F, Args) :- !,
    ( ccl_fmt_nth(N, As, E) -> true ; ccl_macro_error(no_argument(N)) ),
    N1 is N + 1, ccl_fmt_conv(E, C, A1), ccl_fmt_holes(Ps, As, N1, F1, Args1), append(C, F1, F), append(A1, Args1, Args).
ccl_fmt_holes([index(I)|Ps], As, N, F, Args) :- !,
    ( ccl_fmt_nth(I, As, E) -> true ; ccl_macro_error(no_argument(I)) ),
    ccl_fmt_conv(E, C, A1), ccl_fmt_holes(Ps, As, N, F1, Args1), append(C, F1, F), append(A1, Args1, Args).
ccl_fmt_holes([name(V)|Ps], As, N, F, Args) :-
    ccl_fmt_conv(id(V), C, A1), ccl_fmt_holes(Ps, As, N, F1, Args1), append(C, F1, F), append(A1, Args1, Args).
ccl_fmt_nth(0, [X|_], X) :- !.
ccl_fmt_nth(N, [_|T], X) :- N > 0, N1 is N - 1, ccl_fmt_nth(N1, T, X).

%% one argument -> its conversion (codes) and the C arguments it needs
ccl_fmt_conv(E, C, Args) :- ccl_type_of(E, T), ( T == unknown -> ccl_macro_error(cannot_format(E)) ; ccl_fmt_conv_t(E, T, C, Args) ).
ccl_fmt_conv_t(E, T, "%s", [E]) :- ccl_fmt_string(T), !.
ccl_fmt_conv_t(E, T, "%c", [E]) :- ccl_resolve_type(T, base(_, [char])), !.
ccl_fmt_conv_t(E, T, "%g", [E]) :- ccl_is_float(T), !.
ccl_fmt_conv_t(E, T, C, [E]) :- ccl_is_integer(T), !, ccl_int_rank(T, R, U),
    ( R =< 3 -> ( U == true -> C = "%u" ; C = "%d" ) ; R == 4 -> ( U == true -> C = "%lu" ; C = "%ld" ) ; U == true -> C = "%llu" ; C = "%lld" ).
ccl_fmt_conv_t(E, T, "%p", [E]) :- ccl_is_pointer(T), !.
ccl_fmt_conv_t(E, T, C, Args) :- ccl_members_of(T, Ms), !,
    ccl_fmt_type_name(T, Name), atom_codes(Name, NC),
    ccl_fmt_members(Ms, E, MC, Args),
    append(NC, " { ", C0), append(C0, MC, C1), append(C1, " }", C).
ccl_fmt_conv_t(E, _, _, _) :- ccl_macro_error(cannot_format(E)).
ccl_fmt_string(T) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, Q) ; T1 = arr(_, Q) ), ccl_resolve_type(Q, base(_, S)), memberchk(char, S), !.
ccl_fmt_type_name(base(_, [typedef(N)]), N) :- !.
ccl_fmt_type_name(base(_, [struct(N, _)]), N) :- N \== anon, !.
ccl_fmt_type_name(base(_, [union(N, _)]), N) :- N \== anon, !.
ccl_fmt_type_name(_, struct).
ccl_fmt_members([], _, [], []).
ccl_fmt_members([member(_, anon, _)|Ms], E, C, Args) :- !, ccl_fmt_members(Ms, E, C, Args).
ccl_fmt_members([member(MT, M, _)|Ms], E, C, Args) :-
    atom_codes(M, MC), ccl_fmt_conv_t(member(E, M), MT, C1, A1),
    ccl_fmt_members(Ms, E, C2, A2),
    ( C2 == [] -> Sep = [] ; Sep = ", " ),
    append(MC, ": ", C0), append(C0, C1, C01), append(C01, Sep, C012), append(C012, C2, C), append(A1, A2, Args).

%% ---- clone --------------------------------------------------------------------
ccl_macro_clone(E, stmt_expr(block([declaration(0, none, Base, [var(C, ptr([own], PT), call(id(malloc), [sizeof_type(PT)]))]),
                                    expr(0, assign('=', deref(id(C)), deref(E))),
                                    expr(0, id(C))]))) :-
    ccl_type_of(E, T),
    ( ccl_resolve_type(T, ptr(_, PT0)) -> true ; ccl_macro_error(cannot_clone(E)) ),
    ( ccl_has_own_member(PT0) -> ccl_macro_error(cannot_clone_own_members(E)) ; true ),
    ( ccl_declared(malloc, _) -> true ; ccl_macro_error(clone_needs_malloc) ),
    ccl_clone_pointee(PT0, PT), ccl_base_of(PT, Base), ccl_gensym(clone, C).
ccl_clone_pointee(base(Q0, S), base(Q, S)) :- !, ccl_clone_del(own, Q0, Q).       % the copy is own on the pointer
ccl_clone_pointee(T, T).
ccl_clone_del(_, [], []).
ccl_clone_del(X, [X|T], T1) :- !, ccl_clone_del(X, T, T1).
ccl_clone_del(X, [Y|T], [Y|T1]) :- ccl_clone_del(X, T, T1).
