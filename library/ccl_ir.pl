%% cicili-lang -- library(ccl_ir): the lowering. cicili_ir(+Units, -IR) takes
%% the ASTs cicili_ast/2 answers and gives an LLVM IR module as text.
%%
%% The symbol table is rebuilt from the units the way the parser builds it
%% (ccl_note_item/1, library(ccl_syntax)), so the lowering types every
%% expression with ccl_type_of/2 (library(ccl_infer)) -- the same inference
%% the macros and `:=' use -- and lays structs out with ccl_size_of/2.
%%
%% One clause per construct: ir_stmt/1 for statements, ir_expr/3 for an
%% expression's value and C type, ir_lval/3 for an address. Locals are
%% allocas in the entry block (mem2reg lifts them); conversions follow C's
%% usual arithmetic conversions; `defer' is the static cleanup chain: every
%% exit of a scope -- its end, a return, a break or continue -- runs the
%% scope's defers last-registered-first, inline on that path.
%%
%% What lowers today (M2): functions and prototypes; globals with constant
%% initializers; int, char, short, long, float, double, pointers, arrays,
%% structs, typedefs, enums; declarations with initializers; if, while, do,
%% for, switch, return, break, continue, goto, defer; every operator, calls
%% (variadic too), casts, sizeof, ?:, the comma, compound literals,
%% statement expressions. Not yet: bitfields, unions, static locals, VLAs,
%% long double, _Complex -- each throws error(not_lowered(What), where(F)).
%%
%% THE SURFACE:
%%   ccl_ir_units(+Units, -IR)     IR the module text, an atom
%%   ccl_ir_function(+Item, -Text) one function, for the curious

:- use_module(library(ccl_infer)).
:- use_module(library(ccl_check)).

ccl_ir_units(Units, IR) :-
    ir_reset, ccl_scope_init, ir_note_units(Units),                     % the symbol table, once
    ccl_check_noted(Units),                                             % the safe part first: a violation is a compile error
    nb_setval('$ir_fdefs', []), nb_setval('$ir_gdefs', []),
    ir_units(Units),
    ir_assemble(IR).

ir_note_units([]).
ir_note_units([unit(Is)|Us]) :- ccl_items_note(Is), ir_note_units(Us).

ir_units([]).
ir_units([unit(Is)|Us]) :- ir_items(Is), ir_units(Us).
ir_items([]).
ir_items([I|Is]) :- ir_item(I), ir_items(Is).

%% ---- state -----------------------------------------------------------------------
ir_reset :-
    ( once(catch(os_env('CCL_IR_TRACE', Tr), _, fail)), Tr \== '' -> nb_setval('$ir_trace', yes) ; nb_setval('$ir_trace', no) ),
    nb_setval('$ir_reg', 0), nb_setval('$ir_anons', []), nb_setval('$ir_strings', []), nb_setval('$ir_structs', []),
    nb_setval('$ir_externs', []), nb_setval('$ir_defined', []), nb_setval('$ir_gmap', []).
ir_get(K, V) :- once(catch(nb_getval(K, V), _, fail)).
ir_fresh(R) :- nb_getval('$ir_reg', N), N1 is N + 1, nb_setval('$ir_reg', N1), atomic_list_concat(['%t', N1], R).
ir_label(L) :- nb_getval('$ir_reg', N), N1 is N + 1, nb_setval('$ir_reg', N1), atomic_list_concat(['L', N1], L).
ir_emit(Parts) :-
    ( ir_get('$ir_trace', yes) -> write('| '), write(Parts), nl ; true ),          % CCL_IR_TRACE=1: every line as it is emitted
    atomic_list_concat(Parts, Line), nb_getval('$ir_body', B), nb_setval('$ir_body', [Line|B]).
ir_terminated(T) :- nb_getval('$ir_term', T).
ir_set_term(T) :- nb_setval('$ir_term', T).
%% an instruction: a terminated block gets a fresh (dead) label first
ir_ins(Parts) :- ( ir_terminated(yes) -> ir_label(L), ir_emit([L, ':']), ir_set_term(no) ; true ), ir_emit(['  '|Parts]).
%% a terminator
ir_end(Parts) :- ( ir_terminated(yes) -> true ; ir_emit(['  '|Parts]), ir_set_term(yes) ).
%% a block starts: fall in from the block before unless it ended
ir_block(L) :- ( ir_terminated(yes) -> true ; ir_emit(['  br label %', L]) ), ir_emit([L, ':']), ir_set_term(no).
ir_alloca(R, LL) :- nb_getval('$ir_allocas', A), atomic_list_concat(['  ', R, ' = alloca ', LL], Line), nb_setval('$ir_allocas', [Line|A]).
ir_where(W) :- ir_get('$ir_fn', W0), !, W = W0.
ir_where(file).
ir_fail(What) :- ir_where(W), throw(error(not_lowered(What), where(W))).

%% ---- the environment: locals in frames, then the globals, then the table ------------
ir_env_push :- nb_getval('$ir_env', E), nb_setval('$ir_env', [[]|E]), nb_getval('$ir_defers', D), nb_setval('$ir_defers', [[]|D]), ccl_scope_push.
ir_env_pop :- nb_getval('$ir_env', [_|E]), nb_setval('$ir_env', E), nb_getval('$ir_defers', [_|D]), nb_setval('$ir_defers', D), ccl_scope_pop.
ir_local(N, T, Addr) :- nb_getval('$ir_env', [F|E]), nb_setval('$ir_env', [[N-loc(Addr, T)|F]|E]), ccl_declare(N, T).
ir_lookup(N, loc(Addr, T)) :- nb_getval('$ir_env', E), ir_in_frames(E, N, loc(Addr, T)), !.
ir_lookup(N, loc(Addr, T)) :- nb_getval('$ir_gmap', G), memberchk(N-T, G), !, atom_concat('@', N, Addr).
ir_lookup(N, loc(Addr, T)) :- ccl_declared(N, T), !, atom_concat('@', N, Addr), ir_note_extern(N, T).
ir_in_frames([F|Fs], N, L) :- ( memberchk(N-L0, F) -> L = L0 ; ir_in_frames(Fs, N, L) ).
ir_note_extern(N, T) :- nb_getval('$ir_externs', Es), ( memberchk(N-_, Es) -> true ; nb_setval('$ir_externs', [N-T|Es]) ).
ir_defer_push(Body) :- nb_getval('$ir_defers', [F|D]), nb_setval('$ir_defers', [[Body|F]|D]).
%% run the defers of the innermost K frames (all, for a return), each frame LIFO
ir_run_defers(all) :- !, nb_getval('$ir_defers', D), ir_run_frames(D).
ir_run_defers(K) :- nb_getval('$ir_defers', D), ir_take(K, D, Fs), ir_run_frames(Fs).
ir_run_frames([]).
ir_run_frames([F|Fs]) :- ir_run_bodies(F), ir_run_frames(Fs).
ir_run_bodies([]).
ir_run_bodies([B|Bs]) :- ir_stmt(B), ir_run_bodies(Bs).
ir_take(0, _, []) :- !.
ir_take(_, [], []) :- !.
ir_take(K, [F|Fs], [F|Gs]) :- K1 is K - 1, ir_take(K1, Fs, Gs).
ir_depth(K) :- nb_getval('$ir_defers', D), length(D, K).

%% ---- types -------------------------------------------------------------------------
ir_type(T, LL) :- ccl_resolve_type(T, T1), ir_type_(T1, LL).
ir_type_(base(_, S), LL) :- !, ir_base(S, LL).
ir_type_(ptr(_, _), ptr) :- !.
ir_type_(block(_, _), ptr) :- !.
ir_type_(fn(_, _, _), ptr) :- !.
ir_type_(arr(int(N), E), LL) :- !, ir_type(E, EL), atomic_list_concat(['[', N, ' x ', EL, ']'], LL).
ir_type_(arr(_, _), ptr) :- !.
ir_type_(T, _) :- ir_fail(type(T)).
ir_base(S, void) :- memberchk(void, S), !.
ir_base(S, double) :- memberchk(double, S), !.
ir_base(S, float) :- memberchk(float, S), !.
ir_base(S, i8) :- ( memberchk(char, S) ; memberchk('_Bool', S) ), !.
ir_base(S, i16) :- memberchk(short, S), !.
ir_base(S, i64) :- memberchk(long, S), !.
ir_base(S, i32) :- ( memberchk(int, S) ; memberchk(unsigned, S) ; memberchk(signed, S) ), !.
ir_base([enum(_, _)], i32) :- !.
ir_base([struct(Tag, Ms)], LL) :- !, ir_struct(Tag, Ms, LL).
ir_base([union(_, Ms)], LL) :- !, ( Ms == none -> ir_fail(union) ; ccl_union_layout(Ms, 0, 1, N, _), atomic_list_concat(['[', N, ' x i8]'], LL) ).
ir_base([typedef(N)], _) :- !, ir_fail(typedef(N)).
ir_base(S, _) :- ir_fail(specs(S)).
%% a struct type is named once; the members are laid out in order
ir_struct(Tag, Ms0, Name) :-
    ( Ms0 == none -> ( ccl_tag(Tag, Ms) -> true ; ir_fail(struct(Tag)) ) ; Ms = Ms0 ),
    ( Tag == anon -> ir_anon_name(Ms, Name) ; atom_concat('%struct.', Tag, Name) ),
    nb_getval('$ir_structs', Ss),
    (   memberchk(Name-_, Ss) -> true
    ;   nb_setval('$ir_structs', [Name-pending|Ss]),
        ir_member_types(Ms, LLs), ir_join(LLs, ', ', Body),
        atomic_list_concat([Name, ' = type { ', Body, ' }'], Def),
        nb_getval('$ir_structs', Ss1), ir_replace(Ss1, Name, Def, Ss2), nb_setval('$ir_structs', Ss2) ).
%% an anonymous struct is named by its members, in a registry of its own --
%% not in '$ir_structs', where a name means "defined"
ir_anon_name(Ms, Name) :-
    ir_get('$ir_anons', As0), !, As = As0,
    ( member(N-Ms0, As), Ms0 == Ms -> Name = N
    ; length(As, K), atomic_list_concat(['%struct.anon.', K], Name), nb_setval('$ir_anons', [Name-Ms|As]) ).
ir_anon_name(Ms, Name) :- nb_setval('$ir_anons', []), ir_anon_name(Ms, Name).
ir_replace([], _, _, []).
ir_replace([N-_|T], N, D, [N-D|T]) :- !.
ir_replace([X|T], N, D, [X|T1]) :- ir_replace(T, N, D, T1).
ir_member_types([], []).
ir_member_types([member(_, _, Bits)|_], _) :- Bits \== none, !, ir_fail(bitfield).
ir_member_types([member(T, _, _)|Ms], [LL|LLs]) :- ir_type(T, LL), ir_member_types(Ms, LLs).
ir_member_index(T, N, I, MT) :- ccl_members_of(T, Ms), ir_member_index_(Ms, N, 0, I, MT), !.
ir_member_index(T, N, _, _) :- ir_fail(no_member(N, T)).
ir_member_index_([member(MT, N, _)|_], N, I, I, MT) :- !.
ir_member_index_([_|Ms], N, I0, I, MT) :- I1 is I0 + 1, ir_member_index_(Ms, N, I1, I, MT).

ir_signed(T) :- ccl_resolve_type(T, base(_, S)), \+ memberchk(unsigned, S).
ir_is_ptr(T) :- ccl_is_pointer(T).
ir_is_fp(T) :- ccl_is_float(T).
ir_is_int(T) :- ccl_is_integer(T).
ir_int(base([], [int])).
ir_long(base([], [long])).
ir_elem(T, E) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ; T1 = block(_, E) ), !.
ir_elem(T, _) :- ir_fail(not_a_pointer(T)).
ir_zero(LL, Z) :- ( LL == ptr -> Z = null ; ( LL == double ; LL == float ) -> Z = '0.0' ; sub_atom(LL, 0, 1, _, 'i') -> Z = 0 ; Z = zeroinitializer ).

%% ---- conversions -------------------------------------------------------------------
ir_convert(V, From, To, V1) :-
    ir_type(From, FL), ir_type(To, TL),
    (   FL == TL -> V1 = V
    ;   ir_is_fp(From), ir_is_fp(To) -> ( TL == double -> Op = fpext ; Op = fptrunc ), ir_op1(Op, FL, V, TL, V1)
    ;   ir_is_fp(From) -> ( ir_signed(To) -> Op = fptosi ; Op = fptoui ), ir_op1(Op, FL, V, TL, V1)
    ;   ir_is_fp(To) -> ( ir_signed(From) -> Op = sitofp ; Op = uitofp ), ir_op1(Op, FL, V, TL, V1)
    ;   ( FL == ptr ; ir_isfn(From) ), TL == ptr -> V1 = V
    ;   FL == ptr -> ir_op1(ptrtoint, FL, V, TL, V1)
    ;   TL == ptr -> ir_op1(inttoptr, FL, V, TL, V1)
    ;   ir_bits(FL, FB), ir_bits(TL, TB), FB > TB -> ir_op1(trunc, FL, V, TL, V1)
    ;   ir_signed(From) -> ir_op1(sext, FL, V, TL, V1)
    ;   ir_op1(zext, FL, V, TL, V1) ).
ir_isfn(T) :- ccl_resolve_type(T, fn(_, _, _)).
ir_op1(Op, FL, V, TL, R) :- ir_fresh(R), ir_ins([R, ' = ', Op, ' ', FL, ' ', V, ' to ', TL]).
ir_bits(i1, 1). ir_bits(i8, 8). ir_bits(i16, 16). ir_bits(i32, 32). ir_bits(i64, 64).
%% a value as a condition (i1)
ir_cond(E, C) :- ir_cmp_op(E, _), !, ir_expr_i1(E, C).
ir_cond(E, C) :-
    ir_expr(E, V, T), ir_type(T, LL),
    ( ir_is_fp(T) -> ir_fresh(C), ir_ins([C, ' = fcmp une ', LL, ' ', V, ', 0.0'])
    ; LL == ptr -> ir_fresh(C), ir_ins([C, ' = icmp ne ptr ', V, ', null'])
    ; ir_fresh(C), ir_ins([C, ' = icmp ne ', LL, ' ', V, ', 0']) ).
ir_cmp_op(bin(Op, _, _), Op) :- memberchk(Op, ['<', '>', '<=', '>=', '==', '!=']).
%% an i1 as a C int value
ir_bool(C, V) :- ir_fresh(V), ir_ins([V, ' = zext i1 ', C, ' to i32']).

%% ---- constants ------------------------------------------------------------------------
ir_string(S, Ref) :-
    nb_getval('$ir_strings', Ss), length(Ss, K), atomic_list_concat(['@.str.', K], Ref),
    length(S, N0), N is N0 + 1, ir_escape(S, Esc),
    atomic_list_concat([Ref, ' = private unnamed_addr constant [', N, ' x i8] c"', Esc, '\\00"'], Def),
    nb_setval('$ir_strings', [Def|Ss]).
ir_escape([], '').
ir_escape([C|Cs], A) :- ir_escape(Cs, A1), ( ( C < 32 ; C > 126 ; C =:= 34 ; C =:= 92 ) -> ir_hex2(C, H), atom_concat('\\', H, E) ; atom_codes(E, [C]) ), atom_concat(E, A1, A).
ir_hex2(C, H) :- Hi is C // 16, Lo is C mod 16, ir_hexd(Hi, A), ir_hexd(Lo, B), atom_concat(A, B, H).
ir_hexd(D, A) :- ( D < 10 -> C is 0'0 + D ; C is 0'A + D - 10 ), atom_codes(A, [C]).
%% a double as LLVM's hex literal: sign, 11 exponent bits, 52 fraction bits
ir_double(F, A) :-
    ( F =:= 0.0 -> A = '0x0000000000000000'
    ; X is abs(F), ( F < 0 -> Sg = 8 ; Sg = 0 ),
      E0 is floor(log(X) / log(2)), ir_norm(X, E0, E, M),
      Frac is round((M - 1) * 4503599627370496), Ex is E + 1023,
      D1 is Sg + (Ex >> 8), D23 is Ex mod 256,
      ir_hexd(D1, H1), ir_hex2(D23, H23), ir_hexn(Frac, 13, HF),
      atomic_list_concat(['0x', H1, H23, HF], A) ).
ir_norm(X, E0, E, M) :- M0 is X / (2.0 ** E0), ( M0 >= 2.0 -> E1 is E0 + 1, ir_norm(X, E1, E, M) ; M0 < 1.0 -> E1 is E0 - 1, ir_norm(X, E1, E, M) ; E = E0, M = M0 ).
ir_hexn(_, 0, '') :- !.
ir_hexn(N, K, A) :- D is N mod 16, N1 is N // 16, K1 is K - 1, ir_hexn(N1, K1, A1), ir_hexd(D, H), atom_concat(A1, H, A).

%% ---- expressions: a value and its C type ------------------------------------------------
ir_expr(int(N), N, T) :- !, ( ( N > 2147483647 ; N < -2147483648 ) -> ir_long(T) ; ir_int(T) ).
ir_expr(float(F), A, base([], [double])) :- !, ir_double(F, A).
ir_expr(chr(C), C, T) :- !, ir_int(T).
ir_expr(str(S), Ref, ptr([], base([], [char]))) :- !, ir_string(S, Ref).
ir_expr(id(N), V, T) :- ccl_enum_value(N, V), !, ir_int(T).          % an enumerator is its value
ir_expr(id(N), V, T) :- !,
    ( ir_lookup(N, loc(Addr, T0)) -> true ; ir_fail(undeclared(N)) ),
    ccl_resolve_type(T0, T1),
    (   T1 = arr(_, E) -> V = Addr, T = ptr([], E)
    ;   T1 = fn(_, _, _) -> V = Addr, T = ptr([], T0)
    ;   ir_type(T0, LL), ir_fresh(V), ir_ins([V, ' = load ', LL, ', ptr ', Addr]), T = T0 ).
ir_expr(call(F, Args), V, RT) :- !, ir_call(F, Args, V, RT).
ir_expr(assign('=', L, R), V, LT) :- !,
    ir_lval(L, Addr, LT), ir_expr(R, V0, RT), ir_convert(V0, RT, LT, V), ir_type(LT, LL), ir_ins(['store ', LL, ' ', V, ', ptr ', Addr]).
ir_expr(assign(Op, L, R), V, LT) :- !,
    atom_concat(BinOp, '=', Op), ir_lval(L, Addr, LT), ir_type(LT, LL),
    ir_fresh(Cur), ir_ins([Cur, ' = load ', LL, ', ptr ', Addr]),
    ir_binary(BinOp, Cur, LT, R, V0, RT), ir_convert(V0, RT, LT, V), ir_ins(['store ', LL, ' ', V, ', ptr ', Addr]).
ir_expr(bin('&&', A, B), V, T) :- !, ir_int(T),
    ir_label(LB), ir_label(LE), ir_cond(A, CA), ir_cur_label(LA0), ir_end(['br i1 ', CA, ', label %', LB, ', label %', LE]),
    ir_block(LB), ir_cond(B, CB), ir_cur_label(LB1), ir_end(['br label %', LE]),
    ir_block(LE), ir_fresh(C), ir_ins([C, ' = phi i1 [ false, %', LA0, ' ], [ ', CB, ', %', LB1, ' ]']), ir_bool(C, V).
ir_expr(bin('||', A, B), V, T) :- !, ir_int(T),
    ir_label(LB), ir_label(LE), ir_cond(A, CA), ir_cur_label(LA0), ir_end(['br i1 ', CA, ', label %', LE, ', label %', LB]),
    ir_block(LB), ir_cond(B, CB), ir_cur_label(LB1), ir_end(['br label %', LE]),
    ir_block(LE), ir_fresh(C), ir_ins([C, ' = phi i1 [ true, %', LA0, ' ], [ ', CB, ', %', LB1, ' ]']), ir_bool(C, V).
ir_expr(bin(Op, A, B), V, T) :- ir_cmp_op(bin(Op, A, B), _), !, ir_int(T), ir_expr_i1(bin(Op, A, B), C), ir_bool(C, V).
ir_expr(bin(Op, A, B), V, T) :- !, ir_expr(A, VA, TA), ir_binary(Op, VA, TA, B, V, T).
ir_expr(neg(E), V, T) :- !, ir_expr(E, V0, T0), ccl_promote(T0, T), ir_convert(V0, T0, T, V1), ir_type(T, LL),
    ir_fresh(V), ( ir_is_fp(T) -> ir_ins([V, ' = fneg ', LL, ' ', V1]) ; ir_ins([V, ' = sub ', LL, ' 0, ', V1]) ).
ir_expr(pos(E), V, T) :- !, ir_expr(E, V, T).
ir_expr(bitnot(E), V, T) :- !, ir_expr(E, V0, T0), ccl_promote(T0, T), ir_convert(V0, T0, T, V1), ir_type(T, LL), ir_fresh(V), ir_ins([V, ' = xor ', LL, ' ', V1, ', -1']).
ir_expr(not(E), V, T) :- !, ir_int(T), ir_cond(E, C), ir_fresh(C1), ir_ins([C1, ' = xor i1 ', C, ', true']), ir_bool(C1, V).
ir_expr(addr(E), Addr, ptr([], T)) :- !, ir_lval(E, Addr, T).
ir_expr(deref(E), V, T) :- !, ir_lval(deref(E), Addr, T), ir_load_or_decay(Addr, T, V).
ir_expr(index(A, I), V, T) :- !, ir_lval(index(A, I), Addr, T), ir_load_or_decay(Addr, T, V).
ir_expr(member(E, N), V, T) :- !, ir_lval(member(E, N), Addr, T), ir_load_or_decay(Addr, T, V).
ir_expr(arrow(E, N), V, T) :- !, ir_lval(arrow(E, N), Addr, T), ir_load_or_decay(Addr, T, V).
ir_expr(preinc(E), V, T) :- !, ir_step(E, add, pre, V, T).
ir_expr(predec(E), V, T) :- !, ir_step(E, sub, pre, V, T).
ir_expr(postinc(E), V, T) :- !, ir_step(E, add, post, V, T).
ir_expr(postdec(E), V, T) :- !, ir_step(E, sub, post, V, T).
ir_expr(cast(T, E), V, T) :- !, ir_expr(E, V0, T0), ( ccl_resolve_type(T, base(_, [void])) -> V = V0 ; ir_convert(V0, T0, T, V) ).
ir_expr(sizeof(E), N, T) :- !, ccl_size_type(T), ccl_type_of(E, ET), ( ccl_size_of(ET, N) -> true ; ir_fail(sizeof(E)) ).
ir_expr(sizeof_type(ET), N, T) :- !, ccl_size_type(T), ( ccl_size_of(ET, N) -> true ; ir_fail(sizeof_type(ET)) ).
ir_expr(cond(C, A, B), V, T) :- !,
    ccl_type_of(A, TA), ccl_type_of(B, TB), ( ccl_is_arith(TA), ccl_is_arith(TB) -> ccl_usual(TA, TB, T) ; T = TA ),
    ir_label(LT), ir_label(LF), ir_label(LE), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LT, ', label %', LF]),
    ir_block(LT), ir_expr(A, VA0, TA1), ir_convert(VA0, TA1, T, VA), ir_cur_label(LT1), ir_end(['br label %', LE]),
    ir_block(LF), ir_expr(B, VB0, TB1), ir_convert(VB0, TB1, T, VB), ir_cur_label(LF1), ir_end(['br label %', LE]),
    ir_block(LE), ir_type(T, LL), ir_fresh(V), ir_ins([V, ' = phi ', LL, ' [ ', VA, ', %', LT1, ' ], [ ', VB, ', %', LF1, ' ]']).
ir_expr(comma(A, B), V, T) :- !, ir_expr(A, _, _), ir_expr(B, V, T).
ir_expr(move(E), V, T) :- !, ir_expr(E, V, T).                        % a move is the value; the checker did the rest
ir_expr(compound_lit(T, Init), V, T1) :- !,
    ir_fresh(Addr), ir_type(T, LL), ir_alloca(Addr, LL), ir_init(Addr, T, Init), ir_load_or_decay(Addr, T, V), ccl_resolve_type(T, RT), ( RT = arr(_, E) -> T1 = ptr([], E) ; T1 = T ).
ir_expr(stmt_expr(block(Is)), V, T) :- !,
    ir_env_push, ( append(Init, [expr(E)], Is) -> ir_stmts(Init), ir_expr(E, V, T) ; ir_stmts(Is), V = none, T = base([], [void]) ),
    ir_run_defers(1), ir_env_pop.
ir_expr(E, _, _) :- ir_fail(expr(E)).

%% the label of the block the last instruction went into (for phis)
ir_cur_label(L) :- nb_getval('$ir_body', B), ir_last_label(B, L).
ir_last_label([Line|T], L) :- ( sub_atom(Line, _, 1, 0, ':'), \+ sub_atom(Line, 0, 1, _, ' ') -> sub_atom(Line, 0, _, 1, L) ; ir_last_label(T, L) ).
ir_last_label([], entry).

ir_load_or_decay(Addr, T, V) :-
    ccl_resolve_type(T, T1),
    ( T1 = arr(_, _) -> V = Addr ; ir_type(T, LL), ir_fresh(V), ir_ins([V, ' = load ', LL, ', ptr ', Addr]) ).

ir_expr_i1(bin(Op, A, B), C) :-
    ir_expr(A, VA, TA), ir_expr(B, VB, TB),
    (   ( ir_is_ptr(TA) ; ir_is_ptr(TB) ) -> ir_ptr_operands(VA, TA, VB, TB, PA, PB), ir_icmp(Op, false, ptr, PA, PB, C)
    ;   ccl_usual(TA, TB, T), ir_convert(VA, TA, T, A1), ir_convert(VB, TB, T, B1), ir_type(T, LL),
        ( ir_is_fp(T) -> ir_fcmp(Op, LL, A1, B1, C) ; ( ir_signed(T) -> S = true ; S = false ), ir_icmp(Op, S, LL, A1, B1, C) ) ).
ir_ptr_operands(VA, TA, VB, TB, PA, PB) :- ir_to_ptr(VA, TA, PA), ir_to_ptr(VB, TB, PB).
ir_to_ptr(V, T, P) :- ( ir_is_ptr(T) -> P = V ; V == 0 -> P = null ; ir_convert(V, T, ptr([], base([], [void])), P) ).
ir_icmp(Op, S, LL, A, B, C) :- ir_icmp_pred(Op, S, P), ir_fresh(C), ir_ins([C, ' = icmp ', P, ' ', LL, ' ', A, ', ', B]).
ir_icmp_pred('==', _, eq). ir_icmp_pred('!=', _, ne).
ir_icmp_pred('<', true, slt). ir_icmp_pred('<', false, ult). ir_icmp_pred('>', true, sgt). ir_icmp_pred('>', false, ugt).
ir_icmp_pred('<=', true, sle). ir_icmp_pred('<=', false, ule). ir_icmp_pred('>=', true, sge). ir_icmp_pred('>=', false, uge).
ir_fcmp(Op, LL, A, B, C) :- ir_fcmp_pred(Op, P), ir_fresh(C), ir_ins([C, ' = fcmp ', P, ' ', LL, ' ', A, ', ', B]).
ir_fcmp_pred('==', oeq). ir_fcmp_pred('!=', une). ir_fcmp_pred('<', olt). ir_fcmp_pred('>', ogt). ir_fcmp_pred('<=', ole). ir_fcmp_pred('>=', oge).

%% a binary arithmetic/bitwise/shift operator over a lowered left operand
ir_binary(Op, VA, TA, B, V, T) :-
    ir_expr(B, VB, TB),
    (   memberchk(Op, ['+', '-']), ir_is_ptr(TA), ir_is_ptr(TB), Op == '-' ->      % p - q
            ir_elem(TA, E), ccl_size_of(E, Sz), ir_long(T),
            ir_op1(ptrtoint, ptr, VA, i64, A1), ir_op1(ptrtoint, ptr, VB, i64, B1),
            ir_fresh(D), ir_ins([D, ' = sub i64 ', A1, ', ', B1]), ir_fresh(V), ir_ins([V, ' = sdiv exact i64 ', D, ', ', Sz])
    ;   memberchk(Op, ['+', '-']), ir_is_ptr(TA) -> ir_ptr_add(Op, VA, TA, VB, TB, V), ir_decayed(TA, T)
    ;   Op == '+', ir_is_ptr(TB) -> ir_ptr_add('+', VB, TB, VA, TA, V), ir_decayed(TB, T)
    ;   ccl_usual(TA, TB, T0), ( memberchk(Op, ['<<', '>>']) -> ccl_promote(TA, T) ; T = T0 ),
        ir_convert(VA, TA, T, A1), ( memberchk(Op, ['<<', '>>']) -> ir_convert(VB, TB, T, B1) ; ir_convert(VB, TB, T, B1) ),
        ir_type(T, LL), ir_arith_op(Op, T, Ins), ir_fresh(V), ir_ins([V, ' = ', Ins, ' ', LL, ' ', A1, ', ', B1]) ).
ir_decayed(T, D) :- ccl_resolve_type(T, T1), ( T1 = arr(_, E) -> D = ptr([], E) ; D = T ).
ir_ptr_add(Op, P, PT, I, IT, V) :-
    ir_elem(PT, E), ir_type(E, EL), ir_convert(I, IT, base([], [long]), I1),
    ( Op == '-' -> ir_fresh(N), ir_ins([N, ' = sub i64 0, ', I1]) ; N = I1 ),
    ir_fresh(V), ir_ins([V, ' = getelementptr ', EL, ', ptr ', P, ', i64 ', N]).
ir_arith_op('+', T, Ins) :- ( ir_is_fp(T) -> Ins = fadd ; Ins = add ).
ir_arith_op('-', T, Ins) :- ( ir_is_fp(T) -> Ins = fsub ; Ins = sub ).
ir_arith_op('*', T, Ins) :- ( ir_is_fp(T) -> Ins = fmul ; Ins = mul ).
ir_arith_op('/', T, Ins) :- ( ir_is_fp(T) -> Ins = fdiv ; ir_signed(T) -> Ins = sdiv ; Ins = udiv ).
ir_arith_op('%', T, Ins) :- ( ir_is_fp(T) -> Ins = frem ; ir_signed(T) -> Ins = srem ; Ins = urem ).
ir_arith_op('&', _, and). ir_arith_op('|', _, or). ir_arith_op('^', _, xor). ir_arith_op('<<', _, shl).
ir_arith_op('>>', T, Ins) :- ( ir_signed(T) -> Ins = ashr ; Ins = lshr ).

%% ++ and --, on integers, floats and pointers
ir_step(E, Op, When, V, T) :-
    ir_lval(E, Addr, T), ir_type(T, LL), ir_fresh(Cur), ir_ins([Cur, ' = load ', LL, ', ptr ', Addr]),
    ir_fresh(New),
    (   ir_is_ptr(T) -> ir_elem(T, El), ir_type(El, ELL), ( Op == add -> D = 1 ; D = -1 ), ir_ins([New, ' = getelementptr ', ELL, ', ptr ', Cur, ', i64 ', D])
    ;   ir_is_fp(T) -> ( Op == add -> F = fadd ; F = fsub ), ir_ins([New, ' = ', F, ' ', LL, ' ', Cur, ', 1.0'])
    ;   ir_ins([New, ' = ', Op, ' ', LL, ' ', Cur, ', 1']) ),
    ir_ins(['store ', LL, ' ', New, ', ptr ', Addr]),
    ( When == pre -> V = New ; V = Cur ).

%% ---- calls ------------------------------------------------------------------------------
ir_call(id(N), Args, V, RT) :-
    ir_lookup(N, loc(Addr, T0)), ccl_resolve_type(T0, fn(RT, Ps, Var)), !,
    ir_call_(Addr, RT, Ps, Var, Args, V).
ir_call(F, Args, V, RT) :-
    ir_expr(F, FV, FT), ccl_resolve_type(FT, FT1),
    ( FT1 = ptr(_, FnT) -> true ; FnT = FT1 ), ccl_resolve_type(FnT, fn(RT, Ps, Var)), !,
    ir_call_(FV, RT, Ps, Var, Args, V).
ir_call(F, _, _, _) :- ir_fail(call(F)).
ir_call_(Callee, RT, Ps, Var, Args, V) :-
    ir_args(Args, Ps, ArgTxt, ParamLLs), ir_type(RT, RL),
    ( Var == true -> ir_join(ParamLLs, ', ', PL), atomic_list_concat([RL, ' (', PL, ', ...)'], Sig) ; Sig = RL ),
    ( RL == void -> ir_ins(['call ', Sig, ' ', Callee, '(', ArgTxt, ')']), V = none
    ; ir_fresh(V), ir_ins([V, ' = call ', Sig, ' ', Callee, '(', ArgTxt, ')']) ).
ir_args(Args, Ps, Txt, PLLs) :- ir_args_(Args, Ps, Parts, PLLs), ir_join(Parts, ', ', Txt).
ir_args_([], _, [], []).
ir_args_([A|As], [param(PT, _)|Ps], [Part|Parts], [PL|PLs]) :- !,
    ir_expr(A, V0, T0), ir_convert(V0, T0, PT, V), ir_type(PT, PL), atomic_list_concat([PL, ' ', V], Part), ir_args_(As, Ps, Parts, PLs).
ir_args_([A|As], [], [Part|Parts], PLs) :-                    % the variadic tail: default promotions
    ir_expr(A, V0, T0), ir_promote_arg(V0, T0, V, T), ir_type(T, LL), atomic_list_concat([LL, ' ', V], Part), ir_args_(As, [], Parts, PLs).
ir_promote_arg(V0, T0, V, T) :-
    ( ccl_resolve_type(T0, base(_, S)), memberchk(float, S) -> T = base([], [double]), ir_convert(V0, T0, T, V)
    ; ir_is_int(T0), ccl_int_rank(T0, R, _), R < 3 -> ir_int(T), ir_convert(V0, T0, T, V)
    ; V = V0, T = T0 ).

%% ---- lvalues: an address and the C type there --------------------------------------------
ir_lval(id(N), Addr, T) :- !, ( ir_lookup(N, loc(Addr, T)) -> true ; ir_fail(undeclared(N)) ).
ir_lval(deref(E), Addr, T) :- !, ir_expr(E, Addr, PT), ir_elem(PT, T).
ir_lval(index(A, I), Addr, T) :- !,
    ir_expr(A, P, PT), ir_elem(PT, T), ir_type(T, LL), ir_expr(I, IV, IT), ir_convert(IV, IT, base([], [long]), I1),
    ir_fresh(Addr), ir_ins([Addr, ' = getelementptr ', LL, ', ptr ', P, ', i64 ', I1]).
ir_lval(member(E, N), Addr, T) :- !,
    ( ir_lval(E, Base, ST) -> true ; ir_expr(E, SV, ST), ir_type(ST, SLL), ir_fresh(Base), ir_alloca(Base, SLL), ir_ins(['store ', SLL, ' ', SV, ', ptr ', Base]) ),
    ir_member_gep(Base, ST, N, Addr, T).
ir_lval(arrow(E, N), Addr, T) :- !, ir_expr(E, P, PT), ir_elem(PT, ST), ir_member_gep(P, ST, N, Addr, T).
ir_lval(compound_lit(T, Init), Addr, T) :- !, ir_fresh(Addr), ir_type(T, LL), ir_alloca(Addr, LL), ir_init(Addr, T, Init).
ir_lval(E, _, _) :- ir_fail(lvalue(E)).
ir_member_gep(Base, ST, N, Addr, T) :-
    ir_type(ST, SLL), ir_member_index(ST, N, I, T),
    ( sub_atom(SLL, 0, 1, _, '[') -> Addr = Base                         % a union: every member at its address
    ; ir_fresh(Addr), ir_ins([Addr, ' = getelementptr ', SLL, ', ptr ', Base, ', i32 0, i32 ', I]) ).

%% ---- initializers -------------------------------------------------------------------------
ir_init(_, _, none) :- !.
ir_init(Addr, T, init(Items)) :- !,
    ir_type(T, LL), ir_ins(['store ', LL, ' zeroinitializer, ptr ', Addr]), ir_init_items(Items, Addr, T, 0).
ir_init(Addr, T, E) :-
    ccl_resolve_type(T, T1),
    (   T1 = arr(_, El), E = str(S) -> ir_type(El, _), ir_init_string(Addr, T1, S)
    ;   ir_expr(E, V0, ET), ir_convert(V0, ET, T, V), ir_type(T, LL), ir_ins(['store ', LL, ' ', V, ', ptr ', Addr]) ).
ir_init_string(Addr, arr(_, _), S) :- append(S, [0], Cs), ir_init_chars(Cs, Addr, 0).
ir_init_chars([], _, _).
ir_init_chars([C|Cs], Addr, I) :- ir_fresh(P), ir_ins([P, ' = getelementptr i8, ptr ', Addr, ', i64 ', I]), ir_ins(['store i8 ', C, ', ptr ', P]), I1 is I + 1, ir_init_chars(Cs, Addr, I1).
ir_init_items([], _, _, _).
ir_init_items([item(Ds, V)|Is], Addr, T, I) :-
    ccl_resolve_type(T, T1),
    (   Ds = [at(int(K))|Rest] -> I0 = K, Ds1 = Rest
    ;   Ds = [field(F)|Rest] -> ir_member_index(T1, F, I0, _), Ds1 = Rest
    ;   I0 = I, Ds1 = [] ),
    ir_init_slot(Addr, T1, I0, Ds1, V), I1 is I0 + 1, ir_init_items(Is, Addr, T, I1).
ir_init_slot(Addr, arr(_, El), I, Ds, V) :- !,
    ir_type(El, LL), ir_fresh(P), ir_ins([P, ' = getelementptr ', LL, ', ptr ', Addr, ', i64 ', I]), ir_init_sub(P, El, Ds, V).
ir_init_slot(Addr, ST, I, Ds, V) :-
    ir_type(ST, SLL), ccl_members_of(ST, Ms), I1 is I + 1, ( ccl_nth(I1, Ms, member(MT, _, _)) -> true ; ir_fail(initializer(I)) ),
    ir_fresh(P), ir_ins([P, ' = getelementptr ', SLL, ', ptr ', Addr, ', i32 0, i32 ', I]), ir_init_sub(P, MT, Ds, V).
ir_init_sub(P, T, [], V) :- !, ( V = init(_) -> ir_init(P, T, V) ; ir_init(P, T, V) ).
ir_init_sub(P, T, Ds, V) :- ir_init_items([item(Ds, V)], P, T, 0).

%% ---- statements ---------------------------------------------------------------------------
ir_stmts([]).
ir_stmts([S|Ss]) :- ir_stmt(S), ir_stmts(Ss).
ir_stmt(block(Is)) :- !, ir_env_push, ir_stmts(Is), ir_run_defers(1), ir_env_pop.
ir_stmt('$splice'(Is)) :- !, ir_stmts(Is).
ir_stmt(declaration(_, Sto, _, Vs)) :- !, ( Sto == static -> ir_fail(static_local) ; true ), ir_locals(Vs, Sto).
ir_stmt(typedef(_, _)) :- !.
ir_stmt(declare(_, _)) :- !.
ir_stmt(directive(_, _)) :- !.
ir_stmt(include(_, _, _)) :- !.
ir_stmt(static_assert(_, _, _)) :- !.
ir_stmt(empty) :- !.
ir_stmt(expr(E)) :- !, ir_expr(E, _, _).
ir_stmt(defer(_, _, Body)) :- !, ir_defer_push(Body).
ir_stmt(if(C, T, E)) :- !,
    ir_label(LT), ir_label(LE), ir_label(LM), ir_cond(C, CC),
    ( E == none -> ir_end(['br i1 ', CC, ', label %', LT, ', label %', LM]) ; ir_end(['br i1 ', CC, ', label %', LT, ', label %', LE]) ),
    ir_block(LT), ir_stmt(T), ir_end(['br label %', LM]),
    ( E == none -> true ; ir_block(LE), ir_stmt(E), ir_end(['br label %', LM]) ),
    ir_block(LM).
ir_stmt(while(C, S)) :- !,
    ir_label(LC), ir_label(LB), ir_label(LE), ir_block(LC), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]),
    ir_block(LB), ir_loop_push(LE, LC), ir_stmt(S), ir_loop_pop, ir_end(['br label %', LC]), ir_block(LE).
ir_stmt(do(S, C)) :- !,
    ir_label(LB), ir_label(LC), ir_label(LE), ir_block(LB), ir_loop_push(LE, LC), ir_stmt(S), ir_loop_pop,
    ir_block(LC), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]), ir_block(LE).
ir_stmt(for(Init, C, Step, S)) :- !,
    ir_env_push,
    ( Init = decl(_, Vs) -> ir_locals(Vs, none) ; Init == none -> true ; ir_expr(Init, _, _) ),
    ir_label(LC), ir_label(LB), ir_label(LS), ir_label(LE), ir_block(LC),
    ( C == none -> ir_end(['br label %', LB]) ; ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]) ),
    ir_block(LB), ir_loop_push(LE, LS), ir_stmt(S), ir_loop_pop,
    ir_block(LS), ( Step == none -> true ; ir_expr(Step, _, _) ), ir_end(['br label %', LC]),
    ir_block(LE), ir_run_defers(1), ir_env_pop.
ir_stmt(return) :- !, ir_run_defers(all), ir_end(['ret void']).
ir_stmt(return(E)) :- !,
    nb_getval('$ir_ret', RT), ir_expr(E, V0, T0),
    ( ccl_resolve_type(RT, base(_, [void])) -> ir_run_defers(all), ir_end(['ret void'])
    ; ir_convert(V0, T0, RT, V), ir_run_defers(all), ir_type(RT, LL), ir_end(['ret ', LL, ' ', V]) ).
ir_stmt(break) :- !, ir_loop_top(LE, _, Depth), ir_depth(D), K is D - Depth, ir_run_defers(K), ir_end(['br label %', LE]).
ir_stmt(continue) :- !, ir_continue_target(LC, Depth), ir_depth(D), K is D - Depth, ir_run_defers(K), ir_end(['br label %', LC]).
ir_stmt(goto(L)) :- !, atom_concat('L.', L, LL), ir_end(['br label %', LL]).
ir_stmt(label(L, S)) :- !, atom_concat('L.', L, LL), ir_block(LL), ir_stmt(S).
ir_stmt(switch(E, block(Is))) :- !,
    ir_expr(E, V0, T0), ir_int(IT), ir_convert(V0, T0, IT, V),
    ir_label(LE), ir_switch_cases(Is, Cases, Default),
    ( Default = none -> DL = LE ; Default = DL ),
    ir_case_lines(Cases, Lines), ir_join(Lines, ' ', CL),
    ir_end(['switch i32 ', V, ', label %', DL, ' [ ', CL, ' ]']),
    ir_env_push, ir_loop_push(LE, none), ir_switch_body(Is, Cases, Default), ir_loop_pop, ir_run_defers(1), ir_env_pop,
    ir_block(LE).
ir_stmt(switch(E, S)) :- !, ir_stmt(switch(E, block([S]))).
ir_stmt(case(_, S)) :- !, ir_stmt(S).
ir_stmt(default(S)) :- !, ir_stmt(S).
ir_stmt(S) :- ir_fail(stmt(S)).

ir_locals([], _).
ir_locals([var(N, T, Init)|Vs], Sto) :-
    ccl_resolve_type(T, T1),
    (   T1 = fn(_, _, _) -> ir_note_extern(N, T)                         % a local prototype
    ;   Sto == extern -> ir_note_extern(N, T)
    ;   ir_sized_type(T, T1, Init, ST), ir_type(ST, LL),                    % int xs[] = {...}: sized by its initializer
        nb_getval('$ir_reg', K), K1 is K + 1, nb_setval('$ir_reg', K1), atomic_list_concat(['%', N, '.', K1], Addr),
        ir_alloca(Addr, LL), ir_local(N, ST, Addr), ir_init(Addr, ST, Init) ),
    ir_locals(Vs, Sto).

%% the loop stack: break target, continue target (none in a switch), and the defer depth at entry
ir_loop_push(LE, LC) :- ir_depth(D), nb_getval('$ir_loops', L), nb_setval('$ir_loops', [loop(LE, LC, D)|L]).
ir_loop_pop :- nb_getval('$ir_loops', [_|L]), nb_setval('$ir_loops', L).
ir_loop_top(LE, LC, D) :- nb_getval('$ir_loops', [loop(LE, LC, D)|_]), !.
ir_loop_top(_, _, _) :- ir_fail(break_outside_loop).
ir_continue_target(LC, D) :- nb_getval('$ir_loops', L), ( member(loop(_, LC, D), L), LC \== none -> true ; ir_fail(continue_outside_loop) ).

%% a switch body's cases, at the top level of its block
ir_switch_cases([], [], none).
ir_switch_cases([case(E, S)|Is], [case(E, L)|Cs], D) :- !, ir_label(L), ir_switch_cases([S|Is], Cs, D).
ir_switch_cases([default(S)|Is], Cs, L) :- !, ir_label(L), ir_switch_cases([S|Is], Cs, _).
ir_switch_cases([_|Is], Cs, D) :- ir_switch_cases(Is, Cs, D).
ir_case_lines([], []).
ir_case_lines([case(E, L)|Cs], [Line|Ls]) :- ir_const_int(E, N), atomic_list_concat(['i32 ', N, ', label %', L], Line), ir_case_lines(Cs, Ls).
ir_const_int(int(N), N) :- !.
ir_const_int(chr(C), C) :- !.
ir_const_int(neg(int(N)), M) :- !, M is -N.
ir_const_int(E, V) :- ccl_const_eval(E, V), !.
ir_const_int(E, _) :- ir_fail(case(E)).
ir_switch_body([], _, _).
ir_switch_body([case(E, S)|Is], Cases, D) :- !, memberchk(case(E, L), Cases), ir_block(L), ir_switch_body([S|Is], Cases, D).
ir_switch_body([default(S)|Is], Cases, D) :- !, ir_block(D), ir_switch_body([S|Is], Cases, D).
ir_switch_body([S|Is], Cases, D) :- ir_stmt(S), ir_switch_body(Is, Cases, D).

%% ---- functions and globals -------------------------------------------------------------------
ir_item(function(_, Sto, Ret, Name, Params, Var, Body)) :- !,
    ir_function(Sto, Ret, Name, Params, Var, Body, Text),
    nb_getval('$ir_fdefs', Fs), nb_setval('$ir_fdefs', [Text|Fs]),
    nb_getval('$ir_defined', Ds), nb_setval('$ir_defined', [Name|Ds]).
ir_item(declaration(_, Sto, _, Vs)) :- !, ir_globals(Vs, Sto).
ir_item(_).

ir_function(Sto, Ret, Name, Params, Var, Body, Text) :-
    nb_setval('$ir_fn', Name), nb_setval('$ir_body', []), nb_setval('$ir_allocas', []), nb_setval('$ir_term', no),
    nb_setval('$ir_env', [[]]), nb_setval('$ir_defers', [[]]), nb_setval('$ir_loops', []), nb_setval('$ir_ret', Ret), nb_setval('$ir_reg', 0),
    ccl_scope_push,
    ir_params(Params, 0, Sigs, Stores), ir_join(Sigs, ', ', SigTxt),
    ( Var == true -> ( Sigs == [] -> Sig = '...' ; atom_concat(SigTxt, ', ...', Sig) ) ; Sig = SigTxt ),
    ir_run_lines(Stores),
    ir_stmt(Body),
    ir_type(Ret, RL),
    ( ir_terminated(yes) -> true
    ; RL == void -> ir_end(['ret void'])
    ; Name == main -> ir_end(['ret i32 0'])
    ; ir_zero(RL, Z), ir_end(['ret ', RL, ' ', Z]) ),
    ccl_scope_pop,
    ( Sto == static -> Link = 'define internal ' ; Link = 'define ' ),
    nb_getval('$ir_allocas', As0), reverse(As0, As), nb_getval('$ir_body', B0), reverse(B0, B),
    atomic_list_concat([Link, RL, ' @', Name, '(', Sig, ') {'], Head),
    append([Head, 'entry:'|As], B, Lines0), append(Lines0, ['}', ''], Lines),
    ir_join(Lines, '\n', Text).
ir_params([], _, [], []).
ir_params([param(T, N)|Ps], I, [Sig|Sigs], Stores) :-
    ir_type(T, LL0), ccl_resolve_type(T, T1),
    ( T1 = arr(_, E) -> PT = ptr([], E), LL = ptr ; PT = T, LL = LL0 ),
    ( N == anon -> atomic_list_concat(['%p', I], R) ; atomic_list_concat(['%', N], R) ),
    atomic_list_concat([LL, ' ', R], Sig),
    ( N == anon -> Stores = Stores1
    ; atomic_list_concat(['%', N, '.addr'], Addr), Stores = [alloca(Addr, LL), store(LL, R, Addr), local(N, PT, Addr)|Stores1] ),
    I1 is I + 1, ir_params(Ps, I1, Sigs, Stores1).
ir_run_lines([]).
ir_run_lines([alloca(A, LL)|T]) :- ir_alloca(A, LL), ir_run_lines(T).
ir_run_lines([store(LL, R, A)|T]) :- ir_ins(['store ', LL, ' ', R, ', ptr ', A]), ir_run_lines(T).
ir_run_lines([local(N, T0, A)|T]) :- ir_local(N, T0, A), ir_run_lines(T).

ir_globals([], _).
ir_globals([var(N, T, Init)|Vs], Sto) :-
    ccl_resolve_type(T, T1),
    (   ( T1 = fn(_, _, _) ; Sto == extern ; Sto == typedef ) -> true
    ;   ir_sized_type(T, T1, Init, GT), ir_type(GT, LL), ir_gconst(Init, GT, C),
        ( Sto == static -> Link = 'internal global' ; Link = 'global' ),
        atomic_list_concat(['@', N, ' = ', Link, ' ', LL, ' ', C], Def),
        nb_getval('$ir_gdefs', Gs), nb_setval('$ir_gdefs', [Def|Gs]),
        nb_getval('$ir_gmap', M), nb_setval('$ir_gmap', [N-GT|M]),
        nb_getval('$ir_defined', Ds), nb_setval('$ir_defined', [N|Ds]) ),
    ir_globals(Vs, Sto).
%% an unsized array, global or local, takes its size from its initializer
ir_sized_type(_, arr(none, E), init(Items), arr(int(K), E)) :- !, length(Items, K).
ir_sized_type(_, arr(none, E), str(S), arr(int(K), E)) :- !, length(S, K0), K is K0 + 1.
ir_sized_type(T, _, _, T).
ir_gconst(none, T, Z) :- !, ir_type(T, LL), ir_zero(LL, Z).
ir_gconst(int(N), _, N) :- !.
ir_gconst(neg(int(N)), _, M) :- !, M is -N.
ir_gconst(chr(C), _, C) :- !.
ir_gconst(float(F), T, A) :- !, ( ccl_resolve_type(T, base(_, S)), memberchk(float, S) -> ir_fail(float_global) ; ir_double(F, A) ).
ir_gconst(str(S), T, C) :- !,
    ccl_resolve_type(T, T1),
    ( T1 = arr(_, _) -> ir_escape(S, Esc), atomic_list_concat(['c"', Esc, '\\00"'], C) ; ir_string(S, C) ).
ir_gconst(init(Items), T, C) :- !,
    ccl_resolve_type(T, T1),
    (   T1 = arr(int(K), E) -> ir_type(E, EL), ir_gitems(Items, K, E, EL, Parts), ir_join(Parts, ', ', Body), atomic_list_concat(['[', Body, ']'], C)
    ;   ccl_members_of(T1, Ms) -> ir_gmembers(Ms, Items, Parts), ir_join(Parts, ', ', Body), atomic_list_concat(['{ ', Body, ' }'], C)   % the type is written by whoever holds the constant
    ;   ir_fail(global_init(T)) ).
ir_gconst(E, _, _) :- ir_fail(global_init(E)).
ir_gitems([], 0, _, _, []) :- !.
ir_gitems([], K, E, EL, [Z|Zs]) :- ir_type(E, _), ir_zero(EL, Z0), atomic_list_concat([EL, ' ', Z0], Z), K1 is K - 1, ir_gitems([], K1, E, EL, Zs).
ir_gitems([item(_, V)|Is], K, E, EL, [P|Ps]) :- ir_gconst(V, E, C), atomic_list_concat([EL, ' ', C], P), K1 is K - 1, ir_gitems(Is, K1, E, EL, Ps).
ir_gmembers([], _, []).
ir_gmembers([member(MT, _, _)|Ms], Items, [P|Ps]) :-
    ir_type(MT, LL), ( Items = [item(_, V)|Rest] -> ir_gconst(V, MT, C) ; ir_zero(LL, C), Rest = [] ),
    atomic_list_concat([LL, ' ', C], P), ir_gmembers(Ms, Rest, Ps).

%% ---- the module -----------------------------------------------------------------------------------
ir_assemble(IR) :-
    nb_getval('$ir_structs', Ss), ir_struct_defs(Ss, SDefs),
    nb_getval('$ir_strings', Strs), reverse(Strs, Strings),
    nb_getval('$ir_gdefs', Gs0), reverse(Gs0, Gs),
    nb_getval('$ir_fdefs', Fs0), reverse(Fs0, Fs),
    nb_getval('$ir_externs', Es), nb_getval('$ir_defined', Ds), ir_declares(Es, Ds, Decls),
    append(['; cicili-lang', ''|SDefs], Strings, L1), append(L1, Gs, L2), append(L2, [''|Fs], L3), append(L3, Decls, L4),
    ir_join(L4, '\n', IR).
ir_struct_defs([], []).
ir_struct_defs([_-pending|T], D) :- !, ir_struct_defs(T, D).
ir_struct_defs([_-Def|T], [Def|D]) :- ir_struct_defs(T, D).
ir_declares([], _, []).
ir_declares([N-_|Es], Ds, Decls) :- memberchk(N, Ds), !, ir_declares(Es, Ds, Decls).
ir_declares([N-T|Es], Ds, [D|Decls]) :-
    ccl_resolve_type(T, T1),
    (   T1 = fn(RT, Ps, Var) -> ir_type(RT, RL), ir_param_lls(Ps, PLs), ( Var == true -> append(PLs, ['...'], PLs1) ; PLs1 = PLs ), ir_join(PLs1, ', ', PL),
            atomic_list_concat(['declare ', RL, ' @', N, '(', PL, ')'], D)
    ;   ir_type(T, LL), atomic_list_concat(['@', N, ' = external global ', LL], D) ),
    ir_declares(Es, Ds, Decls).
ir_param_lls([], []).
ir_param_lls([param(T, _)|Ps], [LL|LLs]) :- ccl_resolve_type(T, T1), ( T1 = arr(_, _) -> LL = ptr ; ir_type(T, LL) ), ir_param_lls(Ps, LLs).
%% joins go through codes: atomic_list_concat/2 dies silently past ~8 KB
%% (a cocolog finding), atom_codes/2 takes hundreds of KB
ir_join(Xs, Sep, A) :- atom_codes(Sep, SC), ir_join_codes(Xs, SC, Cs), atom_codes(A, Cs).
ir_join_codes([], _, []).
ir_join_codes([X], _, C) :- !, ir_codes(X, C).
ir_join_codes([X|Xs], S, C) :- ir_codes(X, C0), ir_join_codes(Xs, S, C1), append(C0, S, C01), append(C01, C1, C).
ir_codes(X, C) :- ( number(X) -> number_codes(X, C) ; atom_codes(X, C) ).
