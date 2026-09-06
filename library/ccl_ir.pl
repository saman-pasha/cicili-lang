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
%% statement expressions; unions (a scalar of the union's alignment, padded,
%% every member at its address), bitfields (a struct's shape follows its C
%% layout, a run of bitfields one [K x i8] read and written through masks),
%% static locals (a private global of the function's). Not yet: VLAs,
%% long double, _Complex -- each throws error(not_lowered(What), where(F)).
%%
%% A struct by value crosses a call the way the platform's C ABI says (M3):
%% on x86-64 (SysV) a struct of 16 bytes or less is split into eightbytes,
%% each INTEGER (an iN of the bytes it holds) or SSE (float, double,
%% <2 x float>), passed and returned as those pieces; a bigger one is passed
%% in memory (ptr byval) and returned through sret. On arm64 (AAPCS64) 16
%% bytes or less is i64 or [2 x i64], a homogeneous float aggregate [k x T],
%% and a bigger one goes by a pointer to a copy, returned through sret. The
%% host decides (uname -m); ir_abi/2 classifies, ir_fn_sig/6 spells a
%% signature, and a define, a call and a declare all read the same answer.
%%
%% THE SURFACE:
%%   ccl_ir_units(+Units, -IR)     IR the module text, an atom
%%   ccl_ir_function(+Item, -Text) one function, for the curious

:- use_module(library(ccl_infer)).
:- use_module(library(ccl_check)).
:- use_module(library(ccl_cpp)).                                          % M6: the C++ forms desugared to the C below

%% the lowering's version: part of the key of every IR the driver keeps in the
%% store (library(ccl_driver)); BUMP it whenever the check or the lowering
%% changes what they emit, as ccl_reader_version/1 is bumped for the grammar
ccl_lowering_version(8).

ccl_ir_units(Units0, IR) :-
    ir_reset, ccl_scope_init, ir_note_units(Units0),                    % the symbol table, once
    (   ccl_lang(cpp)                                                    % C++ (M6): classes and kin desugared to the C below, over that table,
    ->  ccl_cpp_units(Units0, Units), ccl_scope_init, ir_note_units(Units), ir_cpp_prelude   % then the table again from what came out; new and delete are malloc and free
    ;   Units = Units0 ),
    ccl_check_noted(Units),                                             % the safe part first: a violation is a compile error
    nb_setval('$ir_fdefs', []), nb_setval('$ir_gdefs', []),
    ir_drain_functions(Drains), ccl_items_note(Drains),                 % one drain per struct with an own array (below)
    ir_units(Units), ir_items(Drains),
    ir_assemble(IR).

%% C++ (M6): `new T' is malloc(sizeof(T)) and `delete p' free(p) -- declared
%% here when the file did not, so the check consumes at a delete as at a free
ir_cpp_prelude :-
    ( ccl_gdeclared(malloc, _) -> true ; ccl_gdeclare([malloc-fn(ptr([], base([], [void])), [param(base([], [unsigned, long]), size)], false)]) ),
    ( ccl_gdeclared(free, _) -> true ; ccl_gdeclare([free-fn(base([], [void]), [param(ptr([], base([], [void])), p)], false)]) ).
ir_note_units([]).
ir_note_units([unit(Is)|Us]) :- ccl_items_note(Is), ir_note_units(Us).

ir_units([]).
ir_units([unit(Is)|Us]) :- ir_items(Is), ir_units(Us).
ir_items([]).
ir_items([I|Is]) :- ir_item(I), ir_items(Is).

%% ---- state -----------------------------------------------------------------------
ir_reset :-
    ccl_ensure_globals, ( once(catch(os_env('CCL_IR_TRACE', Tr), _, fail)), Tr \== '' -> nb_setval('$ir_trace', yes) ; nb_setval('$ir_trace', no) ),
    nb_setval('$ir_tcache', []), nb_setval('$ir_abicache', []), nb_setval('$ir_reg', 0), nb_setval('$ir_anons', []), nb_setval('$ir_fn', file), nb_setval('$ir_line', 0), nb_setval('$ir_ret', none), nb_setval('$ir_body', []), nb_setval('$ir_allocas', []), nb_setval('$ir_term', no), nb_setval('$ir_env', [[]]), nb_setval('$ir_defers', [[]]), nb_setval('$ir_loops', []), nb_setval('$ir_strings', []), nb_setval('$ir_structs', []),
    nb_setval('$ir_externs', []), nb_setval('$ir_defined', []), nb_setval('$ir_gmap', []), nb_setval('$ir_ret_abi', scalar),
    nb_setval('$ir_maps', []), nb_setval('$ir_statics', 0),
    ir_arch_init.
ir_get(K, V) :- nb_getval(K, V).                                       % every '$ir_*' key is set by ir_reset / ir_function
%% the host's architecture, once per process: sysv (x86-64) or aapcs (arm64)
ir_arch_init :-                                                                  % the module's compile-time arch (ccl_host_arch/1); uname only without it
    (   once(catch(nb_getval('$ir_arch', _), _, fail)) -> true
    ;   once(catch(ccl_host_arch(M0), _, fail)) -> ( M0 == arm64 -> A = aapcs ; A = sysv ), nb_setval('$ir_arch', A)
    ;   ( once(catch(proc_run('uname -m', 5000, Out, 0), _, fail)), ir_text_atom(Out, M), ( sub_atom(M, _, _, _, arm64) ; sub_atom(M, _, _, _, aarch64) ) -> A = aapcs ; A = sysv ),
        nb_setval('$ir_arch', A) ).
ir_text_atom(Out, A) :- ( atom(Out) -> A = Out ; is_list(Out) -> atom_codes(A, Out) ; A = '' ).
ir_arch(A) :- nb_getval('$ir_arch', A).
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
ir_alloca_aligned(R, LL, Al) :- nb_getval('$ir_allocas', A), atomic_list_concat(['  ', R, ' = alloca ', LL, ', align ', Al], Line), nb_setval('$ir_allocas', [Line|A]).
%% a temporary for a struct crossing a call, over-aligned so every piece's load and store is aligned
ir_tmp(LL, Tmp) :- ir_fresh(Tmp), ir_alloca_aligned(Tmp, LL, 16).
ir_store_at(PL, V, Addr, 0) :- !, ir_ins(['store ', PL, ' ', V, ', ptr ', Addr]).
ir_store_at(PL, V, Addr, Off) :- ir_fresh(G), ir_ins([G, ' = getelementptr inbounds i8, ptr ', Addr, ', i64 ', Off]), ir_ins(['store ', PL, ' ', V, ', ptr ', G]).
ir_load_at(PL, Addr, 0, V) :- !, ir_fresh(V), ir_ins([V, ' = load ', PL, ', ptr ', Addr]).
ir_load_at(PL, Addr, Off, V) :- ir_fresh(G), ir_ins([G, ' = getelementptr inbounds i8, ptr ', Addr, ', i64 ', Off]), ir_fresh(V), ir_ins([V, ' = load ', PL, ', ptr ', G]).
ir_where(where(F, line(L))) :- nb_getval('$ir_fn', F), nb_getval('$ir_line', L).
ir_fail(What) :- ir_where(W), throw(error(not_lowered(What), W)).


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
ir_type(T, LL) :- ccl_cached('$ir_tcache', T, LL, ir_type_nocache(T, LL)).      % asked 2300 times for 170 lines: kept per type term
ir_type_nocache(T, LL) :- ccl_resolve_type(T, T1), ir_type_(T1, LL).
ir_type_(base(_, S), LL) :- !, ir_base(S, LL).
ir_type_(ptr(_, _), ptr) :- !.
ir_type_(ref(_, _), ptr) :- !.                                           % C++: a reference is a pointer in memory
ir_type_(rref(_, _), ptr) :- !.
ir_type_(block(_, _), ptr) :- !.
ir_type_(fn(_, _, _), ptr) :- !.
ir_type_(arr(NE, E), LL) :- !, ir_type(E, EL), ( ccl_const_eval(NE, N) -> true ; N = 0 ), atomic_list_concat(['[', N, ' x ', EL, ']'], LL).   % a flexible member: [0 x T]
ir_type_(T, _) :- ir_fail(type(T)).
ir_base(S, void) :- memberchk(void, S), !.
ir_base(S, double) :- memberchk(double, S), !.
ir_base(S, float) :- memberchk(float, S), !.
ir_base(S, half) :- memberchk('_Float16', S), !.
ir_base(S, i8) :- ( memberchk(char, S) ; memberchk('_Bool', S) ; memberchk(bool, S) ), !.   % C++'s bool: a byte in memory, as clang has it
ir_base(S, i16) :- memberchk(short, S), !.
ir_base(S, i64) :- memberchk(long, S), !.
ir_base(S, i32) :- ( memberchk(int, S) ; memberchk(unsigned, S) ; memberchk(signed, S) ), !.
ir_base([enum(_, _)], i32) :- !.
ir_base([enum_class(_, _)], i32) :- !.
ir_base([class(_, N, _, _)], _) :- !, ir_fail(class(N)).                 % M6's next step
ir_base(S, _) :- memberchk(auto, S), !, ir_fail(auto).
ir_base([struct(Tag, Ms)], LL) :- !, ir_struct(Tag, Ms, LL).
%% a union is a scalar of its alignment (so it lies where C puts it) padded
%% to its size; every member is read and written at its address
ir_base([union(Tag, Ms0)], LL) :- !,
    ( Ms0 == none -> ( ccl_tag(Tag, Ms) -> true ; ir_fail(union(Tag)) ) ; Ms = Ms0 ),
    ccl_union_layout(Ms, 0, 1, N, A), ir_union_type(N, A, LL).
ir_base([typedef(N)], _) :- !, ir_fail(typedef(N)).
ir_base(S, _) :- ir_fail(specs(S)).
ir_union_type(N, A, LL) :-
    ( A >= 8 -> H = i64, HS = 8 ; A =:= 4 -> H = i32, HS = 4 ; A =:= 2 -> H = i16, HS = 2 ; H = i8, HS = 1 ),
    Pad is N - HS,
    ( HS =:= 1 -> atomic_list_concat(['[', N, ' x i8]'], LL)
    ; Pad =:= 0 -> atomic_list_concat(['{ ', H, ' }'], LL)
    ; atomic_list_concat(['{ ', H, ', [', Pad, ' x i8] }'], LL) ).
ir_is_union(T) :- ccl_resolve_type(T, base(_, [union(_, _)])).
%% a struct type is named once, shaped from its layout (ir_struct_shape/3)
ir_struct(Tag, Ms0, Name) :-
    ( Ms0 == none -> ( ccl_tag(Tag, Ms) -> true ; ir_fail(struct(Tag)) ) ; Ms = Ms0 ),
    ( Tag == anon -> ir_anon_name(Ms, Name) ; atom_concat('%struct.', Tag, Name) ),
    nb_getval('$ir_structs', Ss),
    (   memberchk(Name-_, Ss) -> true
    ;   nb_setval('$ir_structs', [Name-pending|Ss]),
        ir_struct_shape(Ms, Elems, Map), ir_join(Elems, ', ', Body),
        atomic_list_concat([Name, ' = type { ', Body, ' }'], Def),
        nb_getval('$ir_structs', Ss1), ir_replace(Ss1, Name, Def, Ss2), nb_setval('$ir_structs', Ss2),
        nb_getval('$ir_maps', Maps), nb_setval('$ir_maps', [Name-shape(Elems, Map)|Maps]) ).
%% the LLVM shape of a struct, from its C layout: an element per plain member,
%% one [K x i8] per run of bitfields (the bytes their bits span; runs split
%% where a byte is not shared), padding wherever C's offset is past LLVM's
%% natural one and at the tail; the map says which element a member is and,
%% for a bitfield, its bits within the run: m(Name, Index, T, none | bf(RunLL, BitOff, Width, Signed))
ir_struct_shape(Ms, Elems, Map) :-
    ccl_members_layout(Ms, Lays, Size, _),
    ir_shape(Lays, 0, 0, Elems0, Map, Cur),
    ( Size > Cur -> Pad is Size - Cur, atomic_list_concat(['[', Pad, ' x i8]'], PadEl), append(Elems0, [PadEl], Elems) ; Elems = Elems0 ).
ir_shape([], Cur, _, [], [], Cur).
ir_shape([lay(N, T, Off, none)|Ls], Cur, Idx, Elems, Map, End) :- !,
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), ccl_round_up(Cur, A, Nat), ir_type(T, LL),
    ir_pad_to(Off, Nat, Cur, Idx, Elems, Elems1, Idx1),
    Elems1 = [LL|Elems2], Cur1 is Off + S, Idx2 is Idx1 + 1,
    Map = [m(N, Idx1, T, none)|Map1],
    ir_shape(Ls, Cur1, Idx2, Elems2, Map1, End).
ir_shape([lay(N, T, Off, Bits)|Ls], Cur, Idx, Elems, Map, End) :-
    ir_bit_run([lay(N, T, Off, Bits)|Ls], none, none, Run, Rest, Start, Last),
    K is Last - Start + 1,
    ir_pad_to(Start, Start, Cur, Idx, Elems, Elems1, Idx1),
    atomic_list_concat(['[', K, ' x i8]'], El), Elems1 = [El|Elems2], RBits is K * 8, atom_concat(i, RBits, RunLL),
    ir_run_map(Run, Idx1, Start, RunLL, Map1), append(Map1, Map2, Map),
    Cur1 is Start + K, Idx2 is Idx1 + 1,
    ir_shape(Rest, Cur1, Idx2, Elems2, Map2, End).
%% padding when the member's offset is past where LLVM would put it
ir_pad_to(Off, Nat, Cur, Idx, Elems, Elems1, Idx1) :-
    ( Off > Nat, Off > Cur -> Pad is Off - Cur, atomic_list_concat(['[', Pad, ' x i8]'], PadEl), Elems = [PadEl|Elems1], Idx1 is Idx + 1 ; Elems = Elems1, Idx1 = Idx ).
%% the consecutive bitfields whose bytes chain (each one's first byte within the run so far)
ir_bit_run([lay(N, T, Off, bits(BOff, W, U))|Ls], S0, L0, [lay(N, T, Off, bits(BOff, W, U))|Run], Rest, Start, Last) :-
    First is Off + BOff // 8, LastB is Off + (BOff + W - 1) // 8,
    ( S0 == none -> true ; First =< L0 + 0 ), !,
    ( S0 == none -> S1 = First ; S1 = S0 ), ( L0 == none -> L1 = LastB ; L1 is max(L0, LastB) ),
    ir_bit_run(Ls, S1, L1, Run, Rest, Start, Last).
ir_bit_run(Ls, Start, Last, [], Ls, Start, Last).
ir_run_map([], _, _, _, []).
ir_run_map([lay(N, T, Off, bits(BOff, W, _))|Ls], Idx, Start, RunLL, [m(N, Idx, T, bf(RunLL, ROff, W, Signed))|Ms]) :-
    ROff is Off * 8 + BOff - Start * 8, ( ir_signed(T) -> Signed = true ; Signed = false ),
    ir_run_map(Ls, Idx, Start, RunLL, Ms).
%% a member's slot: an address, or bf(Address, RunLL, BitOff, Width, Signed) for a bitfield
ir_member_slot(Base, ST, N, Slot, T) :-
    (   ir_is_union(ST) -> ( ccl_member_type(ST, N, T) -> Slot = Base ; ir_fail(no_member(N, ST)) )
    ;   ir_type(ST, SLL), nb_getval('$ir_maps', Maps), memberchk(SLL-shape(_, Map), Maps), memberchk(m(N, Idx, T, BF), Map)
    ->  ir_fresh(P), ir_ins([P, ' = getelementptr inbounds ', SLL, ', ptr ', Base, ', i32 0, i32 ', Idx]),
        ( BF == none -> Slot = P ; BF = bf(RunLL, Off, W, Signed), Slot = bf(P, RunLL, Off, W, Signed) )
    ;   ir_fail(no_member(N, ST)) ).
ir_slot_addr(bf(_, _, _, _, _), _) :- !, ir_fail(address_of_bitfield).
ir_slot_addr(A, A).
%% a load from a slot (an array decays to its address); a bitfield's bits shifted out of its run
ir_load_slot(Slot, T, V) :- ir_type(T, LL), ir_load_slot(Slot, T, LL, V).
ir_load_slot(bf(P, RunLL, Off, W, Signed), _, LL, V) :- !,
    ir_fresh(U), ir_ins([U, ' = load ', RunLL, ', ptr ', P, ', align 1']),
    ir_bits(RunLL, K), Sh1 is K - Off - W, Sh2 is K - W,
    ( Sh1 =:= 0 -> V1 = U ; ir_fresh(V1), ir_ins([V1, ' = shl ', RunLL, ' ', U, ', ', Sh1]) ),
    ( Signed == true -> Op = ashr ; Op = lshr ),
    ( Sh2 =:= 0 -> V2 = V1 ; ir_fresh(V2), ir_ins([V2, ' = ', Op, ' ', RunLL, ' ', V1, ', ', Sh2]) ),
    ir_int_convert(V2, RunLL, Signed, LL, V).
ir_load_slot(A, T, LL, V) :- ir_load_or_decay(A, T, LL, V).
%% a store to a slot; a bitfield's bits masked into its run
ir_store_slot(Slot, T, V) :- ir_type(T, LL), ir_store_slot(Slot, T, LL, V).
ir_store_slot(bf(P, RunLL, Off, W, _), _, LL, V) :- !,
    ir_bits(RunLL, K), Mask is (1 << W) - 1, ir_iconst(Mask, K, MaskLit),
    ( K < 64 -> Clear is ((1 << K) - 1) - (Mask << Off) ; Clear is \ (Mask << Off) ), ir_iconst(Clear, K, ClearLit),
    ir_fresh(U), ir_ins([U, ' = load ', RunLL, ', ptr ', P, ', align 1']),
    ir_fresh(C), ir_ins([C, ' = and ', RunLL, ' ', U, ', ', ClearLit]),
    ir_int_convert(V, LL, false, RunLL, V1),
    ir_fresh(M), ir_ins([M, ' = and ', RunLL, ' ', V1, ', ', MaskLit]),
    ( Off =:= 0 -> S = M ; ir_fresh(S), ir_ins([S, ' = shl ', RunLL, ' ', M, ', ', Off]) ),
    ir_fresh(R), ir_ins([R, ' = or ', RunLL, ' ', C, ', ', S]),
    ir_ins(['store ', RunLL, ' ', R, ', ptr ', P, ', align 1']).
ir_store_slot(A, _, LL, V) :- ir_ins(['store ', LL, ' ', V, ', ptr ', A]).
%% an integer constant as LLVM writes it for iK: two's complement when the top bit is set
ir_iconst(Val, K, Lit) :- ( K < 64, Val >= 1 << (K - 1) -> Lit is Val - (1 << K) ; Lit = Val ).
%% an integer of one width to another
ir_int_convert(V, FL, Signed, TL, V1) :-
    ir_bits(FL, FB), ir_bits(TL, TB),
    (   FB =:= TB -> V1 = V
    ;   FB > TB -> ir_op1(trunc, FL, V, TL, V1)
    ;   Signed == true -> ir_op1(sext, FL, V, TL, V1)
    ;   ir_op1(zext, FL, V, TL, V1) ).
%% an anonymous struct is named by its members, in a registry of its own --
%% not in '$ir_structs', where a name means "defined"
ir_anon_name(Ms, Name) :-
    nb_getval('$ir_anons', As),
    ( member(N-Ms0, As), Ms0 == Ms -> Name = N
    ; length(As, K), atomic_list_concat(['%struct.anon.', K], Name), nb_setval('$ir_anons', [Name-Ms|As]) ).
ir_replace([], _, _, []).
ir_replace([N-_|T], N, D, [N-D|T]) :- !.
ir_replace([X|T], N, D, [X|T1]) :- ir_replace(T, N, D, T1).
ir_member_index(T, N, I, MT) :- ccl_members_of(T, Ms), ir_member_index_(Ms, N, 0, I, MT), !.
ir_member_index(T, N, _, _) :- ir_fail(no_member(N, T)).
ir_member_index_([member(MT, N, _)|_], N, I, I, MT) :- !.
ir_member_index_([_|Ms], N, I0, I, MT) :- I1 is I0 + 1, ir_member_index_(Ms, N, I1, I, MT).

%% ---- the ABI of a struct by value --------------------------------------------------
%% ir_abi(+T, -Abi): scalar | direct([piece(LL, ByteOffset) ...]) | memory(LL, Align) | indirect(LL, Align)
ir_abi(T, Abi) :- ccl_cached('$ir_abicache', T, Abi, ir_abi_nocache(T, Abi)).      % once per type: a struct's leaves and eightbytes are walked at every call site
ir_abi_nocache(T, Abi) :-
    ccl_resolve_type(T, T1),
    (   ir_is_aggregate(T1) -> ir_type(T1, LL), ccl_size_align(T1, N, A), ir_arch(Arch), ir_abi_(Arch, T1, LL, N, A, Abi)
    ;   Abi = scalar ).
ir_is_aggregate(base(_, [struct(_, Ms)])) :- Ms \== none.
ir_is_aggregate(base(_, [union(_, Ms)])) :- Ms \== none.
ir_abi_(sysv, T, LL, N, A, Abi) :- ( N > 16 -> Abi = memory(LL, A) ; ir_leaves(T, 0, Ls), ir_eightbytes(Ls, N, 0, Ps), Abi = direct(Ps) ).
ir_abi_(aapcs, T, LL, N, A, Abi) :-
    (   N > 16 -> Abi = indirect(LL, A)
    ;   ir_leaves(T, 0, Ls), ir_hfa(Ls, K, FT) -> atomic_list_concat(['[', K, ' x ', FT, ']'], P), Abi = direct([piece(P, 0)])
    ;   N =< 8 -> Abi = direct([piece(i64, 0)])
    ;   Abi = direct([piece('[2 x i64]', 0)]) ).
%% the scalar leaves of a type, each at its byte offset: int | float | double
ir_leaves(T, Off, Ls) :-
    ccl_resolve_type(T, T1),
    (   T1 = base(_, [struct(_, Ms)]), Ms \== none -> ir_member_leaves(Ms, Off, 0, Ls)
    ;   T1 = base(_, [union(_, Ms)]), Ms \== none -> ir_union_leaves(Ms, Off, Ls)
    ;   T1 = arr(int(K), E) -> ccl_size_align(E, ES, _), ir_array_leaves(K, E, ES, Off, Ls)
    ;   ir_is_fp(T1) -> ( T1 = base(_, S), memberchk(float, S) -> Ls = [leaf(Off, float)] ; Ls = [leaf(Off, double)] )
    ;   Ls = [leaf(Off, int)] ).
ir_member_leaves(Ms, Base, _, Ls) :- ccl_members_layout(Ms, Lays, _, _), ir_lay_leaves(Lays, Base, Ls).
ir_lay_leaves([], _, []).
ir_lay_leaves([lay(_, T, Off, Bits)|Lays], Base, Ls) :-
    AbsOff is Base + Off,
    ( Bits == none -> ir_leaves(T, AbsOff, L1) ; L1 = [leaf(AbsOff, int)] ),
    ir_lay_leaves(Lays, Base, L2), append(L1, L2, Ls).
ir_union_leaves([], _, []).
ir_union_leaves([member(MT, _, _)|Ms], Off, Ls) :- ir_leaves(MT, Off, L1), ir_union_leaves(Ms, Off, L2), append(L1, L2, Ls).
ir_array_leaves(0, _, _, _, []) :- !.
ir_array_leaves(K, E, ES, Off, Ls) :- ir_leaves(E, Off, L1), K1 is K - 1, Off1 is Off + ES, ir_array_leaves(K1, E, ES, Off1, L2), append(L1, L2, Ls).
%% SysV: each eightbyte is INTEGER when any integer or pointer lies in it, else SSE
ir_eightbytes(_, N, Off, []) :- Off >= N, !.
ir_eightbytes(Ls, N, Off, [piece(P, Off)|Ps]) :-
    End is Off + 8, ir_leaves_in(Ls, Off, End, Cs), Bytes is min(N - Off, 8),
    (   memberchk(int, Cs) -> Bits is Bytes * 8, atom_concat(i, Bits, P)
    ;   memberchk(double, Cs) -> P = double
    ;   Cs == [float, float] -> P = '<2 x float>'
    ;   Cs == [float] -> P = float
    ;   Bits is Bytes * 8, atom_concat(i, Bits, P) ),
    ir_eightbytes(Ls, N, End, Ps).
ir_leaves_in([], _, _, []).
ir_leaves_in([leaf(O, C)|Ls], Off, End, Cs) :- ( O >= Off, O < End -> Cs = [C|Cs1] ; Cs = Cs1 ), ir_leaves_in(Ls, Off, End, Cs1).
%% AAPCS64: a homogeneous floating-point aggregate, up to four of one kind
ir_hfa([leaf(_, FT)|Ls], K, FT) :- memberchk(FT, [float, double]), ir_all_leaves(Ls, FT), length(Ls, K0), K is K0 + 1, K =< 4.
ir_all_leaves([], _).
ir_all_leaves([leaf(_, C)|Ls], C) :- ir_all_leaves(Ls, C).
%% the LLVM type a direct struct is passed or returned as
ir_pieces_type([piece(P, _)], P) :- !.
ir_pieces_type([piece(P1, _), piece(P2, _)], CL) :- atomic_list_concat(['{ ', P1, ', ', P2, ' }'], CL).
ir_piece_lls([], []).
ir_piece_lls([piece(P, _)|Ps], [P|Ls]) :- ir_piece_lls(Ps, Ls).
ir_sret_attr(memory(LL, A), S) :- atomic_list_concat(['ptr sret(', LL, ') align ', A], S).
ir_sret_attr(indirect(LL, A), S) :- atomic_list_concat(['ptr sret(', LL, ') align ', A], S).
%% a parameter's type (an array decays) and its ABI
ir_param_abi(T, PT, Abi) :- ccl_resolve_type(T, T1), ( T1 = arr(_, E) -> PT = ptr([], E) ; PT = T ), ir_abi(PT, Abi).
%% a parameter's LLVM types with their attributes (a define, a declare), and plain (a call's type list)
ir_abi_lls(scalar, T, [LL]) :- ir_type(T, LL).
ir_abi_lls(direct(Pcs), _, LLs) :- ir_piece_lls(Pcs, LLs).
ir_abi_lls(memory(LL, A), _, [S]) :- atomic_list_concat(['ptr byval(', LL, ') align ', A], S).
ir_abi_lls(indirect(_, _), _, [ptr]).
%% a function type's signature: the return LL (void, with an sret parameter
%% first, when the struct is returned in memory) and the parameters' LLs
ir_fn_sig(RT, Ps, Var, RetLL, RetAbi, ParamLLs) :-
    ir_abi(RT, RetAbi),
    (   RetAbi = scalar -> ir_type(RT, RetLL), Lead = []
    ;   RetAbi = direct(Pcs) -> ir_pieces_type(Pcs, RetLL), Lead = []
    ;   ir_sret_attr(RetAbi, Sret), RetLL = void, Lead = [Sret] ),
    ir_params_lls(Ps, PLs), append(Lead, PLs, ParamLLs0),
    ( Var == true -> append(ParamLLs0, ['...'], ParamLLs) ; ParamLLs = ParamLLs0 ).
ir_params_lls([], []).
ir_params_lls([param(T, _)|Ps], LLs) :- ir_param_abi(T, PT, Abi), ir_abi_lls(Abi, PT, L1), ir_params_lls(Ps, L2), append(L1, L2, LLs).

ir_signed(T) :- ccl_resolve_type(T, base(_, S)), \+ memberchk(unsigned, S).
ir_is_ptr(T) :- ccl_is_pointer(T).
ir_is_fp(T) :- ccl_is_float(T).
ir_is_int(T) :- ccl_is_integer(T).
ir_int(base([], [int])).
ir_long(base([], [long])).
ir_elem(ptr(_, E), E) :- !.
ir_elem(arr(_, E), E) :- !.
ir_elem(T, E) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ; T1 = block(_, E) ), !.
ir_elem(T, _) :- ir_fail(not_a_pointer(T)).
ir_zero(LL, Z) :- ( LL == ptr -> Z = null ; ( LL == double ; LL == float ) -> Z = '0.0' ; sub_atom(LL, 0, 1, _, 'i') -> Z = 0 ; Z = zeroinitializer ).

%% ---- conversions -------------------------------------------------------------------
ir_convert(V, From, To, V1) :- ir_type(From, FL), ir_type(To, TL), ir_convert(V, From, FL, To, TL, V1).
%% with both LLVM types in hand (the value's travels with it, the target's the caller has)
ir_convert(V, From, FL, To, TL, V1) :-
    (   ir_is_bool(To), \+ ir_is_bool(From) -> ir_to_bool(V, From, FL, V1)   % C++: a bool is 0 or 1, whatever came
    ;   FL == TL -> V1 = V
    ;   ir_fp_ll(FL), ir_fp_ll(TL) -> ( ir_fp_wider(TL, FL) -> Op = fpext ; Op = fptrunc ), ir_op1(Op, FL, V, TL, V1)
    ;   ir_fp_ll(FL) -> ( ir_signed(To) -> Op = fptosi ; Op = fptoui ), ir_op1(Op, FL, V, TL, V1)
    ;   ir_fp_ll(TL) -> ( ir_signed(From) -> Op = sitofp ; Op = uitofp ), ir_op1(Op, FL, V, TL, V1)
    ;   ( FL == ptr ; ir_isfn(From) ), TL == ptr -> V1 = V
    ;   FL == ptr -> ir_op1(ptrtoint, FL, V, TL, V1)
    ;   TL == ptr -> ir_op1(inttoptr, FL, V, TL, V1)
    ;   ir_bits(FL, FB), ir_bits(TL, TB), FB > TB -> ir_op1(trunc, FL, V, TL, V1)
    ;   ir_signed(From) -> ir_op1(sext, FL, V, TL, V1)
    ;   ir_op1(zext, FL, V, TL, V1) ).
ir_isfn(T) :- ccl_resolve_type(T, fn(_, _, _)).
ir_is_bool(T) :- ccl_resolve_type(T, base(_, S)), memberchk(bool, S), !.
ir_to_bool(V, From, FL, V1) :-
    ir_fresh(C),
    (   ir_fp_ll(FL) -> ir_ins([C, ' = fcmp une ', FL, ' ', V, ', 0.0'])
    ;   ( FL == ptr ; ir_isfn(From) ) -> ir_ins([C, ' = icmp ne ptr ', V, ', null'])
    ;   ir_ins([C, ' = icmp ne ', FL, ' ', V, ', 0']) ),
    ir_fresh(V1), ir_ins([V1, ' = zext i1 ', C, ' to i8']).
ir_op1(Op, FL, V, TL, R) :- ir_fresh(R), ir_ins([R, ' = ', Op, ' ', FL, ' ', V, ' to ', TL]).
ir_bits(LL, N) :- atom_concat(i, A, LL), atom_codes(A, Cs), catch(number_codes(N, Cs), _, fail), !.
%% a value as a condition (i1)
%% `new T' is malloc(sizeof(T)); `new T(v)' for a scalar T stores v into it; a
%% class with a constructor is the next step
ir_new(T, [], cast(ptr([], T), call(id(malloc), [sizeof_type(T)]))) :- !.
ir_new(T, [A], stmt_expr(block([declaration(0, none, T, [var(P, ptr([], T), cast(ptr([], T), call(id(malloc), [sizeof_type(T)])))]), expr(0, assign('=', deref(id(P)), A)), expr(0, id(P))]))) :-
    ccl_resolve_type(T, T1), \+ T1 = base(_, [struct(_, _)]), \+ T1 = base(_, [class(_, _, _, _)]), !, ccl_gensym('$new', P).
ir_new(T, _, _) :- ir_fail(new_with_constructor(T)).
ir_cond(E, C) :- ir_cmp_op(E, _), !, ir_expr_i1(E, C).
ir_cond(E, C) :-
    ir_expr(E, V, _, LL),
    ( ir_fp_ll(LL) -> ir_fresh(C), ir_ins([C, ' = fcmp une ', LL, ' ', V, ', 0.0'])
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

%% ---- expressions: a value, its C type, and its LLVM type ------------------------------------
%% ir_expr(+E, -V, -T, -LL): the value, the C type (resolved where the
%% lowering resolved it) and the LLVM type of the value -- `ptr' for an array
%% that decayed, whatever ir_type/2 says of the array. The LLVM type travels
%% with the value so the consumers (a conversion, a store, an arithmetic
%% instruction, a condition) stop deriving it again from the C type: half
%% the lowering's 50,000 calls were the type machinery asked twice.
ir_expr(E, V, T) :- ir_expr(E, V, T, _).
ir_expr(int(N), N, T, LL) :- !, ( ( N > 2147483647 ; N < -2147483648 ) -> ir_long(T), LL = i64 ; ir_int(T), LL = i32 ).
ir_expr(float(F), A, base([], [double]), double) :- !, ir_double(F, A).
ir_expr(chr(C), C, T, i32) :- !, ir_int(T).
ir_expr(str(S), Ref, ptr([], base([], [char])), ptr) :- !, ir_string(S, Ref).
ir_expr(id(N), V, T, i32) :- ccl_enum_value(N, V), !, ir_int(T).          % an enumerator is its value
ir_expr(id(N), V, T, LL) :- !,
    ( ir_lookup(N, loc(Addr0, T00)) -> true ; ir_fail(undeclared(N)) ),
    ir_ref_slot(Addr0, T00, Addr, T0),
    ccl_resolve_type(T0, T1),
    (   T1 = arr(_, E) -> V = Addr, T = ptr([], E), LL = ptr
    ;   T1 = fn(_, _, _) -> V = Addr, T = ptr([], T0), LL = ptr
    ;   ir_type(T1, LL), ir_fresh(V), ir_ins([V, ' = load ', LL, ', ptr ', Addr]), T = T1 ).
ir_expr(call(F, Args), V, RT, LL) :- !,
    ir_moved_args(F, Args, Args1),
    (   F = id(free), Args1 = [E], ir_drain_free(E, S) -> ir_expr(S, V, RT, LL)
    ;   ir_call(F, Args1, V0, RT0),
        (   ( RT0 = ref(_, RT1) ; RT0 = rref(_, RT1) ) -> ccl_resolve_type(RT1, RT), ir_type(RT, LL), ir_fresh(V), ir_ins([V, ' = load ', LL, ', ptr ', V0])   % C++: a reference result is what it refers to
        ;   V = V0, RT = RT0, ir_type(RT, LL) ) ).
%% C++ (M6): the forms that are C with names
ir_expr(bool(true), 1, base([], [bool]), i8) :- !.
ir_expr(bool(false), 0, base([], [bool]), i8) :- !.
ir_expr(nullptr, null, ptr([], base([], [void])), ptr) :- !.
ir_expr(scoped(_, N), V, T, LL) :- !, ir_expr(id(N), V, T, LL).
ir_expr(ccast(_, T, E), V, T1, LL) :- !, ir_expr(cast(T, E), V, T1, LL).
ir_expr(new(T, Args), V, T1, LL) :- !, ir_new(T, Args, E), ir_expr(E, V, T1, LL).
ir_expr(new_array(T, N), V, T1, LL) :- !,
    ir_expr(cast(ptr([], T), call(id(malloc), [bin('*', cast(base([], [unsigned, long]), N), sizeof_type(T))])), V, T1, LL).
ir_expr(delete(E), V, T, LL) :- !, ir_expr(call(id(free), [E]), V, T, LL).
ir_expr(delete_array(E), V, T, LL) :- !, ir_expr(call(id(free), [E]), V, T, LL).
ir_expr(lambda(_, _, _, _), _, _, _) :- !, ir_fail(lambda).
ir_expr(throw(_), _, _, _) :- !, ir_fail(throw).
ir_expr(drain_free(E), V, RT, LL) :- !, ir_call(id(free), [E], V, RT), ir_type(RT, LL).          % the lowering's own free, past the drain
ir_expr(assign('=', L, R), V, LT, LL) :- ir_own_elem(L), !, ir_elem_assign(L, R, S), ir_expr(S, V, LT, LL).   % an own array's element: the old one freed
ir_expr(assign('=', L, R), V, LT, LL) :- !,
    ir_lval(L, Slot, LT, LL), ir_expr(R, V0, RT, RL), ir_convert(V0, RT, RL, LT, LL, V), ir_store_slot(Slot, LT, LL, V).
ir_expr(assign(Op, L, R), V, LT, LL) :- !,
    atom_concat(BinOp, '=', Op), ir_lval(L, Slot, LT, LL),
    ir_load_slot(Slot, LT, LL, Cur),
    ir_binary(BinOp, Cur, LT, LL, R, V0, RT, RL), ir_convert(V0, RT, RL, LT, LL, V), ir_store_slot(Slot, LT, LL, V).
ir_expr(bin('&&', A, B), V, T, i32) :- !, ir_int(T),
    ir_label(LB), ir_label(LE), ir_cond(A, CA), ir_cur_label(LA0), ir_end(['br i1 ', CA, ', label %', LB, ', label %', LE]),
    ir_block(LB), ir_cond(B, CB), ir_cur_label(LB1), ir_end(['br label %', LE]),
    ir_block(LE), ir_fresh(C), ir_ins([C, ' = phi i1 [ false, %', LA0, ' ], [ ', CB, ', %', LB1, ' ]']), ir_bool(C, V).
ir_expr(bin('||', A, B), V, T, i32) :- !, ir_int(T),
    ir_label(LB), ir_label(LE), ir_cond(A, CA), ir_cur_label(LA0), ir_end(['br i1 ', CA, ', label %', LE, ', label %', LB]),
    ir_block(LB), ir_cond(B, CB), ir_cur_label(LB1), ir_end(['br label %', LE]),
    ir_block(LE), ir_fresh(C), ir_ins([C, ' = phi i1 [ true, %', LA0, ' ], [ ', CB, ', %', LB1, ' ]']), ir_bool(C, V).
ir_expr(bin(Op, A, B), V, T, i32) :- ir_cmp_op(bin(Op, A, B), _), !, ir_int(T), ir_expr_i1(bin(Op, A, B), C), ir_bool(C, V).
ir_expr(bin(Op, A, B), V, T, LL) :- !, ir_expr(A, VA, TA, LA), ir_binary(Op, VA, TA, LA, B, V, T, LL).
ir_expr(neg(E), V, T, LL) :- !, ir_expr(E, V0, T0, L0), ccl_promote(T0, T), ir_type(T, LL), ir_convert(V0, T0, L0, T, LL, V1),
    ir_fresh(V), ( ir_fp_ll(LL) -> ir_ins([V, ' = fneg ', LL, ' ', V1]) ; ir_signed(T) -> ir_ins([V, ' = sub nsw ', LL, ' 0, ', V1]) ; ir_ins([V, ' = sub ', LL, ' 0, ', V1]) ).
ir_expr(pos(E), V, T, LL) :- !, ir_expr(E, V, T, LL).
ir_expr(bitnot(E), V, T, LL) :- !, ir_expr(E, V0, T0, L0), ccl_promote(T0, T), ir_type(T, LL), ir_convert(V0, T0, L0, T, LL, V1), ir_fresh(V), ir_ins([V, ' = xor ', LL, ' ', V1, ', -1']).
ir_expr(not(E), V, T, i32) :- !, ir_int(T), ir_cond(E, C), ir_fresh(C1), ir_ins([C1, ' = xor i1 ', C, ', true']), ir_bool(C1, V).
ir_expr(addr(E), Addr, ptr([], T), ptr) :- !, ir_lval(E, Slot, T, _), ir_slot_addr(Slot, Addr).
ir_expr(deref(E), V, T, LL) :- !, ir_lval(deref(E), Slot, T, LT), ir_load_slot(Slot, T, LT, V), ir_value_ll(LT, LL).
ir_expr(index(A, I), V, T, LL) :- !, ir_lval(index(A, I), Slot, T, LT), ir_load_slot(Slot, T, LT, V), ir_value_ll(LT, LL).
ir_expr(member(E, N), V, T, LL) :- !, ir_lval(member(E, N), Slot, T, LT), ir_load_slot(Slot, T, LT, V), ir_value_ll(LT, LL).
ir_expr(arrow(E, N), V, T, LL) :- !, ir_lval(arrow(E, N), Slot, T, LT), ir_load_slot(Slot, T, LT, V), ir_value_ll(LT, LL).
ir_expr(preinc(E), V, T, LL) :- !, ir_step(E, add, pre, V, T, LL).
ir_expr(predec(E), V, T, LL) :- !, ir_step(E, sub, pre, V, T, LL).
ir_expr(postinc(E), V, T, LL) :- !, ir_step(E, add, post, V, T, LL).
ir_expr(postdec(E), V, T, LL) :- !, ir_step(E, sub, post, V, T, LL).
ir_expr(cast(T, E), V, T, LL) :- !, ir_expr(E, V0, T0, L0), ( ccl_resolve_type(T, base(_, [void])) -> V = V0, LL = void ; ir_type(T, LL), ir_convert(V0, T0, L0, T, LL, V) ).
ir_expr(sizeof(E), N, T, i64) :- !, ccl_size_type(T), ccl_type_of(E, ET), ( ccl_size_of(ET, N) -> true ; ir_fail(sizeof(E)) ).
ir_expr(sizeof_type(ET), N, T, i64) :- !, ccl_size_type(T), ( ccl_size_of(ET, N) -> true ; ir_fail(sizeof_type(ET)) ).
ir_expr(cond(C, A, B), V, T, LL) :- !,
    ccl_type_of(A, TA), ccl_type_of(B, TB), ( ccl_is_arith(TA), ccl_is_arith(TB) -> ccl_usual(TA, TB, T) ; T = TA ), ir_type(T, LL),
    ir_label(LT), ir_label(LF), ir_label(LE), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LT, ', label %', LF]),
    ir_block(LT), ir_expr(A, VA0, TA1, LA), ir_convert(VA0, TA1, LA, T, LL, VA), ir_cur_label(LT1), ir_end(['br label %', LE]),
    ir_block(LF), ir_expr(B, VB0, TB1, LB), ir_convert(VB0, TB1, LB, T, LL, VB), ir_cur_label(LF1), ir_end(['br label %', LE]),
    ir_block(LE), ir_fresh(V), ir_ins([V, ' = phi ', LL, ' [ ', VA, ', %', LT1, ' ], [ ', VB, ', %', LF1, ' ]']).
ir_expr(comma(A, B), V, T, LL) :- !, ir_expr(A, _, _, _), ir_expr(B, V, T, LL).
ir_expr(move(E), V, T, LL) :- ir_own_elem(E), !, ir_lval(E, Slot, T, LL), ir_load_slot(Slot, T, LL, V), ir_store_slot(Slot, T, LL, null).   % out of an own array: the slot nulled
ir_expr(move(E), V, T, LL) :- !, ir_expr(E, V, T, LL).                        % a move is the value; the checker did the rest
ir_expr(compound_lit(T, Init), V, T1, LL) :- !,
    ir_fresh(Addr), ir_alloca_typed(Addr, T), ir_init(Addr, T, Init), ir_load_or_decay(Addr, T, V), ccl_resolve_type(T, RT), ( RT = arr(_, E) -> T1 = ptr([], E), LL = ptr ; T1 = T, ir_type(T, LL) ).
ir_expr(stmt_expr(block(Is)), V, T, LL) :- !,
    ir_env_push, ( append(Init, [expr(_, E)], Is) -> ir_stmts(Init), ir_expr(E, V, T, LL) ; ir_stmts(Is), V = none, T = base([], [void]), LL = void ),
    ir_run_defers(1), ir_env_pop.
ir_expr(E, _, _, _) :- ir_fail(expr(E)).
%% the LLVM type of a loaded value: an array decays to its address
ir_value_ll(LT, LL) :- ( sub_atom(LT, 0, 1, _, '[') -> LL = ptr ; LL = LT ).
ir_fp_ll(double). ir_fp_ll(float). ir_fp_ll(half).
ir_fp_wider(double, float). ir_fp_wider(double, half). ir_fp_wider(float, half).

%% the label of the block the last instruction went into (for phis)
ir_cur_label(L) :- nb_getval('$ir_body', B), ir_last_label(B, L).
ir_last_label([Line|T], L) :- ( sub_atom(Line, _, 1, 0, ':'), \+ sub_atom(Line, 0, 1, _, ' ') -> sub_atom(Line, 0, _, 1, L) ; ir_last_label(T, L) ).
ir_last_label([], entry).

ir_load_or_decay(Addr, T, V) :- ir_type(T, LL), ir_load_or_decay(Addr, T, LL, V).
ir_load_or_decay(Addr, T, LL, V) :-
    ( ccl_resolve_type(T, arr(_, _)) -> V = Addr ; ir_fresh(V), ir_ins([V, ' = load ', LL, ', ptr ', Addr]) ).

ir_expr_i1(bin(Op, A, B), C) :-
    ir_expr(A, VA, TA, LA), ir_expr(B, VB, TB, LB),
    (   ( LA == ptr ; LB == ptr ) -> ir_to_ptr(VA, TA, LA, PA), ir_to_ptr(VB, TB, LB, PB), ir_icmp(Op, false, ptr, PA, PB, C)
    ;   ccl_usual(TA, TB, T), ir_type(T, LL), ir_convert(VA, TA, LA, T, LL, A1), ir_convert(VB, TB, LB, T, LL, B1),
        ( ir_fp_ll(LL) -> ir_fcmp(Op, LL, A1, B1, C) ; ( ir_signed(T) -> S = true ; S = false ), ir_icmp(Op, S, LL, A1, B1, C) ) ).
ir_to_ptr(V, T, L, P) :- ( L == ptr -> P = V ; V == 0 -> P = null ; ir_convert(V, T, L, ptr([], base([], [void])), ptr, P) ).
ir_icmp(Op, S, LL, A, B, C) :- ir_icmp_pred(Op, S, P), ir_fresh(C), ir_ins([C, ' = icmp ', P, ' ', LL, ' ', A, ', ', B]).
ir_icmp_pred('==', _, eq). ir_icmp_pred('!=', _, ne).
ir_icmp_pred('<', true, slt). ir_icmp_pred('<', false, ult). ir_icmp_pred('>', true, sgt). ir_icmp_pred('>', false, ugt).
ir_icmp_pred('<=', true, sle). ir_icmp_pred('<=', false, ule). ir_icmp_pred('>=', true, sge). ir_icmp_pred('>=', false, uge).
ir_fcmp(Op, LL, A, B, C) :- ir_fcmp_pred(Op, P), ir_fresh(C), ir_ins([C, ' = fcmp ', P, ' ', LL, ' ', A, ', ', B]).
ir_fcmp_pred('==', oeq). ir_fcmp_pred('!=', une). ir_fcmp_pred('<', olt). ir_fcmp_pred('>', ogt). ir_fcmp_pred('<=', ole). ir_fcmp_pred('>=', oge).

%% a binary arithmetic/bitwise/shift operator over a lowered left operand
ir_binary(Op, VA, TA, LA, B, V, T, LL) :-
    ir_expr(B, VB, TB, LB),
    (   Op == '-', LA == ptr, LB == ptr ->                                          % p - q
            ir_elem(TA, E), ccl_size_of(E, Sz), ir_long(T), LL = i64,
            ir_op1(ptrtoint, ptr, VA, i64, A1), ir_op1(ptrtoint, ptr, VB, i64, B1),
            ir_fresh(D), ir_ins([D, ' = sub i64 ', A1, ', ', B1]), ir_fresh(V), ir_ins([V, ' = sdiv exact i64 ', D, ', ', Sz])
    ;   memberchk(Op, ['+', '-']), LA == ptr -> ir_ptr_add(Op, VA, TA, VB, TB, LB, V), ir_decayed(TA, T), LL = ptr
    ;   Op == '+', LB == ptr -> ir_ptr_add('+', VB, TB, VA, TA, LA, V), ir_decayed(TB, T), LL = ptr
    ;   ccl_usual(TA, TB, T0), ( memberchk(Op, ['<<', '>>']) -> ccl_promote(TA, T) ; T = T0 ),
        ir_type(T, LL), ir_convert(VA, TA, LA, T, LL, A1), ir_convert(VB, TB, LB, T, LL, B1),
        ir_arith_op(Op, T, LL, Ins), ir_fresh(V), ir_ins([V, ' = ', Ins, ' ', LL, ' ', A1, ', ', B1]) ).
ir_decayed(T, D) :- ccl_resolve_type(T, T1), ( T1 = arr(_, E) -> D = ptr([], E) ; D = T ).
ir_ptr_add(Op, P, PT, I, IT, IL, V) :-
    ir_elem(PT, E), ir_type(E, EL), ir_convert(I, IT, IL, base([], [long]), i64, I1),
    ( Op == '-' -> ir_fresh(N), ir_ins([N, ' = sub i64 0, ', I1]) ; N = I1 ),
    ir_fresh(V), ir_ins([V, ' = getelementptr inbounds ', EL, ', ptr ', P, ', i64 ', N]).
%% signed overflow is undefined in C, so signed integer arithmetic is `nsw':
%% LLVM then widens loop counters and drops the sign extensions before an
%% index (every address is `inbounds' for the same reason: past the object
%% is undefined too); together a third of a B-tree's search time
ir_arith_op('+', T, LL, Ins) :- ( ir_fp_ll(LL) -> Ins = fadd ; ir_signed(T) -> Ins = 'add nsw' ; Ins = add ).
ir_arith_op('-', T, LL, Ins) :- ( ir_fp_ll(LL) -> Ins = fsub ; ir_signed(T) -> Ins = 'sub nsw' ; Ins = sub ).
ir_arith_op('*', T, LL, Ins) :- ( ir_fp_ll(LL) -> Ins = fmul ; ir_signed(T) -> Ins = 'mul nsw' ; Ins = mul ).
ir_arith_op('/', T, LL, Ins) :- ( ir_fp_ll(LL) -> Ins = fdiv ; ir_signed(T) -> Ins = sdiv ; Ins = udiv ).
ir_arith_op('%', T, LL, Ins) :- ( ir_fp_ll(LL) -> Ins = frem ; ir_signed(T) -> Ins = srem ; Ins = urem ).
ir_arith_op('&', _, _, and). ir_arith_op('|', _, _, or). ir_arith_op('^', _, _, xor). ir_arith_op('<<', _, _, shl).
ir_arith_op('>>', T, _, Ins) :- ( ir_signed(T) -> Ins = ashr ; Ins = lshr ).

%% ++ and --, on integers, floats and pointers
ir_step(E, Op, When, V, T, LL) :-
    ir_lval(E, Slot, T, LL), ir_load_slot(Slot, T, LL, Cur),
    ir_fresh(New),
    (   LL == ptr -> ir_elem(T, El), ir_type(El, ELL), ( Op == add -> D = 1 ; D = -1 ), ir_ins([New, ' = getelementptr inbounds ', ELL, ', ptr ', Cur, ', i64 ', D])
    ;   ir_fp_ll(LL) -> ( Op == add -> F = fadd ; F = fsub ), ir_ins([New, ' = ', F, ' ', LL, ' ', Cur, ', 1.0'])
    ;   ir_signed(T) -> ir_ins([New, ' = ', Op, ' nsw ', LL, ' ', Cur, ', 1'])
    ;   ir_ins([New, ' = ', Op, ' ', LL, ' ', Cur, ', 1']) ),
    ir_store_slot(Slot, T, LL, New),
    ( When == pre -> V = New ; V = Cur ).

%% ---- own arrays: the drains the source did not write ---------------------------------------
%% `own node *c[4]' holds owners the check cannot tell apart, so the lowering
%% keeps them: every non-null element freed (its own struct drained first)
%% when the struct holding the array is freed -- through one generated
%% function per struct with an own array, ccl_drain_<tag>(T *x), recursive as
%% the type is -- or when a local array's scope ends (a defer registered at
%% the declaration); the old element freed when one is overwritten; the slot
%% nulled when an element is moved out or handed to a consumer.
ir_own_elem(index(A, _)) :- ccl_type_of(A, AT), AT \== unknown, ck_own_array_type(AT).
ir_needs_drain(T) :- ccl_resolve_type(T, T1), T1 = base(_, [struct(_, _)]), ck_has_own_array(T1).
ir_struct_tag(T, Tag) :- ccl_resolve_type(T, base(_, [struct(Tag, _)])).
ir_drain_name(T, D) :- ir_struct_tag(T, Tag), atom_concat(ccl_drain_, Tag, D).
%% the functions: one per tagged struct in the symbol table with an own array
ir_drain_functions(Fns) :-
    nb_getval('$ccl_tags', Tags),
    findall(F, ( member(Tag-Ms, Tags), Tag \== anon, Ms \== none, T = base([], [struct(Tag, Ms)]), ck_has_own_array(T), ir_drain_function(Tag, Ms, F) ), Fns).
ir_drain_function(Tag, Ms, function(0, static, base([], [void]), D, [param(ptr([], base([], [struct(Tag, none)])), x)], false, block(Loops))) :-
    atom_concat(ccl_drain_, Tag, D), ir_array_loops(Ms, id(x), arrow, Loops).
ir_array_loops([], _, _, []).
ir_array_loops([member(MT, F, _)|Ms], Base, How, Loops) :-
    ( How == arrow -> P = arrow(Base, F) ; P = member(Base, F) ),
    (   F \== anon, ck_own_array_type(MT) -> ir_array_bound(MT, Base, How, Bound), ir_drain_loop(P, MT, Bound, Loop), Loops = [Loop|Loops1]
    ;   F \== anon, ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]), ck_has_own_array(MT1) -> ccl_members_of(MT1, Sub), ir_array_loops(Sub, P, member, L0), append(L0, Loops1, Loops)
    ;   Loops = Loops1 ),
    ir_array_loops(Ms, Base, How, Loops1).
%% the bound of an own array member: its constant, or the sibling field it names (`own T *a[n]')
ir_array_bound(MT, Base, How, Bound) :-
    ccl_resolve_type(MT, arr(NE, _)),
    ( ck_const(NE, N) -> Bound = int(N) ; NE = id(B), ( How == arrow -> Bound = arrow(Base, B) ; Bound = member(Base, B) ) ).
%% for (int i = 0; i < Bound; i++) if (a[i]) { ccl_drain_T(a[i]); free(a[i]); }
ir_drain_loop(Path, T, Bound, for(0, decl(base([], [int]), [var(I, base([], [int]), int(0))]), bin('<', id(I), Bound), postinc(id(I)), if(0, Elem, block(Calls), none))) :-
    ccl_resolve_type(T, arr(_, ET)), ccl_gensym(i, I), Elem = index(Path, id(I)),
    (   ccl_resolve_type(ET, ptr(_, PT)), ir_needs_drain(PT), ir_drain_name(PT, D) -> Calls = [expr(0, call(id(D), [Elem])), expr(0, drain_free(Elem))]
    ;   Calls = [expr(0, drain_free(Elem))] ).
%% free(p) of a struct with an own array: the drain first
ir_drain_free(E, S) :-
    ck_strip_move(E, E0), ccl_type_of(E0, T), T \== unknown, ccl_resolve_type(T, ptr(_, PT)), ir_needs_drain(PT), ir_drain_name(PT, D),
    (   E = id(_) -> S = stmt_expr(block([expr(0, call(id(D), [E])), expr(0, drain_free(E))]))
    ;   ccl_gensym(drain, Tmp), ccl_base_of(T, Base),
        S = stmt_expr(block([declaration(0, none, Base, [var(Tmp, T, E)]), expr(0, call(id(D), [id(Tmp)])), expr(0, drain_free(id(Tmp)))])) ).
%% an element handed to a consumer (free, fclose, an own parameter) is moved out: the slot nulled
ir_moved_args(F, Args, Args1) :-
    (   F = id(_) -> Callee = F
    ;   ccl_type_of(F, FT), FT \== unknown, ck_fn_params(FT, Ps) -> Callee = params(Ps)
    ;   Callee = none ),
    ir_moved_args_(Args, Callee, 1, Args1).
ir_moved_args_([], _, _, []).
ir_moved_args_([A|As], Callee, I, [A1|As1]) :-
    ( Callee \== none, A = index(_, _), ir_own_elem(A), ck_consumes(Callee, I) -> A1 = move(A) ; A1 = A ),
    I1 is I + 1, ir_moved_args_(As, Callee, I1, As1).
%% a[i] = R: ({ T **p = &a[i]; T *n = R; if (*p) { drain(*p); free(*p); } *p = n; })
ir_elem_assign(L, R, stmt_expr(block([declaration(0, none, Base, [var(P, ptr([], ET), addr(L))]),
                                      declaration(0, none, Base, [var(N, ET, R)]),
                                      if(0, deref(id(P)), block(Calls), none),
                                      expr(0, assign('=', deref(id(P)), id(N)))]))) :-
    L = index(A, _), ccl_type_of(A, AT), ccl_resolve_type(AT, arr(_, ET)), ccl_base_of(ET, Base),
    ccl_gensym(slot, P), ccl_gensym(new, N),
    (   ccl_resolve_type(ET, ptr(_, PT)), ir_needs_drain(PT), ir_drain_name(PT, D) -> Calls = [expr(0, call(id(D), [deref(id(P))])), expr(0, drain_free(deref(id(P))))]
    ;   Calls = [expr(0, drain_free(deref(id(P))))] ).
%% a local own array: drained at every exit of its scope, as a defer
ir_array_defers([], _).
ir_array_defers([var(N, T, _)|Vs], Sto) :-
    ( Sto \== extern, ck_own_array_type(T) -> ccl_resolve_type(T, arr(NE, _)), ck_const(NE, K), ir_drain_loop(id(N), T, int(K), Loop), ir_defer_push(block([Loop])) ; true ),
    ir_array_defers(Vs, Sto).

%% ---- calls ------------------------------------------------------------------------------
ir_call(id(N), Args, V, RT) :-
    ir_lookup(N, loc(Addr, T0)), ccl_resolve_type(T0, fn(RT, Ps, Var)), !,
    ir_call_(Addr, RT, Ps, Var, Args, V).
ir_call(F, Args, V, RT) :-
    ir_expr(F, FV, FT), ccl_resolve_type(FT, FT1),
    ( FT1 = ptr(_, FnT) -> true ; FnT = FT1 ), ccl_resolve_type(FnT, fn(RT, Ps, Var)), !,
    ir_call_(FV, RT, Ps, Var, Args, V).
ir_call(F, _, _, _) :- ir_fail(call(F)).
%% a call under the ABI: a struct returned in memory gets a temporary as its
%% sret argument, one returned in pieces is stored to a temporary and loaded
%% back as the struct; a struct argument is handed over the same way
ir_call_(Callee, RT, Ps, Var, Args, V) :-
    ir_abi(RT, RetAbi),
    (   ( RetAbi = memory(_, _) ; RetAbi = indirect(_, _) )
    ->  ir_type(RT, RLL), ir_tmp(RLL, Sret), ir_sret_attr(RetAbi, SA), atomic_list_concat([SA, ' ', Sret], LeadPart), Lead = [LeadPart], LeadLL = [ptr], CL = void
    ;   Lead = [], LeadLL = [], ( RetAbi = direct(Pcs) -> ir_pieces_type(Pcs, CL) ; ir_type(RT, CL) ) ),
    ir_args_(Args, Ps, Parts0, PLLs0), append(Lead, Parts0, Parts), append(LeadLL, PLLs0, PLLs), ir_join(Parts, ', ', ArgTxt),
    ( Var == true -> ir_join(PLLs, ', ', PL), atomic_list_concat([CL, ' (', PL, ', ...)'], Sig) ; Sig = CL ),
    (   CL == void
    ->  ir_ins(['call ', Sig, ' ', Callee, '(', ArgTxt, ')']),
        ( RetAbi == scalar -> V = none ; ir_fresh(V), ir_ins([V, ' = load ', RLL, ', ptr ', Sret]) )
    ;   ir_fresh(R), ir_ins([R, ' = call ', Sig, ' ', Callee, '(', ArgTxt, ')']),
        (   RetAbi = direct(_) -> ir_type(RT, RLL2), ir_tmp(RLL2, T2), ir_ins(['store ', CL, ' ', R, ', ptr ', T2]), ir_fresh(V), ir_ins([V, ' = load ', RLL2, ', ptr ', T2])
        ;   V = R ) ).
%% the arguments: each as its parts (a struct in pieces is several), and the plain type of each part
ir_args_([], _, [], []).
ir_args_([A|As], [param(PT0, _)|Ps], Parts, PLLs) :- ( PT0 = ref(_, _) ; PT0 = rref(_, _) ), !,   % C++: a reference parameter takes the argument's address
    ir_ref_of(A, V), atomic_list_concat(['ptr ', V], P1), ir_args_(As, Ps, P2, PLLs2), Parts = [P1|P2], PLLs = [ptr|PLLs2].
ir_args_([A|As], [param(PT0, _)|Ps], Parts, PLLs) :- !,
    ir_param_abi(PT0, PT, Abi), ir_expr(A, V0, T0, L0), ( Abi == scalar -> ir_type(PT, PL), ir_convert(V0, T0, L0, PT, PL, V) ; V = V0 ),
    ir_arg_parts(Abi, PT, V, P1, L1), ir_args_(As, Ps, P2, L2), append(P1, P2, Parts), append(L1, L2, PLLs).
ir_args_([A|As], [], Parts, PLLs) :-                    % the variadic tail: default promotions
    ir_expr(A, V0, T0), ir_promote_arg(V0, T0, V, T), ir_abi(T, Abi),
    ir_arg_parts(Abi, T, V, P1, L1), ir_args_(As, [], P2, L2), append(P1, P2, Parts), append(L1, L2, PLLs).
ir_arg_parts(scalar, T, V, [Part], [LL]) :- ir_type(T, LL), atomic_list_concat([LL, ' ', V], Part).
ir_arg_parts(direct(Pcs), T, V, Parts, LLs) :- ir_type(T, LL), ir_tmp(LL, Tmp), ir_ins(['store ', LL, ' ', V, ', ptr ', Tmp]), ir_piece_loads(Pcs, Tmp, Parts, LLs).
ir_arg_parts(memory(LL, A), _, V, [Part], [ptr]) :- ir_tmp(LL, Tmp), ir_ins(['store ', LL, ' ', V, ', ptr ', Tmp]), atomic_list_concat(['ptr byval(', LL, ') align ', A, ' ', Tmp], Part).
ir_arg_parts(indirect(LL, _), _, V, [Part], [ptr]) :- ir_tmp(LL, Tmp), ir_ins(['store ', LL, ' ', V, ', ptr ', Tmp]), atomic_list_concat(['ptr ', Tmp], Part).
ir_piece_loads([], _, [], []).
ir_piece_loads([piece(P, Off)|Ps], Tmp, [Part|Parts], [P|LLs]) :- ir_load_at(P, Tmp, Off, V), atomic_list_concat([P, ' ', V], Part), ir_piece_loads(Ps, Tmp, Parts, LLs).
ir_promote_arg(V0, T0, V, T) :-
    ( ccl_resolve_type(T0, base(_, S)), memberchk(float, S) -> T = base([], [double]), ir_convert(V0, T0, T, V)
    ; ir_is_int(T0), ccl_int_rank(T0, R, _), R < 3 -> ir_int(T), ir_convert(V0, T0, T, V)
    ; V = V0, T = T0 ).

%% ---- lvalues: an address and the C type there --------------------------------------------
%% ir_lval(+E, -Slot, -T, -LL): the slot, the C type there (resolved) and its LLVM type
ir_lval(E, Slot, T) :- ir_lval(E, Slot, T, _).
ir_lval(id(N), Addr, T, LL) :- !, ( ir_lookup(N, loc(Addr0, T00)) -> true ; ir_fail(undeclared(N)) ), ir_ref_slot(Addr0, T00, Addr, T0), ccl_resolve_type(T0, T), ir_type(T, LL).
ir_lval(scoped(_, N), Addr, T, LL) :- !, ir_lval(id(N), Addr, T, LL).
ir_lval(call(F, Args), Addr, T, LL) :- !,                                 % C++: a call's reference result is a place
    ir_call(F, Args, Addr, RT), ( ( RT = ref(_, T0) ; RT = rref(_, T0) ) -> ccl_resolve_type(T0, T), ir_type(T, LL) ; ir_fail(lvalue(call(F, Args))) ).
%% C++ (M6): a reference's slot holds the address of what it refers to, so a
%% use of the name loads that address first and goes on as the referent
ir_ref_slot(A0, T0, A, T) :- ( T0 = ref(_, T) ; T0 = rref(_, T) ), !, ir_fresh(A), ir_ins([A, ' = load ptr, ptr ', A0]).
ir_ref_slot(A, T, A, T).
%% what a reference is bound to: an lvalue's address, or a call's reference result as it is
ir_ref_of(E, P) :- ir_lvalue_form(E), !, ir_lval(E, P, _, _).
ir_ref_of(call(F, Args), P) :- !, ir_call(F, Args, P, RT), ( ( RT = ref(_, _) ; RT = rref(_, _) ) -> true ; ir_fail(reference_to_value(call(F, Args))) ).
ir_ref_of(E, _) :- ir_fail(reference_to_value(E)).
ir_lvalue_form(id(_)).
ir_lvalue_form(scoped(_, _)).
ir_lvalue_form(index(_, _)).
ir_lvalue_form(member(_, _)).
ir_lvalue_form(arrow(_, _)).
ir_lvalue_form(deref(_)).
ir_lval(deref(E), Addr, T, LL) :- !, ir_expr(E, Addr, PT, _), ir_elem(PT, T), ir_type(T, LL).
ir_lval(index(A, I), Addr, T, LL) :- !,
    ir_expr(A, P, PT, _), ir_elem(PT, T), ir_type(T, LL), ir_expr(I, IV, IT, IL), ir_convert(IV, IT, IL, base([], [long]), i64, I1),
    ir_fresh(Addr), ir_ins([Addr, ' = getelementptr inbounds ', LL, ', ptr ', P, ', i64 ', I1]).
ir_lval(member(E, N), Slot, T, LL) :- !,
    ( ir_lval(E, Base0, ST, _) -> ir_slot_addr(Base0, Base) ; ir_expr(E, SV, ST, SLL), ir_fresh(Base), ir_alloca_typed(Base, ST), ir_ins(['store ', SLL, ' ', SV, ', ptr ', Base]) ),
    ir_member_slot(Base, ST, N, Slot, T), ir_type(T, LL).
ir_lval(arrow(E, N), Slot, T, LL) :- !, ir_expr(E, P, PT, _), ir_elem(PT, ST), ir_member_slot(P, ST, N, Slot, T), ir_type(T, LL).
ir_lval(compound_lit(T, Init), Addr, T, LL) :- !, ir_fresh(Addr), ir_alloca_typed(Addr, T), ir_init(Addr, T, Init), ir_type(T, LL).
ir_lval(E, _, _, _) :- ir_fail(lvalue(E)).
%% an alloca for a value of a C type: a struct or a union aligned as C aligns it
ir_alloca_typed(Addr, T) :-
    ir_type(T, LL), ccl_resolve_type(T, T1),
    ( ( T1 = base(_, [struct(_, _)]) ; T1 = base(_, [union(_, _)]) ), ccl_size_align(T1, _, A) -> ir_alloca_aligned(Addr, LL, A) ; ir_alloca(Addr, LL) ).

%% ---- initializers -------------------------------------------------------------------------
ir_init(_, _, none) :- !.
ir_init(Slot, T, init(Items)) :- !,
    ir_slot_addr(Slot, Addr), ir_type(T, LL), ir_ins(['store ', LL, ' zeroinitializer, ptr ', Addr]), ir_init_items(Items, Addr, T, 0).
ir_init(Slot, T, E) :-
    ccl_resolve_type(T, T1),
    (   T1 = arr(_, El), E = str(S) -> ir_slot_addr(Slot, Addr), ir_type(El, _), ir_init_string(Addr, T1, S)
    ;   ir_expr(E, V0, ET, EL), ir_type(T, TL), ir_convert(V0, ET, EL, T, TL, V), ir_store_slot(Slot, T, TL, V) ).
ir_init_string(Addr, arr(_, _), S) :- append(S, [0], Cs), ir_init_chars(Cs, Addr, 0).
ir_init_chars([], _, _).
ir_init_chars([C|Cs], Addr, I) :- ir_fresh(P), ir_ins([P, ' = getelementptr inbounds i8, ptr ', Addr, ', i64 ', I]), ir_ins(['store i8 ', C, ', ptr ', P]), I1 is I + 1, ir_init_chars(Cs, Addr, I1).
ir_init_items([], _, _, _).
ir_init_items([item(Ds, V)|Is], Addr, T, I) :-
    ccl_resolve_type(T, T1),
    (   Ds = [at(int(K))|Rest] -> I0 = K, Ds1 = Rest
    ;   Ds = [field(F)|Rest] -> ir_member_index(T1, F, I0, _), Ds1 = Rest
    ;   I0 = I, Ds1 = [] ),
    ir_init_slot(Addr, T1, I0, Ds1, V), I1 is I0 + 1, ir_init_items(Is, Addr, T, I1).
ir_init_slot(Addr, arr(_, El), I, Ds, V) :- !,
    ir_type(El, LL), ir_fresh(P), ir_ins([P, ' = getelementptr inbounds ', LL, ', ptr ', Addr, ', i64 ', I]), ir_init_sub(P, El, Ds, V).
ir_init_slot(Addr, ST, I, Ds, V) :-
    ccl_members_of(ST, Ms), I1 is I + 1, ( ccl_nth(I1, Ms, member(MT, N, _)) -> true ; ir_fail(initializer(I)) ),
    ir_member_slot(Addr, ST, N, Slot, MT), ir_init_sub(Slot, MT, Ds, V).
ir_init_sub(P, T, [], V) :- !, ( V = init(_) -> ir_init(P, T, V) ; ir_init(P, T, V) ).
ir_init_sub(P, T, Ds, V) :- ir_init_items([item(Ds, V)], P, T, 0).

%% ---- statements ---------------------------------------------------------------------------
ir_stmts([]).
ir_stmts([S|Ss]) :- ir_stmt(S), ir_stmts(Ss).
ir_stmt(block(Is)) :- !, ir_env_push, ir_stmts(Is), ir_run_defers(1), ir_env_pop.
ir_stmt('$splice'(Is)) :- !, ir_stmts(Is).
ir_stmt(declaration(_, Sto, _, Vs)) :- !, ( Sto == static -> ir_static_locals(Vs) ; ir_locals(Vs, Sto), ir_array_defers(Vs, Sto) ).
ir_stmt(typedef(_, _)) :- !.
ir_stmt(declare(_, _)) :- !.
ir_stmt(directive(_, _)) :- !.
ir_stmt(include(_, _, _)) :- !.
ir_stmt(static_assert(_, _, _)) :- !.
ir_stmt(empty) :- !.
ir_stmt(expr(L, E)) :- !, ir_line(L), ir_expr(E, _, _).
ir_stmt(defer(L, _, Body)) :- !, ir_line(L), ir_defer_push(Body).
ir_stmt(if(L, C, T, E)) :- !, ir_line(L),
    ir_label(LT), ir_label(LE), ir_label(LM), ir_cond(C, CC),
    ( E == none -> ir_end(['br i1 ', CC, ', label %', LT, ', label %', LM]) ; ir_end(['br i1 ', CC, ', label %', LT, ', label %', LE]) ),
    ir_block(LT), ir_stmt(T), ir_end(['br label %', LM]),
    ( E == none -> true ; ir_block(LE), ir_stmt(E), ir_end(['br label %', LM]) ),
    ir_block(LM).
ir_stmt(while(L, C, S)) :- !, ir_line(L),
    ir_label(LC), ir_label(LB), ir_label(LE), ir_block(LC), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]),
    ir_block(LB), ir_loop_push(LE, LC), ir_stmt(S), ir_loop_pop, ir_end(['br label %', LC]), ir_block(LE).
ir_stmt(do(L, S, C)) :- !, ir_line(L),
    ir_label(LB), ir_label(LC), ir_label(LE), ir_block(LB), ir_loop_push(LE, LC), ir_stmt(S), ir_loop_pop,
    ir_block(LC), ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]), ir_block(LE).
ir_stmt(for_each(L, D, R, S)) :- !, ( ccl_for_each_as_for(for_each(L, D, R, S), For) -> ir_stmt(For) ; ir_fail(range_for_over_non_array) ).   % C++ (M6)
ir_stmt(using(_, _)) :- !.
ir_stmt(try(_, _, _)) :- !, ir_fail(try).
ir_stmt(for(L, Init, C, Step, S)) :- !, ir_line(L),
    ir_env_push,
    ( Init = decl(_, Vs) -> ir_locals(Vs, none) ; Init == none -> true ; ir_expr(Init, _, _) ),
    ir_label(LC), ir_label(LB), ir_label(LS), ir_label(LE), ir_block(LC),
    ( C == none -> ir_end(['br label %', LB]) ; ir_cond(C, CC), ir_end(['br i1 ', CC, ', label %', LB, ', label %', LE]) ),
    ir_block(LB), ir_loop_push(LE, LS), ir_stmt(S), ir_loop_pop,
    ir_block(LS), ( Step == none -> true ; ir_expr(Step, _, _) ), ir_end(['br label %', LC]),
    ir_block(LE), ir_run_defers(1), ir_env_pop.
ir_stmt(return(L)) :- !, ir_line(L), ir_run_defers(all), ir_end(['ret void']).
ir_stmt(return(L, E)) :- nb_getval('$ir_ret', RT), ( RT = ref(_, _) ; RT = rref(_, _) ), !, ir_line(L),   % C++: a reference result is the address
    ir_ref_of(E, P), ir_run_defers(all), ir_end(['ret ptr ', P]).
ir_stmt(return(L, E)) :- !, ir_line(L),
    nb_getval('$ir_ret', RT), nb_getval('$ir_ret_abi', Abi), ir_expr(E, V0, T0, L0),
    (   ccl_resolve_type(RT, base(_, [void])) -> ir_run_defers(all), ir_end(['ret void'])
    ;   Abi = direct(Pcs) -> ir_type(RT, LL), ir_pieces_type(Pcs, CL), ir_tmp(LL, Tmp), ir_ins(['store ', LL, ' ', V0, ', ptr ', Tmp]),
            ir_fresh(C), ir_ins([C, ' = load ', CL, ', ptr ', Tmp]), ir_run_defers(all), ir_end(['ret ', CL, ' ', C])
    ;   ( Abi = memory(_, _) ; Abi = indirect(_, _) ) -> ir_type(RT, LL), ir_ins(['store ', LL, ' ', V0, ', ptr %agg.result']), ir_run_defers(all), ir_end(['ret void'])
    ;   ir_type(RT, LL), ir_convert(V0, T0, L0, RT, LL, V), ir_run_defers(all), ir_end(['ret ', LL, ' ', V]) ).
ir_stmt(break(L)) :- !, ir_line(L), ir_loop_top(LE, _, Depth), ir_depth(D), K is D - Depth, ir_run_defers(K), ir_end(['br label %', LE]).
ir_stmt(continue(L)) :- !, ir_line(L), ir_continue_target(LC, Depth), ir_depth(D), K is D - Depth, ir_run_defers(K), ir_end(['br label %', LC]).
ir_stmt(goto(Ln, L)) :- !, ir_line(Ln), atom_concat('L.', L, LL), ir_end(['br label %', LL]).
ir_stmt(label(_, L, S)) :- !, atom_concat('L.', L, LL), ir_block(LL), ir_stmt(S).
ir_stmt(switch(L, E, block(Is))) :- !, ir_line(L),
    ir_expr(E, V0, T0, L0), ir_int(IT), ir_convert(V0, T0, L0, IT, i32, V),
    ir_label(LE), ir_switch_cases(Is, Cases, Default),
    ( Default = none -> DL = LE ; Default = DL ),
    ir_case_lines(Cases, Lines), ir_join(Lines, ' ', CL),
    ir_end(['switch i32 ', V, ', label %', DL, ' [ ', CL, ' ]']),
    ir_env_push, ir_loop_push(LE, none), ir_switch_body(Is, Cases, Default), ir_loop_pop, ir_run_defers(1), ir_env_pop,
    ir_block(LE).
ir_stmt(switch(L, E, S)) :- !, ir_stmt(switch(L, E, block([S]))).
ir_line(L) :- nb_setval('$ir_line', L).
ir_stmt(case(_, _, S)) :- !, ir_stmt(S).
ir_stmt(default(_, S)) :- !, ir_stmt(S).
ir_stmt(S) :- ir_fail(stmt(S)).

ir_locals([], _).
ir_locals([var(N, T, Init)|Vs], Sto) :-
    ccl_resolve_type(T, T1),
    (   ( T1 = ref(_, _) ; T1 = rref(_, _) )                             % C++: a reference, bound once to an address
    ->  nb_getval('$ir_reg', K), K1 is K + 1, nb_setval('$ir_reg', K1), atomic_list_concat(['%', N, '.', K1], Addr),
        ir_alloca_typed(Addr, T1), ir_local(N, T1, Addr),
        ( Init == none -> ir_fail(reference_unbound(N)) ; ir_ref_of(Init, P), ir_ins(['store ptr ', P, ', ptr ', Addr]) )
    ;   T1 = fn(_, _, _) -> ir_note_extern(N, T)                         % a local prototype
    ;   Sto == extern -> ir_note_extern(N, T)
    ;   ir_sized_type(T, T1, Init, ST),                                     % int xs[] = {...}: sized by its initializer
        nb_getval('$ir_reg', K), K1 is K + 1, nb_setval('$ir_reg', K1), atomic_list_concat(['%', N, '.', K1], Addr),
        ir_alloca_typed(Addr, ST), ir_local(N, ST, Addr), ir_init(Addr, ST, Init) ),
    ir_locals(Vs, Sto).
%% a static local is a private global of the function's, initialized once, constant
ir_static_locals([]).
ir_static_locals([var(N, T, Init)|Vs]) :-
    ccl_resolve_type(T, T1), ir_sized_type(T, T1, Init, GT), ir_gconst_typed(Init, GT, LL, C), ir_galign(GT, Al),
    nb_getval('$ir_fn', F), nb_getval('$ir_statics', K), K1 is K + 1, nb_setval('$ir_statics', K1),
    atomic_list_concat(['@', F, '.', N, '.', K1], Addr),
    atomic_list_concat([Addr, ' = internal global ', LL, ' ', C, Al], Def),
    nb_getval('$ir_gdefs', Gs), nb_setval('$ir_gdefs', [Def|Gs]),
    ir_local(N, GT, Addr), ir_static_locals(Vs).

%% the loop stack: break target, continue target (none in a switch), and the defer depth at entry
ir_loop_push(LE, LC) :- ir_depth(D), nb_getval('$ir_loops', L), nb_setval('$ir_loops', [loop(LE, LC, D)|L]).
ir_loop_pop :- nb_getval('$ir_loops', [_|L]), nb_setval('$ir_loops', L).
ir_loop_top(LE, LC, D) :- nb_getval('$ir_loops', [loop(LE, LC, D)|_]), !.
ir_loop_top(_, _, _) :- ir_fail(break_outside_loop).
ir_continue_target(LC, D) :- nb_getval('$ir_loops', L), ( member(loop(_, LC, D), L), LC \== none -> true ; ir_fail(continue_outside_loop) ).

%% a switch body's cases, at the top level of its block
ir_switch_cases([], [], none).
ir_switch_cases([case(_, E, S)|Is], [case(E, L)|Cs], D) :- !, ir_label(L), ir_switch_cases([S|Is], Cs, D).
ir_switch_cases([default(_, S)|Is], Cs, L) :- !, ir_label(L), ir_switch_cases([S|Is], Cs, _).
ir_switch_cases([_|Is], Cs, D) :- ir_switch_cases(Is, Cs, D).
ir_case_lines([], []).
ir_case_lines([case(E, L)|Cs], [Line|Ls]) :- ir_const_int(E, N), atomic_list_concat(['i32 ', N, ', label %', L], Line), ir_case_lines(Cs, Ls).
ir_const_int(int(N), N) :- !.
ir_const_int(chr(C), C) :- !.
ir_const_int(neg(int(N)), M) :- !, M is -N.
ir_const_int(E, V) :- ccl_const_eval(E, V), !.
ir_const_int(E, _) :- ir_fail(case(E)).
ir_switch_body([], _, _).
ir_switch_body([case(_, E, S)|Is], Cases, D) :- !, memberchk(case(E, L), Cases), ir_block(L), ir_switch_body([S|Is], Cases, D).
ir_switch_body([default(_, S)|Is], Cases, D) :- !, ir_block(D), ir_switch_body([S|Is], Cases, D).
ir_switch_body([S|Is], Cases, D) :- ir_stmt(S), ir_switch_body(Is, Cases, D).

%% ---- functions and globals -------------------------------------------------------------------
ir_item(function(_, _, _, operator(Op), _, _, _)) :- !, ir_fail(operator(Op)).                     % C++: the class step's
ir_item(function(_, _, _, Name, _, _, _)) :- \+ atom(Name), !, ir_fail(member_of_class(Name)).
ir_item(dtor_def(_, _, _, _)) :- !, ir_fail(destructor).
ir_item(declaration(_, _, _, Vs)) :- member(var(N, _, _), Vs), \+ atom(N), !, ir_fail(member_of_class(N)).
ir_item(declare(_, base(_, [class(_, N, _, _)]))) :- !, ir_fail(class(N)).
ir_item(ctor(_, _, _, _, _)) :- !, ir_fail(constructor).
ir_item(dtor(_, _, _)) :- !, ir_fail(destructor).
ir_item(method(_, _, _, N, _, _, _)) :- !, ir_fail(method(N)).
ir_item(function(_, Sto, Ret, Name, Params, Var, Body)) :- !,
    ir_function(Sto, Ret, Name, Params, Var, Body, Text),
    nb_getval('$ir_fdefs', Fs), nb_setval('$ir_fdefs', [Text|Fs]),
    nb_getval('$ir_defined', Ds), nb_setval('$ir_defined', [Name|Ds]).
ir_item(declaration(_, Sto, _, Vs)) :- !, ir_globals(Vs, Sto).
ir_item(extern_c(_, Is)) :- !, ir_items(Is).                              % C++ (M6): C linkage is what every name has
ir_item(namespace(_, _, Is)) :- !, ir_items(Is).                          % a namespace flattens to bare names (the symbol table's view too)
ir_item(using(_, _)) :- !.
ir_item(template(_, _, _)) :- !, ir_fail(template).
ir_item(_).

ir_function(Sto, Ret, Name, Params, Var, Body, Text) :-
    nb_setval('$ir_fn', Name), nb_setval('$ir_line', 0), nb_setval('$ir_body', []), nb_setval('$ir_allocas', []), nb_setval('$ir_term', no),
    nb_setval('$ir_env', [[]]), nb_setval('$ir_defers', [[]]), nb_setval('$ir_loops', []), nb_setval('$ir_ret', Ret), nb_setval('$ir_reg', 0),
    ir_abi(Ret, RetAbi), nb_setval('$ir_ret_abi', RetAbi),
    ccl_scope_push,
    ir_params(Params, 0, Sigs0, Stores),
    (   RetAbi = scalar -> ir_type(Ret, RL), Sigs = Sigs0
    ;   RetAbi = direct(Pcs) -> ir_pieces_type(Pcs, RL), Sigs = Sigs0
    ;   ir_sret_attr(RetAbi, SA), atom_concat(SA, ' %agg.result', S0), RL = void, Sigs = [S0|Sigs0] ),
    ir_join(Sigs, ', ', SigTxt),
    ( Var == true -> ( Sigs == [] -> Sig = '...' ; atom_concat(SigTxt, ', ...', Sig) ) ; Sig = SigTxt ),
    ir_run_lines(Stores),
    ir_stmt(Body),
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
%% the parameters: a scalar is stored to its alloca; a struct in pieces arrives
%% as one register per piece, stored into an alloca of the struct; a struct
%% in memory (byval) or by a pointer to a copy is used where it is
ir_params([], _, [], []).
ir_params([param(T, N)|Ps], I, Sigs, Stores) :-
    ir_param_abi(T, PT, Abi),
    ( N == anon -> atomic_list_concat(['%p', I], R) ; atomic_list_concat(['%', N], R) ),
    ir_param_sig(Abi, PT, N, R, Sigs0, Stores0),
    I1 is I + 1, ir_params(Ps, I1, Sigs1, Stores1), append(Sigs0, Sigs1, Sigs), append(Stores0, Stores1, Stores).
ir_param_sig(scalar, PT, N, R, [Sig], Stores) :-
    ir_type(PT, LL), atomic_list_concat([LL, ' ', R], Sig),
    ( N == anon -> Stores = [] ; atom_concat(R, '.addr', Addr), Stores = [alloca(Addr, LL), store(LL, R, Addr), local(N, PT, Addr)] ).
ir_param_sig(direct(Pcs), PT, N, R, Sigs, Stores) :-
    ir_type(PT, LL), ir_piece_sigs(Pcs, R, 0, Sigs, Pieces),
    ( N == anon -> Stores = [] ; atom_concat(R, '.addr', Addr), ir_piece_stores(Pieces, Addr, St1), append(St1, [local(N, PT, Addr)], St2), Stores = [alloca_al(Addr, LL, 16)|St2] ).
ir_param_sig(memory(LL, A), PT, N, R, [Sig], Stores) :- atomic_list_concat(['ptr byval(', LL, ') align ', A, ' ', R], Sig), ( N == anon -> Stores = [] ; Stores = [local(N, PT, R)] ).
ir_param_sig(indirect(_, _), PT, N, R, [Sig], Stores) :- atomic_list_concat(['ptr ', R], Sig), ( N == anon -> Stores = [] ; Stores = [local(N, PT, R)] ).
ir_piece_sigs([], _, _, [], []).
ir_piece_sigs([piece(P, Off)|Ps], R, J, [Sig|Sigs], [pc(P, Reg, Off)|Pcs]) :-
    atomic_list_concat([R, '.', J], Reg), atomic_list_concat([P, ' ', Reg], Sig), J1 is J + 1, ir_piece_sigs(Ps, R, J1, Sigs, Pcs).
ir_piece_stores([], _, []).
ir_piece_stores([pc(P, Reg, Off)|Pcs], Addr, [store_at(P, Reg, Addr, Off)|Ss]) :- ir_piece_stores(Pcs, Addr, Ss).
ir_run_lines([]).
ir_run_lines([alloca(A, LL)|T]) :- ir_alloca(A, LL), ir_run_lines(T).
ir_run_lines([alloca_al(A, LL, Al)|T]) :- ir_alloca_aligned(A, LL, Al), ir_run_lines(T).
ir_run_lines([store(LL, R, A)|T]) :- ir_ins(['store ', LL, ' ', R, ', ptr ', A]), ir_run_lines(T).
ir_run_lines([store_at(PL, R, A, Off)|T]) :- ir_store_at(PL, R, A, Off), ir_run_lines(T).
ir_run_lines([local(N, T0, A)|T]) :- ir_local(N, T0, A), ir_run_lines(T).

ir_globals([], _).
ir_globals([var(N, T, Init)|Vs], Sto) :-
    ccl_resolve_type(T, T1),
    (   ( T1 = fn(_, _, _) ; Sto == extern ; Sto == typedef ) -> true
    ;   ir_sized_type(T, T1, Init, GT), ir_gconst_typed(Init, GT, LL, C), ir_galign(GT, Al),
        ( Sto == static -> Link = 'internal global' ; Link = 'global' ),
        atomic_list_concat(['@', N, ' = ', Link, ' ', LL, ' ', C, Al], Def),
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
ir_gconst(bool(true), _, 1) :- !.                                         % C++
ir_gconst(bool(false), _, 0) :- !.
ir_gconst(nullptr, _, null) :- !.
ir_gconst(neg(int(N)), _, M) :- !, M is -N.
ir_gconst(id(N), _, Ref) :- ccl_declared(N, T), ccl_resolve_type(T, fn(_, _, _)), !, atom_concat('@', N, Ref), ir_note_extern(N, T).   % a function's address (a C++ table)
ir_gconst(addr(id(N)), _, Ref) :- ccl_declared(N, _), !, atom_concat('@', N, Ref).
ir_gconst(chr(C), _, C) :- !.
ir_gconst(float(F), T, A) :- !, ( ccl_resolve_type(T, base(_, S)), memberchk(float, S) -> ir_fail(float_global) ; ir_double(F, A) ).
ir_gconst(str(S), T, C) :- !,
    ccl_resolve_type(T, T1),
    ( T1 = arr(_, _) -> ir_escape(S, Esc), atomic_list_concat(['c"', Esc, '\\00"'], C) ; ir_string(S, C) ).
ir_gconst(init(Items), T, C) :- !,
    ccl_resolve_type(T, T1),
    (   T1 = arr(int(K), E) -> ir_type(E, EL), ir_gitems(Items, K, E, EL, Parts), ir_join(Parts, ', ', Body), atomic_list_concat(['[', Body, ']'], C)
    ;   T1 = base(_, [struct(_, _)]) -> ir_gstruct(Items, T1, C)                 % the type is written by whoever holds the constant
    ;   T1 = base(_, [union(_, _)]) -> ir_gunion(Items, T1, _, C)
    ;   ir_fail(global_init(T)) ).
ir_gconst(E, _, _) :- ir_fail(global_init(E)).
%% a global's constant with its type: a union initialized takes the literal
%% type of the member given, padded to the union's size
ir_gconst_typed(init(Items), T, LL, C) :- ccl_resolve_type(T, T1), T1 = base(_, [union(_, _)]), !, ir_gunion(Items, T1, LL, C).
ir_gconst_typed(Init, T, LL, C) :- ir_type(T, LL), ir_gconst(Init, T, C).
ir_galign(T, Al) :- ccl_resolve_type(T, T1), ( ( T1 = base(_, [struct(_, _)]) ; T1 = base(_, [union(_, _)]) ), ccl_size_align(T1, _, A) -> atomic_list_concat([', align ', A], Al) ; Al = '' ).
ir_gitems([], 0, _, _, []) :- !.
ir_gitems([], K, E, EL, [Z|Zs]) :- ir_type(E, _), ir_zero(EL, Z0), atomic_list_concat([EL, ' ', Z0], Z), K1 is K - 1, ir_gitems([], K1, E, EL, Zs).
ir_gitems([item(_, V)|Is], K, E, EL, [P|Ps]) :- ir_gconst(V, E, C), atomic_list_concat([EL, ' ', C], P), K1 is K - 1, ir_gitems(Is, K1, E, EL, Ps).
%% a struct constant over its shape: a plain member's constant, a run of
%% bitfields packed into its bytes, padding zero
ir_gstruct(Items, ST, C) :-
    ccl_members_of(ST, Ms), ir_gvalues(Items, Ms, 0, Vals),
    ir_type(ST, SLL), nb_getval('$ir_maps', Maps), memberchk(SLL-shape(Elems, Map), Maps),
    ir_gelems(Elems, 0, Map, Vals, Parts), ir_join(Parts, ', ', Body), atomic_list_concat(['{ ', Body, ' }'], C).
ir_gvalues([], _, _, []).
ir_gvalues([item(Ds, V)|Is], Ms, I, [N-V|Vs]) :-
    (   Ds = [field(F)|_] -> N = F, ir_member_index_(Ms, F, 0, I0, _), I1 is I0 + 1
    ;   I1 is I + 1, ccl_nth(I1, Ms, member(_, N, _)) ),
    ir_gvalues(Is, Ms, I1, Vs).
ir_gelems([], _, _, _, []).
ir_gelems([LL|Ls], Idx, Map, Vals, [P|Ps]) :-
    findall(M, ( member(M, Map), M = m(_, Idx, _, _) ), Here),
    (   Here == [] -> ir_zero(LL, Z), atomic_list_concat([LL, ' ', Z], P)
    ;   Here = [m(N, _, MT, none)] -> ( memberchk(N-V, Vals) -> ir_gconst(V, MT, C) ; ir_zero(LL, C) ), atomic_list_concat([LL, ' ', C], P)
    ;   ir_gpack(Here, Vals, 0, Packed), ir_array_count(LL, K),
        ir_le_bytes(Packed, K, Bytes), ir_escape(Bytes, Esc), atomic_list_concat([LL, ' c"', Esc, '"'], P) ),
    Idx1 is Idx + 1, ir_gelems(Ls, Idx1, Map, Vals, Ps).
%% the K of a `[K x i8]'
ir_array_count(LL, K) :- atom_codes(LL, [0'[|Cs]), ir_digits(Cs, Ds), number_codes(K, Ds).
ir_digits([C|Cs], [C|Ds]) :- C >= 0'0, C =< 0'9, !, ir_digits(Cs, Ds).
ir_digits(_, []).
ir_gpack([], _, Acc, Acc).
ir_gpack([m(N, _, _, bf(_, Off, W, _))|Ms], Vals, Acc, Packed) :-
    ( memberchk(N-V, Vals) -> ir_const_int(V, I) ; I = 0 ), Mask is (1 << W) - 1, Bits is (I mod (1 << W)) /\ Mask,
    Acc1 is Acc \/ (Bits << Off), ir_gpack(Ms, Vals, Acc1, Packed).
ir_le_bytes(_, 0, []) :- !.
ir_le_bytes(V, K, [B|Bs]) :- B is V /\ 255, V1 is V >> 8, K1 is K - 1, ir_le_bytes(V1, K1, Bs).
%% a union constant: the member given (the first, or the designated one) in its own type, padded
ir_gunion(Items, UT, LL, C) :-
    ccl_members_of(UT, Ms), ccl_union_layout(Ms, 0, 1, N, _),
    (   Items = [item(Ds, V)|_] -> ( Ds = [field(F)|_] -> memberchk(member(MT, F, _), Ms) ; Ms = [member(MT, _, _)|_] ),
        ir_type(MT, MLL), ir_gconst(V, MT, MC), ccl_resolve_type(MT, MT1), ccl_size_align(MT1, S, _), Pad is N - S,
        ( Pad =:= 0 -> atomic_list_concat(['{ ', MLL, ' }'], LL), atomic_list_concat(['{ ', MLL, ' ', MC, ' }'], C)
        ; atomic_list_concat(['{ ', MLL, ', [', Pad, ' x i8] }'], LL), atomic_list_concat(['{ ', MLL, ' ', MC, ', [', Pad, ' x i8] zeroinitializer }'], C) )
    ;   ir_type(UT, LL), C = zeroinitializer ).

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
    (   T1 = fn(RT, Ps, Var) -> ir_fn_sig(RT, Ps, Var, RL, _, PLs), ir_join(PLs, ', ', PL),
            atomic_list_concat(['declare ', RL, ' @', N, '(', PL, ')'], D)
    ;   ir_type(T, LL), atomic_list_concat(['@', N, ' = external global ', LL], D) ),
    ir_declares(Es, Ds, Decls).
%% joins go through codes: atomic_list_concat/2 dies silently past ~8 KB
%% (a cocolog finding), atom_codes/2 takes hundreds of KB
%% the builtin joins 5000 lines in no time where a walk over their codes took
%% 0.3 s (the walk was for cocolog before 1.1.0, whose atomic_list_concat died
%% past 8 KB; it takes 16 MB since)
ir_join(Xs, Sep, A) :- atomic_list_concat(Xs, Sep, A).
