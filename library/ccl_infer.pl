%% cicili-lang -- library(ccl_infer): what a macro can ask, as the parser
%% stands at the call. The parser (library(ccl_syntax)) keeps the scope of
%% declared names, the typedef definitions and the struct tags as it reads;
%% a macro predicate from an included .pl runs at that point and may ask:
%%
%%   ccl_type_of(+Expr, -Type)        the type of an expression AST, or unknown
%%   ccl_resolve_type(+T, -T1)        typedef names unwrapped, a tag's members filled
%%   ccl_declared(+Name, -Type)       a name in scope, innermost first
%%   ccl_typedef_of(+Name, -Type)     a typedef's definition
%%   ccl_tag(+Tag, -Members)          a struct/union's members, an enum's enumerators
%%   ccl_members_of(+Type, -Members)  the members of a struct or union type
%%   ccl_member_type(+Type, +Name, -T)
%%   ccl_is_integer(+T) ccl_is_float(+T) ccl_is_arith(+T) ccl_is_pointer(+T)
%%   ccl_size_of(+T, -Bytes)          LP64: char 1 short 2 int 4 long 8 float 4 double 8 pointer 8
%%   ccl_scope(-Frames)               every frame, innermost first
%%   ccl_gensym(+Prefix, -Atom)       a fresh identifier for a macro's temporary
%%   ccl_here(-File, -Line)           where the parser is
%%   ccl_macro_error(+Message)        stop the read with a message and the place
%%
%% Types are the AST's: base(Quals, Specs), ptr(Quals, T), arr(Size, T),
%% fn(Ret, Params, Variadic), block(Quals, T); and unknown.

%% every catch here is once/1: a bare catch that succeeds leaves a frame a
%% later throw runs (a cocolog finding, in CLAUDE.md)
ccl_scope(Fs) :- once(catch(nb_getval('$ccl_scope', Fs), _, Fs = [[]])).
ccl_declared(N, T) :- ccl_scope(Fs), ccl_in_frames(Fs, N, T).
ccl_in_frames([F|Fs], N, T) :- ( memberchk(N-T0, F) -> T = T0 ; ccl_in_frames(Fs, N, T) ).
ccl_typedef_of(N, T) :- once(catch(nb_getval('$ccl_typedefs', L), _, fail)), memberchk(N-T, L).
ccl_tag(Tag, Ms) :- once(catch(nb_getval('$ccl_tags', L), _, fail)), memberchk(Tag-Ms, L).

ccl_here(File, Line) :- once(catch(nb_getval('$ccl_file', File), _, File = none)), once(catch(nb_getval('$ccl_far', Line), _, Line = 0)).
ccl_gensym(Prefix, Atom) :-
    ( catch(nb_getval('$ccl_gensym', N0), _, fail) -> true ; N0 = 0 ), N is N0 + 1, nb_setval('$ccl_gensym', N),
    atomic_list_concat([Prefix, '_', N], Atom).
ccl_macro_error(Msg) :- ccl_here(F, L), throw(error(macro_error(Msg, here(F, L)), _)).

%% ---- resolving ------------------------------------------------------------------
ccl_resolve_type(base(Q, [typedef(N)]), T) :- ccl_typedef_of(N, T0), !, ccl_resolve_type(T0, T1), ccl_add_quals(Q, T1, T).
ccl_resolve_type(base(Q, [struct(Tag, none)]), base(Q, [struct(Tag, Ms)])) :- ccl_tag(Tag, Ms), !.
ccl_resolve_type(base(Q, [union(Tag, none)]), base(Q, [union(Tag, Ms)])) :- ccl_tag(Tag, Ms), !.
ccl_resolve_type(T, T).
ccl_add_quals([], T, T) :- !.
ccl_add_quals(Q, base(Q0, S), base(Q1, S)) :- !, append(Q, Q0, Q1).
ccl_add_quals(Q, ptr(Q0, T), ptr(Q1, T)) :- !, append(Q, Q0, Q1).
ccl_add_quals(_, T, T).
ccl_members_of(T, Ms) :- ccl_resolve_type(T, T1), ( T1 = base(_, [struct(_, Ms)]) ; T1 = base(_, [union(_, Ms)]) ), Ms \== none, !.
ccl_member_type(T, N, MT) :- ccl_members_of(T, Ms), memberchk(member(MT, N, _), Ms).

%% ---- classes ----------------------------------------------------------------------
ccl_is_pointer(T) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, _) ; T1 = arr(_, _) ; T1 = block(_, _) ), !.
ccl_is_float(T) :- ccl_resolve_type(T, base(_, S)), ( memberchk(double, S) ; memberchk(float, S) ), !.
ccl_is_integer(T) :- ccl_resolve_type(T, base(_, S)), \+ memberchk(double, S), \+ memberchk(float, S), \+ memberchk(void, S),
    ( memberchk(int, S) ; memberchk(char, S) ; memberchk(short, S) ; memberchk(long, S) ; memberchk(signed, S)
    ; memberchk(unsigned, S) ; memberchk('_Bool', S) ; S = [enum(_, _)] ), !.
ccl_is_arith(T) :- ( ccl_is_integer(T) ; ccl_is_float(T) ), !.

%% integer rank and signedness, for the usual arithmetic conversions
ccl_int_rank(T, Rank, Unsigned) :-
    ccl_resolve_type(T, base(_, S)),
    ( memberchk(unsigned, S) -> Unsigned = true ; Unsigned = false ),
    ( ccl_count(long, S, 2) -> Rank = 5 ; memberchk(long, S) -> Rank = 4 ; memberchk(short, S) -> Rank = 2
    ; memberchk(char, S) -> Rank = 1 ; memberchk('_Bool', S) -> Rank = 0 ; Rank = 3 ).
ccl_count(_, [], 0).
ccl_count(X, [Y|T], N) :- ccl_count(X, T, N0), ( X == Y -> N is N0 + 1 ; N = N0 ).
ccl_promote(T, P) :- ( ccl_int_rank(T, R, _), R < 3 -> P = base([], [int]) ; P = T ).
ccl_usual(A, B, T) :-
    (   ccl_is_float(A), ccl_is_float(B) -> ( ccl_resolve_type(A, base(_, SA)), memberchk(double, SA) -> T = A ; T = B )
    ;   ccl_is_float(A) -> T = A
    ;   ccl_is_float(B) -> T = B
    ;   ccl_is_integer(A), ccl_is_integer(B) ->
            ccl_promote(A, PA), ccl_promote(B, PB), ccl_int_rank(PA, RA, UA), ccl_int_rank(PB, RB, UB),
            ( RA > RB -> T = PA ; RB > RA -> T = PB ; UA == true -> T = PA ; UB == true -> T = PB ; T = PA )
    ;   T = unknown ).
ccl_size_type(T) :- ( ccl_typedef_of(size_t, _) -> T = base([], [typedef(size_t)]) ; T = base([], [unsigned, long]) ).

%% ---- the type of an expression ----------------------------------------------------
ccl_type_of(int(_), base([], [int])) :- !.
ccl_type_of(float(_), base([], [double])) :- !.
ccl_type_of(chr(_), base([], [int])) :- !.
ccl_type_of(str(_), ptr([], base([], [char]))) :- !.
ccl_type_of(id(N), T) :- !, ( ccl_declared(N, T0) -> T = T0 ; T = unknown ).
ccl_type_of(call(F, _), T) :- !,
    (   F = id(N), ccl_declared(N, fn(R, _, _)) -> T = R
    ;   ccl_type_of(F, FT), ccl_resolve_type(FT, FT1),
        ( FT1 = fn(R, _, _) -> T = R ; FT1 = ptr(_, fn(R, _, _)) -> T = R ; FT1 = block(_, fn(R, _, _)) -> T = R ; T = unknown ) ).
ccl_type_of(member(E, N), T) :- !, ccl_type_of(E, ET), ( ccl_member_type(ET, N, T0) -> T = T0 ; T = unknown ).
ccl_type_of(arrow(E, N), T) :- !, ccl_type_of(E, ET), ccl_resolve_type(ET, ET1),
    ( ( ET1 = ptr(_, ST) ; ET1 = arr(_, ST) ), ccl_member_type(ST, N, T0) -> T = T0 ; T = unknown ).
ccl_type_of(index(A, _), T) :- !, ccl_type_of(A, AT), ccl_resolve_type(AT, AT1), ( ( AT1 = ptr(_, T0) ; AT1 = arr(_, T0) ) -> T = T0 ; T = unknown ).
ccl_type_of(deref(E), T) :- !, ccl_type_of(E, ET), ccl_resolve_type(ET, ET1), ( ( ET1 = ptr(_, T0) ; ET1 = arr(_, T0) ) -> T = T0 ; T = unknown ).
ccl_type_of(addr(E), T) :- !, ccl_type_of(E, ET), ( ET == unknown -> T = unknown ; T = ptr([], ET) ).
ccl_type_of(neg(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(pos(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(bitnot(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(not(_), base([], [int])) :- !.
ccl_type_of(preinc(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(predec(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(postinc(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(postdec(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(sizeof(_), T) :- !, ccl_size_type(T).
ccl_type_of(sizeof_type(_), T) :- !, ccl_size_type(T).
ccl_type_of(cast(T, _), T) :- !.
ccl_type_of(compound_lit(T, _), T) :- !.
ccl_type_of(assign(_, L, _), T) :- !, ccl_type_of(L, T).
ccl_type_of(comma(_, B), T) :- !, ccl_type_of(B, T).
ccl_type_of(cond(_, A, B), T) :- !, ccl_type_of(A, AT), ccl_type_of(B, BT),
    ( ccl_is_arith(AT), ccl_is_arith(BT) -> ccl_usual(AT, BT, T) ; AT \== unknown -> T = AT ; T = BT ).
ccl_type_of(stmt_expr(block(Is)), T) :- !,            % its declarations are in scope for its last expression
    ccl_scope_push, ccl_note_items(Is),
    ( append(_, [expr(E)], Is) -> ccl_type_of(E, T) ; T = base([], [void]) ),
    ccl_scope_pop.
ccl_type_of(bin(Op, A, B), T) :- !,
    ccl_type_of(A, AT), ccl_type_of(B, BT),
    (   memberchk(Op, ['<', '>', '<=', '>=', '==', '!=', '&&', '||']) -> T = base([], [int])
    ;   memberchk(Op, ['<<', '>>']) -> ccl_promoted_or_unknown(AT, T)
    ;   memberchk(Op, ['+', '-']), ccl_is_pointer(AT), ccl_is_pointer(BT) -> T = base([], [long])
    ;   memberchk(Op, ['+', '-']), ccl_is_pointer(AT) -> ccl_decay(AT, T)
    ;   Op == '+', ccl_is_pointer(BT) -> ccl_decay(BT, T)
    ;   ccl_is_arith(AT), ccl_is_arith(BT) -> ccl_usual(AT, BT, T)
    ;   T = unknown ).
ccl_type_of(_, unknown).
ccl_promoted_or_unknown(ET, T) :- ( ccl_is_integer(ET) -> ccl_promote(ET, T) ; ccl_is_float(ET) -> T = ET ; T = unknown ).
%% an array decays to a pointer to its element, a function to a pointer to
%% itself; anything else keeps its name (a typedef stays a typedef)
ccl_decay(T, D) :- ccl_resolve_type(T, T1), ( T1 = arr(_, E) -> D = ptr([], E) ; T1 = fn(_, _, _) -> D = ptr([], T1) ; D = T ).

%% ---- sizes, LP64 ---------------------------------------------------------------------
ccl_size_of(T, N) :- ccl_resolve_type(T, T1), ccl_size_align(T1, N, _).
ccl_size_align(ptr(_, _), 8, 8) :- !.
ccl_size_align(block(_, _), 8, 8) :- !.
ccl_size_align(fn(_, _, _), 8, 8) :- !.
ccl_size_align(arr(int(K), E), N, A) :- !, ccl_size_align(E, EN, A), N is K * EN.
ccl_size_align(base(_, S), N, A) :- ccl_basic_size(S, N), !, A = N.
ccl_size_align(base(_, [struct(_, Ms)]), N, A) :- Ms \== none, !, ccl_struct_layout(Ms, 0, 1, N, A).
ccl_size_align(base(_, [union(_, Ms)]), N, A) :- Ms \== none, !, ccl_union_layout(Ms, 0, 1, N, A).
ccl_size_align(base(_, [enum(_, _)]), 4, 4) :- !.
ccl_basic_size(S, N) :- ( memberchk(double, S) -> N = 8 ; memberchk(float, S) -> N = 4 ; ccl_count(long, S, 2) -> N = 8
    ; memberchk(long, S) -> N = 8 ; memberchk(short, S) -> N = 2 ; memberchk(char, S) -> N = 1 ; memberchk('_Bool', S) -> N = 1
    ; memberchk(int, S) -> N = 4 ; memberchk(unsigned, S) -> N = 4 ; memberchk(signed, S) -> N = 4 ; memberchk(void, S) -> N = 1 ; fail ).
ccl_struct_layout([], Off, Al, N, Al) :- ccl_round_up(Off, Al, N).
ccl_struct_layout([member(T, _, _)|Ms], Off0, Al0, N, Al) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), ccl_round_up(Off0, A, Off1), Off2 is Off1 + S, Al1 is max(Al0, A),
    ccl_struct_layout(Ms, Off2, Al1, N, Al).
ccl_union_layout([], S, Al, N, Al) :- ccl_round_up(S, Al, N).
ccl_union_layout([member(T, _, _)|Ms], S0, Al0, N, Al) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), S1 is max(S0, S), Al1 is max(Al0, A), ccl_union_layout(Ms, S1, Al1, N, Al).
ccl_round_up(X, A, Y) :- Y is ((X + A - 1) // A) * A.
