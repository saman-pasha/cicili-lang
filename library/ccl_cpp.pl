%% ccl_cpp.pl -- M6's C++ forms desugared to the C the check and the lowering
%% have, before either runs (cicili_ir calls ccl_cpp_units/2 in cpp mode).
%%
%% A class is a struct of its data members, its base (one) the first member,
%% '$base'; every method is a function over `this' (C.m.k, k the arity, an
%% operator by its word), a constructor `C.C.k' returning void, run at the
%% declaration of every local of the class (a '$splice' of the declaration,
%% the call, and -- when the class has a destructor -- a defer of `C.dtor.0'
%% over its address: the scope's exits run it, last declared first, as C++
%% has it); a static member is the global `C.N'; `new C(args)' constructs
%% into malloc's block and `delete p' destroys before free; a call `o.m(a)'
%% is `C.m.k(&o, a)' with the default arguments filled, `p->m(a)' passes p,
%% an unqualified `m(a)' inside a method passes this, `Counter(v)' builds a
%% temporary; `o += v', `o[i]', `a + b' go to the class's or a free operator.
%% Inside a method an unqualified data member is `this->n', an inherited one
%% through '$base'. The walk keeps the symbol table's scopes as the check
%% does, so ccl_type_of/2 tells a class-typed operand; the functions it makes
%% are declared as it goes, so their calls have types too.
%%
%% Not this step (refused by name): virtual, more than one base, a member of
%% class type with a constructor, an array of a class, a global of a class
%% with a constructor, a temporary's destructor, operator= and copy
%% constructors (a struct copies).

ccl_cpp_units(Units0, Units) :- cpp_register_units(Units0), cpp_units(Units0, Units).
cpp_units([], []).
cpp_units([unit(Is0)|Us0], [unit(Is)|Us]) :- cpp_items(Is0, Is), cpp_units(Us0, Us).

%% ---- the classes of the units: '$cpp_classes' = [C-cls(Base, Data, Members, Statics, Defaults) ...] --------
cpp_register_units(Units) :-
    nb_setval('$cpp_classes', []), nb_setval('$cpp_defaults', []), nb_setval('$cpp_free_ops', []), nb_setval('$cpp_dtor_defs', []),
    forall(member(unit(Is), Units), cpp_register_(Is)).
cpp_register_([]).
cpp_register_([declare(L, base(_, [class(_, C, Bases, Ms)]))|Is]) :- !, cpp_register_class(L, C, Bases, Ms), cpp_register_(Is).
cpp_register_([function(_, _, Ret, operator(Op), Ps, V, _)|Is]) :- !,
    cpp_free_operator(Op, Ps, Name), cpp_plain_params(Ps, Ps1), ccl_declare(Name, fn(Ret, Ps1, V)), cpp_note_defaults(Name, Ps),
    nb_getval('$cpp_free_ops', Os), nb_setval('$cpp_free_ops', [Name|Os]), cpp_register_(Is).
cpp_register_([function(_, _, _, N, Ps, _, _)|Is]) :- atom(N), !, cpp_note_defaults(N, Ps), cpp_register_(Is).
cpp_register_([dtor_def(_, C, _, _)|Is]) :- !, nb_getval('$cpp_dtor_defs', Ds), nb_setval('$cpp_dtor_defs', [C|Ds]), cpp_register_(Is).
cpp_register_([namespace(_, _, Js)|Is]) :- !, cpp_register_(Js), cpp_register_(Is).
cpp_register_([extern_c(_, Js)|Is]) :- !, cpp_register_(Js), cpp_register_(Is).
cpp_register_([_|Is]) :- cpp_register_(Is).
cpp_register_class(L, C, Bases, Ms) :-
    (   Bases = [] -> Base = none
    ;   Bases = [base(_, B)] -> Base = B
    ;   cpp_refuse(L, multiple_inheritance(C)) ),
    ( member(method(ML, Qs, _, _, _, _, _), Ms), memberchk(virtual, Qs) -> cpp_refuse(ML, virtual(C)) ; true ),
    ( member(dtor(DL, Qs2, _), Ms), memberchk(virtual, Qs2) -> cpp_refuse(DL, virtual(C)) ; true ),
    cpp_split_members(Ms, Data, Statics, Defaults),
    nb_getval('$cpp_classes', Cs), nb_setval('$cpp_classes', [C-cls(Base, Data, Ms, Statics, Defaults)|Cs]),
    cpp_declare_members(Ms, C), cpp_declare_statics(Statics, C).
cpp_split_members([], [], [], []).
cpp_split_members([member(base(Q, S), N, _)|Ms], Data, [N-base(Q1, S)|Ss], Ds) :- memberchk(static, Q), !, ccl_delete_one(Q, static, Q1), cpp_split_members(Ms, Data, Ss, Ds).
cpp_split_members([member(T, N, _)|Ms], [member(T, N, none)|Data], Ss, Ds) :- !, cpp_split_members(Ms, Data, Ss, Ds).
cpp_split_members([default_init(N, E)|Ms], Data, Ss, [N-E|Ds]) :- !, cpp_split_members(Ms, Data, Ss, Ds).
cpp_split_members([_|Ms], Data, Ss, Ds) :- cpp_split_members(Ms, Data, Ss, Ds).
%% the functions a class makes are declared in the symbol table at once, so
%% a rewritten call has a type while the walk goes on
cpp_declare_members([], _).
cpp_declare_members([method(_, Qs, Ret, M, Ps, V, _)|Ms], C) :- !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, Qs, ThisT),
    ccl_declare(Name, fn(Ret, [param(ThisT, this)|Ps1], V)), cpp_note_defaults(Name, Ps), cpp_declare_members(Ms, C).
cpp_declare_members([ctor(_, _, Ps, _, _)|Ms], C) :- !,
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], ThisT),
    ccl_declare(Name, fn(base([], [void]), [param(ThisT, this)|Ps1], false)), cpp_note_defaults(Name, Ps), cpp_declare_members(Ms, C).
cpp_declare_members([dtor(_, _, _)|Ms], C) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], ThisT),
    ccl_declare(Name, fn(base([], [void]), [param(ThisT, this)], false)), cpp_declare_members(Ms, C).
cpp_declare_members([_|Ms], C) :- cpp_declare_members(Ms, C).
cpp_declare_statics([], _).
cpp_declare_statics([N-T|Ss], C) :- atomic_list_concat([C, '.', N], Name), ccl_declare(Name, T), cpp_declare_statics(Ss, C).
cpp_class(C, Cls) :- nb_getval('$cpp_classes', Cs), memberchk(C-Cls, Cs).
%% the class a type names, and the one a pointer's or an array's element names
cpp_class_of_type(T, C) :- ccl_resolve_type(T, T1), cpp_class_of_type_(T1, C).
cpp_class_of_type_(base(_, [class(_, C, _, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [struct(C, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [typedef(C)]), C) :- cpp_class(C, _), !.
cpp_pointee_class(T, C) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ), cpp_class_of_type(E, C).
cpp_class_of_type_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_class_of_type(T, C).
cpp_pointee_class_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_pointee_class(T, C).
%% the members: data (own and inherited, with the hops through '$base'), the statics, methods, constructors, the destructor
cpp_data_member(C, N, []) :- cpp_class(C, cls(_, Data, _, _, _)), memberchk(member(_, N, _), Data), !.
cpp_data_member(C, N, ['$base'|Hops]) :- cpp_class(C, cls(B, _, _, _, _)), B \== none, cpp_data_member(B, N, Hops).
cpp_static_member(C, N, Name) :- cpp_class(C, cls(B, _, _, Ss, _)), ( memberchk(N-_, Ss) -> atomic_list_concat([C, '.', N], Name) ; B \== none, cpp_static_member(B, N, Name) ).
cpp_method(C, M, NArgs, Name, Hops) :-
    cpp_class(C, cls(B, _, Ms, _, _)),
    (   member(method(_, _, _, M, Ps, _, _), Ms), cpp_arity_fits(Ps, NArgs) -> cpp_mangle(C, M, Ps, Name), Hops = []
    ;   B \== none, cpp_method(B, M, NArgs, Name, Hops1), Hops = ['$base'|Hops1] ).
cpp_ctor(C, NArgs, Name) :- cpp_class(C, cls(_, _, Ms, _, _)), member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, NArgs), !, cpp_mangle(C, C, Ps, Name).
cpp_ctor(C, 0, Name) :- cpp_implicit_ctor_needed(C), cpp_mangle(C, C, [], Name).
cpp_has_ctors(C) :- cpp_class(C, cls(_, _, Ms, _, _)), memberchk(ctor(_, _, _, _, _), Ms), !.
cpp_has_ctors(C) :- cpp_implicit_ctor_needed(C).
cpp_implicit_ctor_needed(C) :- cpp_class(C, cls(B, _, Ms, _, Defaults)), \+ memberchk(ctor(_, _, _, _, _), Ms), ( Defaults \== [] ; B \== none, cpp_has_ctors(B) ), !.
cpp_dtor(C, Name) :- cpp_class(C, cls(_, _, Ms, _, _)), ( memberchk(dtor(_, _, _), Ms) ; nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ), !, atomic_list_concat([C, '.dtor.0'], Name).
cpp_arity_fits(Ps, N) :- length(Ps, Max), Max >= N, cpp_required(Ps, Min), Min =< N.
cpp_required([], 0).
cpp_required([param(_, _, _)|_], 0) :- !.
cpp_required([_|Ps], N) :- cpp_required(Ps, N0), N is N0 + 1.

%% ---- names ----------------------------------------------------------------------
cpp_mangle(C, operator(Op), Ps, Name) :- !, length(Ps, K), cpp_op_word(Op, W), atomic_list_concat([C, '.op.', W, '.', K], Name).
cpp_mangle(C, M, Ps, Name) :- length(Ps, K), atomic_list_concat([C, '.', M, '.', K], Name).
cpp_free_operator(Op, Ps, Name) :- length(Ps, K), cpp_op_word(Op, W), atomic_list_concat(['op.', W, '.', K], Name).
cpp_op_word('+', plus) :- !.        cpp_op_word('-', minus) :- !.       cpp_op_word('*', times) :- !.       cpp_op_word('/', divide) :- !.     cpp_op_word('%', modulo) :- !.
cpp_op_word('==', eq) :- !.         cpp_op_word('!=', ne) :- !.         cpp_op_word('<', lt) :- !.          cpp_op_word('>', gt) :- !.         cpp_op_word('<=', le) :- !.        cpp_op_word('>=', ge) :- !.
cpp_op_word('+=', plus_assign) :- !. cpp_op_word('-=', minus_assign) :- !. cpp_op_word('*=', times_assign) :- !. cpp_op_word('/=', divide_assign) :- !. cpp_op_word('%=', modulo_assign) :- !.
cpp_op_word('[]', index) :- !.      cpp_op_word('()', call) :- !.       cpp_op_word('<<', shl) :- !.        cpp_op_word('>>', shr) :- !.       cpp_op_word('!', not) :- !.
cpp_op_word('&&', and) :- !.        cpp_op_word('||', or) :- !.         cpp_op_word('&', bitand) :- !.      cpp_op_word('|', bitor) :- !.      cpp_op_word('^', bitxor) :- !.     cpp_op_word('~', bitnot) :- !.
cpp_op_word('++', inc) :- !.        cpp_op_word('--', dec) :- !.        cpp_op_word('=', assign) :- !.      cpp_op_word('->', arrow) :- !.
cpp_op_word('<<=', shl_assign) :- !. cpp_op_word('>>=', shr_assign) :- !. cpp_op_word('&=', bitand_assign) :- !. cpp_op_word('|=', bitor_assign) :- !. cpp_op_word('^=', bitxor_assign) :- !.
cpp_op_word(Op, W) :- atom_codes(Op, Cs), atomic_list_concat([op|Cs], '_', W).
%% the default arguments of a function, by its (mangled) name: '$cpp_defaults' = [Name-[none | E ...] ...]
cpp_note_defaults(Name, Ps) :- ( member(param(_, _, _), Ps) -> cpp_defaults_of(Ps, Ds), nb_getval('$cpp_defaults', L), nb_setval('$cpp_defaults', [Name-Ds|L]) ; true ).
cpp_defaults_of([], []).
cpp_defaults_of([param(_, _, D)|Ps], [D|Ds]) :- !, cpp_defaults_of(Ps, Ds).
cpp_defaults_of([_|Ps], [none|Ds]) :- cpp_defaults_of(Ps, Ds).
cpp_fill_defaults(Name, As, As1) :- nb_getval('$cpp_defaults', L), memberchk(Name-Ds, L), !, length(As, N), cpp_drop(N, Ds, Rest), cpp_take_defaults(Rest, Tail), append(As, Tail, As1).
cpp_fill_defaults(_, As, As).
cpp_drop(0, L, L) :- !.
cpp_drop(N, [_|L], R) :- N1 is N - 1, cpp_drop(N1, L, R).
cpp_take_defaults([], []).
cpp_take_defaults([none|_], []) :- !.
cpp_take_defaults([D|Ds], [D|Es]) :- cpp_take_defaults(Ds, Es).
cpp_plain_params([], []).
cpp_plain_params([param(T, N, _)|Ps], [param(T, N)|Qs]) :- !, cpp_plain_params(Ps, Qs).
cpp_plain_params([P|Ps], [P|Qs]) :- cpp_plain_params(Ps, Qs).
cpp_this_type(C, Quals, ptr([], base(Q, [typedef(C)]))) :- ( memberchk(const, Quals) -> Q = [const] ; Q = [] ).
cpp_refuse(L, What) :- throw(error(not_lowered(What), where(file, line(L)))).

%% ---- items ----------------------------------------------------------------------
cpp_items([], []).
cpp_items([I|Is], Out) :- cpp_item(I, Js), append(Js, Out1, Out), cpp_items(Is, Out1).
%% a class: the struct, the statics, then its members as functions
cpp_item(declare(L, base(Q, [class(_, C, _, _)])), [declare(L, base(Q, [struct(C, Data1)]))|Fns]) :- !,
    cpp_class(C, cls(Base, Data, Ms, Statics, Defaults)),
    ( Base == none -> Data1 = Data ; Data1 = [member(base([], [typedef(Base)]), '$base', none)|Data] ),
    cpp_static_decls(L, C, Statics, Fns0),
    cpp_member_fns(Ms, C, Base, Defaults, Fns1),
    ( cpp_implicit_ctor_needed(C) -> cpp_implicit_ctor(L, C, Base, Defaults, Fns2) ; Fns2 = [] ),
    append(Fns0, Fns1, Fns01), append(Fns01, Fns2, Fns).
cpp_item(declaration(L, Sto, B, [var(scoped([C], N), T, Init)]), [declaration(L, Sto, B, [var(Name, T, Init1)])]) :- cpp_class(C, _), !,
    atomic_list_concat([C, '.', N], Name), cpp_expr(none, Init, Init1).
cpp_item(function(L, Sto, Ret, scoped([C], M), Ps, V, Body), [function(L, Sto, Ret, Name, [param(ThisT, this)|Ps1], V, Body1)]) :- cpp_class(C, _), !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], ThisT),
    cpp_method_body(C, [param(ThisT, this)|Ps1], Body, Body1).
cpp_item(dtor_def(L, C, _, Body), [function(L, none, base([], [void]), Name, [param(ThisT, this)], false, Body1)]) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], ThisT), cpp_method_body(C, [param(ThisT, this)], Body, Body1).
cpp_item(function(L, Sto, Ret, operator(Op), Ps, V, Body), [function(L, Sto, Ret, Name, Ps1, V, Body1)]) :- !,
    cpp_free_operator(Op, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_method_body(none, Ps1, Body, Body1).
cpp_item(function(L, Sto, Ret, N, Ps, V, Body), [function(L, Sto, Ret, N, Ps1, V, Body1)]) :- !,
    cpp_plain_params(Ps, Ps1), cpp_method_body(none, Ps1, Body, Body1).
cpp_item(declaration(L, Sto, B, Vs), [declaration(L, Sto, B, Vs1)]) :- !, cpp_vars(none, Vs, Vs1).
cpp_item(namespace(L, N, Is), [namespace(L, N, Js)]) :- !, cpp_items(Is, Js).
cpp_item(extern_c(L, Is), [extern_c(L, Js)]) :- !, cpp_items(Is, Js).
cpp_item(I, [I]).
cpp_vars(_, [], []).
cpp_vars(Ctx, [var(N, fn(R, Ps, V), I)|Vs], [var(N, fn(R, Ps1, V), I)|Ws]) :- !, cpp_plain_params(Ps, Ps1), cpp_vars(Ctx, Vs, Ws).
cpp_vars(Ctx, [var(N, T, I)|Vs], [var(N, T, I1)|Ws]) :- cpp_expr(Ctx, I, I1), cpp_vars(Ctx, Vs, Ws).
%% the static members: declared with the class, defined out of it (Counter::made, above)
cpp_static_decls(_, _, [], []).
cpp_static_decls(L, C, [N-T|Ss], [declaration(L, extern, T, [var(Name, T, none)])|Ds]) :- atomic_list_concat([C, '.', N], Name), cpp_static_decls(L, C, Ss, Ds).
%% the members that are functions
cpp_member_fns([], _, _, _, []).
cpp_member_fns([method(L, Qs, Ret, M, Ps, V, Body)|Ms], C, B, Ds, [F|Fs]) :- !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, Qs, ThisT), Params = [param(ThisT, this)|Ps1],
    (   Body == none -> F = declaration(L, none, Ret, [var(Name, fn(Ret, Params, V), none)])
    ;   cpp_method_body(C, Params, Body, Body1), F = function(L, none, Ret, Name, Params, V, Body1) ),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([ctor(L, _, Ps, Inits, Body)|Ms], C, B, Ds, [F|Fs]) :- !,
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], ThisT), Params = [param(ThisT, this)|Ps1],
    cpp_ctor_body(L, C, B, Ds, Inits, Body, Body0), cpp_method_body(C, Params, Body0, Body1),
    F = function(L, none, base([], [void]), Name, Params, false, Body1),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([dtor(L, _, Body)|Ms], C, B, Ds, Fs) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], ThisT), Params = [param(ThisT, this)],
    (   Body == none -> Fs = [declaration(L, none, base([], [void]), [var(Name, fn(base([], [void]), Params, false), none)])|Fs1]
    ;   cpp_method_body(C, Params, Body, Body1), Fs = [function(L, none, base([], [void]), Name, Params, false, Body1)|Fs1] ),
    cpp_member_fns(Ms, C, B, Ds, Fs1).
cpp_member_fns([_|Ms], C, B, Ds, Fs) :- cpp_member_fns(Ms, C, B, Ds, Fs).
%% a constructor's body: the base's constructor, then every member from its
%% initializer, else its default, in the members' order; then the body
cpp_ctor_body(L, C, B, Defaults, Inits, block(Body), block(Pre)) :-
    (   B \== none
    ->  ( memberchk(init(B, BArgs), Inits) -> true ; BArgs = [] ),
        length(BArgs, NB),
        ( cpp_ctor(B, NB, BName) -> cpp_fill_defaults(BName, BArgs, BArgs1), Pre = [expr(L, call(id(BName), [addr(arrow(this, '$base'))|BArgs1]))|Pre1]
        ; BArgs == [] -> Pre = Pre1
        ; cpp_refuse(L, base_constructor(B)) )
    ;   Pre = Pre1 ),
    cpp_class(C, cls(_, Data, _, _, _)),
    cpp_member_inits(Data, Inits, Defaults, L, Pre1, Body).
cpp_member_inits([], _, _, _, Body, Body).
cpp_member_inits([member(_, N, _)|Ds], Inits, Defaults, L, Pre, Body) :-
    (   memberchk(init(N, [E]), Inits) -> Pre = [expr(L, assign('=', arrow(this, N), E))|Pre1]
    ;   memberchk(N-E, Defaults) -> Pre = [expr(L, assign('=', arrow(this, N), E))|Pre1]
    ;   Pre = Pre1 ),
    cpp_member_inits(Ds, Inits, Defaults, L, Pre1, Body).
%% a class with no constructor of its own but defaults to set, or a base to construct: C.C.0
cpp_implicit_ctor(L, C, B, Defaults, [function(L, none, base([], [void]), Name, Params, false, Body1)]) :-
    cpp_mangle(C, C, [], Name), cpp_this_type(C, [], ThisT), Params = [param(ThisT, this)],
    ccl_declare(Name, fn(base([], [void]), Params, false)),
    cpp_ctor_body(L, C, B, Defaults, [], block([]), Body0), cpp_method_body(C, Params, Body0, Body1).
%% a body under its parameters, the class's members in reach
cpp_method_body(Ctx, Params, Body, Body1) :- ccl_scope_push, ccl_declare_params(Params), cpp_stmt(Ctx, Body, Body1), ccl_scope_pop.

%% ---- statements, the scopes kept -------------------------------------------------
cpp_stmt(Ctx, block(Is), block(Js)) :- !, ccl_scope_push, cpp_stmts(Ctx, Is, Js), ccl_scope_pop.
cpp_stmt(Ctx, '$splice'(Is), '$splice'(Js)) :- !, cpp_stmts(Ctx, Is, Js).
cpp_stmt(Ctx, declaration(L, Sto, B, Vs), S) :- !, cpp_decl_stmt(Ctx, L, Sto, B, Vs, S).
cpp_stmt(Ctx, expr(L, E), expr(L, E1)) :- !, cpp_expr(Ctx, E, E1).
cpp_stmt(Ctx, defer(L, Vs, Body), defer(L, Vs, Body1)) :- !, cpp_stmt(Ctx, Body, Body1).
cpp_stmt(Ctx, if(L, C, T, E), if(L, C1, T1, E1)) :- !, cpp_expr(Ctx, C, C1), cpp_stmt(Ctx, T, T1), ( E == none -> E1 = none ; cpp_stmt(Ctx, E, E1) ).
cpp_stmt(Ctx, while(L, C, S), while(L, C1, S1)) :- !, cpp_expr(Ctx, C, C1), cpp_stmt(Ctx, S, S1).
cpp_stmt(Ctx, do(L, S, C), do(L, S1, C1)) :- !, cpp_stmt(Ctx, S, S1), cpp_expr(Ctx, C, C1).
cpp_stmt(Ctx, for(L, Init, C, Step, S), for(L, Init1, C1, Step1, S1)) :- !,
    ccl_scope_push,
    ( Init = decl(B, Vs) -> cpp_vars(Ctx, Vs, Vs1), ccl_declare_vars(Vs1), Init1 = decl(B, Vs1) ; cpp_opt_expr(Ctx, Init, Init1) ),
    cpp_opt_expr(Ctx, C, C1), cpp_opt_expr(Ctx, Step, Step1), cpp_stmt(Ctx, S, S1), ccl_scope_pop.
cpp_stmt(Ctx, for_each(L, var(N, T, I), R, S), for_each(L, var(N, T, I), R1, S1)) :- !,
    cpp_expr(Ctx, R, R1), ccl_scope_push, ccl_declare(N, T), cpp_stmt(Ctx, S, S1), ccl_scope_pop.
cpp_stmt(Ctx, return(L, E), return(L, E1)) :- !, cpp_expr(Ctx, E, E1).
cpp_stmt(Ctx, label(L, N, S), label(L, N, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt(Ctx, switch(L, E, S), switch(L, E1, S1)) :- !, cpp_expr(Ctx, E, E1), cpp_stmt(Ctx, S, S1).
cpp_stmt(Ctx, case(L, E, S), case(L, E, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt(Ctx, default(L, S), default(L, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt(_, S, S).
cpp_stmts(_, [], []).
cpp_stmts(Ctx, [S|Ss], [S1|Ts]) :- cpp_stmt(Ctx, S, S1), cpp_stmts(Ctx, Ss, Ts).
cpp_opt_expr(_, none, none) :- !.
cpp_opt_expr(Ctx, E, E1) :- cpp_expr(Ctx, E, E1).
%% a declaration: a local of a class type with a constructor is declared, then
%% constructed (from its arguments, or copied from a value of the class),
%% then -- when the class has a destructor -- deferred; several declarators
%% go one by one
cpp_decl_stmt(Ctx, L, Sto, B, Vs, S) :-
    cpp_decl_pieces(Ctx, L, Sto, B, Vs, Pieces),
    ( Pieces = [One] -> S = One ; S = '$splice'(Pieces) ).
cpp_decl_pieces(_, _, _, _, [], []).
cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T, I)|Vs], Pieces) :-
    (   Sto \== static, Sto \== extern, cpp_class_of_type(T, C), cpp_has_ctors(C), cpp_ctor_args(Ctx, I, C, Args)
    ->  length(Args, NA),
        ( cpp_ctor(C, NA, CName) -> true ; cpp_refuse(L, no_constructor(C, NA)) ),
        cpp_fill_defaults(CName, Args, Args1),
        ccl_declare(N, T),
        Pieces = [declaration(L, Sto, B, [var(N, T, none)]), expr(L, call(id(CName), [addr(id(N))|Args1]))|P1]
    ;   cpp_expr(Ctx, I, I1), ccl_declare(N, T),
        Pieces = [declaration(L, Sto, B, [var(N, T, I1)])|P1] ),
    ( Sto \== static, Sto \== extern, cpp_class_of_type(T, C2), cpp_dtor(C2, DName) -> P1 = [defer(L, [], block([expr(L, call(id(DName), [addr(id(N))]))]))|P2] ; P1 = P2 ),
    cpp_decl_pieces(Ctx, L, Sto, B, Vs, P2).
cpp_ctor_args(_, none, _, []) :- !.
cpp_ctor_args(Ctx, ctor(As), _, As1) :- !, cpp_exprs(Ctx, As, As1).
cpp_ctor_args(Ctx, init(Items), _, As1) :- !, findall(E, member(item(_, E), Items), As), cpp_exprs(Ctx, As, As1).
cpp_ctor_args(Ctx, E, C, [E1]) :- cpp_expr(Ctx, E, E1), \+ cpp_class_of_type_of(E1, C).   % a value of the class itself is copied, not constructed from

%% ---- expressions, bottom up ----------------------------------------------------------
cpp_exprs(_, [], []).
cpp_exprs(Ctx, [E|Es], [E1|Fs]) :- cpp_expr(Ctx, E, E1), cpp_exprs(Ctx, Es, Fs).
cpp_expr(_, this, id(this)) :- !.
cpp_expr(_, E, E) :- \+ compound(E), !.
cpp_expr(Ctx, id(N), E) :- !,
    (   cpp_local(N) -> E = id(N)
    ;   Ctx \== none, cpp_data_member(Ctx, N, Hops) -> cpp_access(id(this), N, Hops, E)
    ;   Ctx \== none, cpp_static_member(Ctx, N, Name) -> E = id(Name)
    ;   E = id(N) ).
cpp_expr(_, scoped([C], N), id(Name)) :- cpp_class(C, _), !, ( cpp_static_member(C, N, Name) -> true ; atomic_list_concat([C, '.', N], Name) ).
cpp_expr(Ctx, call(F, As), E) :- !, cpp_exprs(Ctx, As, As1), cpp_call(Ctx, F, As1, E).
cpp_expr(Ctx, member(X, N), E) :- !, cpp_expr(Ctx, X, X1), ( cpp_class_of_type_of(X1, C), cpp_data_member(C, N, Hops), Hops \== [] -> cpp_hops(X1, Hops, B), E = member(B, N) ; E = member(X1, N) ).
cpp_expr(Ctx, arrow(X, N), E) :- !, cpp_expr(Ctx, X, X1), ( cpp_pointee_class_of(X1, C), cpp_data_member(C, N, Hops), Hops \== [] -> cpp_access(X1, N, Hops, E) ; E = arrow(X1, N) ).
cpp_expr(Ctx, bin(Op, A, B), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_operator(Op, A1, [B1], bin(Op, A1, B1), E).
cpp_expr(Ctx, assign(Op, A, B), E) :- Op \== '=', !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_operator(Op, A1, [B1], assign(Op, A1, B1), E).
cpp_expr(Ctx, index(A, I), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, I, I1), cpp_operator('[]', A1, [I1], index(A1, I1), E).
cpp_expr(Ctx, new(T, As), E) :- !, cpp_exprs(Ctx, As, As1), cpp_new(T, As1, E).
cpp_expr(Ctx, delete(X), E) :- !, cpp_expr(Ctx, X, X1), cpp_delete(X1, E).
cpp_expr(Ctx, ccast(functional, base(Q, [typedef(C)]), X), E) :- cpp_class(C, _), !, cpp_expr(Ctx, X, X1), cpp_temporary(base(Q, [typedef(C)]), C, [X1], E).
cpp_expr(Ctx, stmt_expr(block(Is)), stmt_expr(block(Js))) :- !, ccl_scope_push, cpp_stmts(Ctx, Is, Js), ccl_scope_pop.
cpp_expr(_, lambda(A, B, C, D), lambda(A, B, C, D)) :- !.
cpp_expr(_, str(S), str(S)) :- !.
cpp_expr(Ctx, E, E1) :- E =.. [F|As], cpp_exprs(Ctx, As, Bs), E1 =.. [F|Bs].
cpp_local(N) :- ccl_locals(Fs), member(F, Fs), memberchk(N-_, F), !.
%% the way to a member: o.$base...n by value, p->n or p->$base...n through a pointer
cpp_hops(X, [], X).
cpp_hops(X, [H|Hs], B) :- cpp_hops(member(X, H), Hs, B).
cpp_access(P, N, [], arrow(P, N)) :- !.
cpp_access(P, N, Hops, member(B, N)) :- cpp_hops(deref(P), Hops, B).
%% calls: a method through its object, a method of this, a constructor as a temporary, a free function with its defaults
cpp_call(Ctx, member(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_class_of_type_of(X, C), length(As, N), cpp_method(C, M, N, Name, Hops)
    ->  cpp_hops(X, Hops, B), cpp_fill_defaults(Name, As, As1), E = call(id(Name), [addr(B)|As1])
    ;   E = call(member(X, M), As) ).
cpp_call(Ctx, arrow(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_pointee_class_of(X, C), length(As, N), cpp_method(C, M, N, Name, Hops)
    ->  ( Hops == [] -> P = X ; cpp_hops(deref(X), Hops, B), P = addr(B) ), cpp_fill_defaults(Name, As, As1), E = call(id(Name), [P|As1])
    ;   E = call(arrow(X, M), As) ).
cpp_call(Ctx, id(M), As, call(id(Name), [P|As1])) :- Ctx \== none, \+ cpp_local(M), length(As, N), cpp_method(Ctx, M, N, Name, Hops), !,
    ( Hops == [] -> P = id(this) ; cpp_hops(deref(id(this)), Hops, B), P = addr(B) ), cpp_fill_defaults(Name, As, As1).
cpp_call(_, id(C), As, E) :- cpp_class(C, _), !, cpp_temporary(base([], [typedef(C)]), C, As, E).
cpp_call(_, id(F), As, call(id(F), As1)) :- !, cpp_fill_defaults(F, As, As1).
cpp_call(Ctx, F, As, call(F1, As)) :- cpp_expr(Ctx, F, F1).
%% a temporary of the class: constructed in a statement expression, its value the last expression
cpp_temporary(T, C, As, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, none)]), expr(0, call(id(Name), [addr(id(Tmp))|As1])), expr(0, id(Tmp))]))) :-
    length(As, N), ( cpp_ctor(C, N, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As1), ccl_gensym('$tmp', Tmp).
%% an operator on a class-typed left operand: the class's member operator, else a free one declared, else the form as it is
cpp_operator(Op, A, Args, Plain, E) :-
    (   cpp_class_of_type_of(A, C), length(Args, N), cpp_method(C, operator(Op), N, Name, Hops)
    ->  cpp_hops(A, Hops, B), cpp_fill_defaults(Name, Args, Args1), E = call(id(Name), [addr(B)|Args1])
    ;   cpp_class_of_type_of(A, _), length(Args, N0), N1 is N0 + 1, length(Ps, N1), cpp_free_operator(Op, Ps, Name), nb_getval('$cpp_free_ops', Os), memberchk(Name, Os)
    ->  E = call(id(Name), [A|Args])
    ;   E = Plain ).
%% new C(args): malloc's block constructed; delete p: destroyed, then freed
cpp_new(T, As, stmt_expr(block([declaration(0, none, T, [var(P, PT, new(T, []))]), expr(0, call(id(Name), [id(P)|As1])), expr(0, id(P))]))) :-
    cpp_class_of_type(T, C), cpp_has_ctors(C), !,
    length(As, N), ( cpp_ctor(C, N, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As1), ccl_gensym('$new', P), PT = ptr([], T).
cpp_new(T, As, new(T, As)).
cpp_delete(X, E) :- cpp_pointee_class_of(X, C), cpp_dtor(C, DName), !,
    (   X = id(_) -> E = comma(call(id(DName), [X]), delete(X))
    ;   ccl_type_of(X, PT), ccl_gensym('$del', P), E = stmt_expr(block([declaration(0, none, PT, [var(P, PT, X)]), expr(0, comma(call(id(DName), [id(P)]), delete(id(P))))])) ).
cpp_delete(X, delete(X)).
