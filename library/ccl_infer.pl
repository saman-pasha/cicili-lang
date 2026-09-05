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
%%   ccl_enum_value(+Name, -Int)      an enumerator's value
%%   ccl_const_eval(+Expr, -Int)      an integer constant expression, folded as C folds it
%%   ccl_scope(-Frames)               every frame, innermost first
%%   ccl_gensym(+Prefix, -Atom)       a fresh identifier for a macro's temporary
%%   ccl_here(-File, -Line)           where the parser is
%%   ccl_macro_error(+Message)        stop the read with a message and the place
%%
%% Types are the AST's: base(Quals, Specs), ptr(Quals, T), arr(Size, T),
%% fn(Ret, Params, Variadic), block(Quals, T); and unknown.

%% no catch on a read of a global here: the keys are set once per process
%% (ccl_ensure_globals/0, library(ccl_include)), and a catch costs in
%% proportion to the terms bound inside it (a cocolog finding, in CLAUDE.md)
ccl_scope(Fs) :- nb_getval('$ccl_scope', Fs).                        % set by ccl_scope_init; bare: a catch would copy it
ccl_declared(N, T) :- ccl_scope(Fs), ccl_in_frames(Fs, N, T).
ccl_in_frames([F|Fs], N, T) :- ( memberchk(N-T0, F) -> T = T0 ; ccl_in_frames(Fs, N, T) ).
ccl_typedef_of(N, T) :- nb_getval('$ccl_typedefs', L), memberchk(N-T, L).
ccl_tag(Tag, Ms) :- nb_getval('$ccl_tags', L), memberchk(Tag-Ms, L).

%% ---- constants ---------------------------------------------------------------------
ccl_enum_value(N, V) :- nb_getval('$ccl_enums', L), memberchk(N-V, L).
%% an integer constant expression, as C folds it
ccl_const_eval(int(N), N) :- !.
ccl_const_eval(chr(C), C) :- !.
ccl_const_eval(id(N), V) :- !, ccl_enum_value(N, V).
ccl_const_eval(neg(E), V) :- !, ccl_const_eval(E, V0), V is -V0.
ccl_const_eval(pos(E), V) :- !, ccl_const_eval(E, V).
ccl_const_eval(bitnot(E), V) :- !, ccl_const_eval(E, V0), V is \ V0.
ccl_const_eval(not(E), V) :- !, ccl_const_eval(E, V0), ( V0 =:= 0 -> V = 1 ; V = 0 ).
ccl_const_eval(cast(_, E), V) :- !, ccl_const_eval(E, V).
ccl_const_eval(sizeof_type(T), V) :- !, ccl_size_of(T, V).
ccl_const_eval(sizeof(E), V) :- !, ccl_type_of(E, T), ccl_size_of(T, V).
ccl_const_eval(cond(C, A, B), V) :- !, ccl_const_eval(C, CV), ( CV =\= 0 -> ccl_const_eval(A, V) ; ccl_const_eval(B, V) ).
ccl_const_eval(bin(Op, A, B), V) :- ccl_const_eval(A, X), ccl_const_eval(B, Y), ccl_const_op(Op, X, Y, V).
ccl_const_op('+', X, Y, V) :- V is X + Y.
ccl_const_op('-', X, Y, V) :- V is X - Y.
ccl_const_op('*', X, Y, V) :- V is X * Y.
ccl_const_op('/', X, Y, V) :- Y =\= 0, V is X // Y.
ccl_const_op('%', X, Y, V) :- Y =\= 0, V is X mod Y.
ccl_const_op('<<', X, Y, V) :- V is X << Y.
ccl_const_op('>>', X, Y, V) :- V is X >> Y.
ccl_const_op('&', X, Y, V) :- V is X /\ Y.
ccl_const_op('|', X, Y, V) :- V is X \/ Y.
ccl_const_op('^', X, Y, V) :- V is xor(X, Y).
ccl_const_op('<', X, Y, V) :- ( X < Y -> V = 1 ; V = 0 ).
ccl_const_op('>', X, Y, V) :- ( X > Y -> V = 1 ; V = 0 ).
ccl_const_op('<=', X, Y, V) :- ( X =< Y -> V = 1 ; V = 0 ).
ccl_const_op('>=', X, Y, V) :- ( X >= Y -> V = 1 ; V = 0 ).
ccl_const_op('==', X, Y, V) :- ( X =:= Y -> V = 1 ; V = 0 ).
ccl_const_op('!=', X, Y, V) :- ( X =\= Y -> V = 1 ; V = 0 ).
ccl_const_op('&&', X, Y, V) :- ( X =\= 0, Y =\= 0 -> V = 1 ; V = 0 ).
ccl_const_op('||', X, Y, V) :- ( ( X =\= 0 ; Y =\= 0 ) -> V = 1 ; V = 0 ).

ccl_here(File, Line) :- ccl_ensure_globals, nb_getval('$ccl_file', File), nb_getval('$ccl_far', Line).
ccl_gensym(Prefix, Atom) :-
    ccl_ensure_globals, nb_getval('$ccl_gensym', N0), N is N0 + 1, nb_setval('$ccl_gensym', N),
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
ccl_type_of(move(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(compound_lit(T, _), T) :- !.
ccl_type_of(assign(_, L, _), T) :- !, ccl_type_of(L, T).
ccl_type_of(comma(_, B), T) :- !, ccl_type_of(B, T).
ccl_type_of(cond(_, A, B), T) :- !, ccl_type_of(A, AT), ccl_type_of(B, BT),
    ( ccl_is_arith(AT), ccl_is_arith(BT) -> ccl_usual(AT, BT, T) ; AT \== unknown -> T = AT ; T = BT ).
ccl_type_of(stmt_expr(block(Is)), T) :- !,            % its declarations are in scope for its last expression
    ccl_scope_push, ccl_note_items(Is),
    ( append(_, [expr(_, E)], Is) -> ccl_type_of(E, T) ; T = base([], [void]) ),
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
ccl_size_align(arr(NE, E), N, A) :- !, ccl_size_align(E, EN, A), ( ccl_const_eval(NE, K) -> N is K * EN ; N = 0 ).   % a flexible member, `T a[]' or `own T *a[n]': no bytes of its own
ccl_size_align(base(_, S), N, A) :- ccl_basic_size(S, N), !, A = N.
ccl_size_align(base(_, [struct(_, Ms)]), N, A) :- Ms \== none, !, ccl_struct_layout(Ms, 0, 1, N, A).
ccl_size_align(base(_, [union(_, Ms)]), N, A) :- Ms \== none, !, ccl_union_layout(Ms, 0, 1, N, A).
ccl_size_align(base(_, [enum(_, _)]), 4, 4) :- !.
ccl_basic_size(S, N) :- ( memberchk(double, S) -> N = 8 ; memberchk(float, S) -> N = 4 ; ccl_count(long, S, 2) -> N = 8
    ; memberchk(long, S) -> N = 8 ; memberchk(short, S) -> N = 2 ; memberchk(char, S) -> N = 1 ; memberchk('_Bool', S) -> N = 1
    ; memberchk(int, S) -> N = 4 ; memberchk(unsigned, S) -> N = 4 ; memberchk(signed, S) -> N = 4 ; memberchk(void, S) -> N = 1 ; fail ).
ccl_struct_layout(Ms, _, _, N, Al) :- ccl_members_layout(Ms, _, N, Al).
%% ccl_members_layout(+Members, -Lays, -Size, -Align): where every member lies --
%% lay(Name, T, ByteOff, none) for a plain member, lay(Name, T, UnitByteOff,
%% bits(BitOffInUnit, Width, UnitBytes)) for a bitfield. The packing is the
%% SysV one (clang's): a bitfield lands at the next bit unless it would cross
%% a boundary of its declared type's alignment, then at that boundary; a zero
%% width closes the unit; a plain member is aligned as usual; the struct's
%% alignment counts every member's, a bitfield's declared type included.
ccl_members_layout(Ms, Lays, Size, Align) :- ccl_members_layout_(Ms, 0, 1, Lays, Bits, Align), Bytes is (Bits + 7) // 8, ccl_round_up(Bytes, Align, Size).
ccl_members_layout_([], Bits, Al, [], Bits, Al).
ccl_members_layout_([member(T, N, W0)|Ms], Bit0, Al0, Lays, Bits, Al) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), ABits is A * 8,
    (   W0 == none
    ->  ccl_round_up(Bit0, ABits, B1), Off is B1 // 8, Bit1 is B1 + S * 8, Al1 is max(Al0, A),
        Lays = [lay(N, T, Off, none)|Lays1]
    ;   ccl_bit_width(W0, W),
        (   W =:= 0 -> ccl_round_up(Bit0, ABits, Bit1), Al1 = Al0, Lays = Lays1
        ;   ( (Bit0 mod ABits) + W > ABits -> ccl_round_up(Bit0, ABits, Start) ; Start = Bit0 ),
            UnitStart is (Start // ABits) * ABits, Off is UnitStart // 8, BOff is Start - UnitStart,
            Bit1 is Start + W, Al1 is max(Al0, A),
            Lays = [lay(N, T, Off, bits(BOff, W, S))|Lays1] ) ),
    ccl_members_layout_(Ms, Bit1, Al1, Lays1, Bits, Al).
ccl_bit_width(int(W), W) :- !.
ccl_bit_width(W, W) :- integer(W), !.
ccl_bit_width(E, W) :- ccl_const_eval(E, W).
ccl_union_layout([], S, Al, N, Al) :- ccl_round_up(S, Al, N).
ccl_union_layout([member(T, _, _)|Ms], S0, Al0, N, Al) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), S1 is max(S0, S), Al1 is max(Al0, A), ccl_union_layout(Ms, S1, Al1, N, Al).
ccl_round_up(X, A, Y) :- Y is ((X + A - 1) // A) * A.

%% ---- the tie operator, `<*>' --------------------------------------------------
%% `x <*> y' declares x to live within y. The reader keeps it as the qualifier
%% tie(Y) in the OUTERMOST qualifier list of x's type -- through an array to
%% its element, through a function to its result, which is how a result is
%% tied to a parameter. The check reads it (library(ccl_check)); the lowering
%% and the layout never look at a qualifier, so it costs them nothing.
ccl_add_tie(Y, base(Q, S), base([tie(Y)|Q], S)) :- !.
ccl_add_tie(Y, ptr(Q, T), ptr([tie(Y)|Q], T)) :- !.
ccl_add_tie(Y, block(Q, T), block([tie(Y)|Q], T)) :- !.
ccl_add_tie(Y, arr(N, T0), arr(N, T)) :- !, ccl_add_tie(Y, T0, T).
ccl_add_tie(Y, fn(R0, Ps, V), fn(R, Ps, V)) :- !, ccl_add_tie(Y, R0, R).
ccl_add_tie(_, T, T).
ccl_tie_of(base(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(ptr(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(block(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(arr(_, T), Y) :- !, ccl_tie_of(T, Y).
ccl_tie_of(fn(R, _, _), Y) :- !, ccl_tie_of(R, Y).
%% a struct (or union) with an own member, at any depth held by value: its copy
%% would own the same memory twice, so clone refuses it
ccl_has_own_member(T) :- ccl_members_of(T, Ms), member(member(MT, _, _), Ms), ( ccl_own_quals(MT) -> true ; ccl_has_own_member(MT) ), !.
ccl_own_quals(ptr(Q, B)) :- ( memberchk(own, Q) ; B = base(Q2, _), memberchk(own, Q2) ), !.
ccl_own_quals(base(Q, _)) :- memberchk(own, Q), !.
ccl_own_quals(arr(_, T)) :- ccl_own_quals(T), !.
