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
%% virtual, the third step: a polymorphic class carries `$vptr' (the first
%% member of the class that introduces it, after `$base' when it has one), a
%% pointer to a struct `C.vt' of function pointers, one per virtual method
%% in the order they were introduced (the base's first, an override in its
%% base's slot, `$dtor' for a virtual destructor); every class has its own
%% table, the global `C.vtable', filled with the most derived
%% implementations, and every constructor stores its address after the
%% base's constructor ran; a call through a pointer or a reference goes
%% `p->$vptr->m(p)', a call on a value straight to the function; `delete p'
%% destroys through the slot. Single inheritance puts the base at offset 0,
%% so `this' is never adjusted.
%%
%% Templates, the fourth step: instantiated on use, a copy of the item with
%% the parameters substituted (cpp_subst/3), named `N.key.key' by its
%% arguments (`Buf.int.4', `max2.double'); a class template at every
%% template-id type met by the walk (cpp_type/2, the hook every type goes
%% through), registered and desugared like a class written out; a function
%% template at a call, its type arguments explicit or deduced from the
%% arguments' types (cpp_match/5), declared and walked like a function
%% written out; the instances join the unit's items at its end, the
%% template item itself is nothing. A template from a header's summary has
%% no body to copy and is refused.
%%
%% Not this step (refused by name): more than one base, a member of class
%% type with a constructor, an array of a class, a global of a class with a
%% constructor, a temporary's destructor, operator= and copy constructors
%% (a struct copies), a pure virtual method, partial and explicit
%% specializations, a template's non-type argument deduced.

ccl_cpp_units(Units0, Units) :- cpp_register_units(Units0), cpp_units(Units0, Units).
cpp_units([], []).
cpp_units([unit(Is0)|Us0], [unit(Is)|Us]) :- cpp_items(Is0, Is1), cpp_flush_instances(Is1, Is), cpp_units(Us0, Us).
%% the instances made while the unit was walked join its items; walking them may make more
cpp_flush_instances(Is0, Is) :-
    nb_getval('$cpp_instance_items', New),
    ( New == [] -> Is = Is0 ; nb_setval('$cpp_instance_items', []), reverse(New, Ordered), append(Is0, Ordered, Is1), cpp_flush_instances(Is1, Is) ).

%% ---- the classes of the units: '$cpp_classes' = [C-cls(Base, Data, Members, Statics, Defaults) ...] --------
cpp_register_units(Units) :-
    nb_setval('$cpp_classes', []), nb_setval('$cpp_defaults', []), nb_setval('$cpp_free_ops', []), nb_setval('$cpp_dtor_defs', []),
    nb_setval('$cpp_templates', []), nb_setval('$cpp_instances', []), nb_setval('$cpp_instance_items', []),
    forall(member(unit(Is), Units), cpp_register_(Is)).
cpp_register_([template(_, TPs, Item)|Is]) :- !, ( cpp_template_name(Item, N) -> nb_getval('$cpp_templates', Ts), nb_setval('$cpp_templates', [N-tmpl(TPs, Item)|Ts]) ; true ), cpp_register_(Is).
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
    ( member(method(ML, _, _, _, _, _, none), Ms), member(method(ML, Qs, _, _, _, _, _), Ms), memberchk(pure, Qs) -> cpp_refuse(ML, pure_virtual(C)) ; true ),
    cpp_split_members(Ms, Data0, Statics, Defaults),
    cpp_slots(Base, Ms, C, Slots),
    (   Slots \== [], \+ cpp_polymorphic(Base)                          % the class introduces the table: its pointer is a member of its own
    ->  cpp_vt_tag(C, VT), Data = [member(ptr([], base([], [struct(VT, none)])), '$vptr', none)|Data0]
    ;   Data = Data0 ),
    nb_getval('$cpp_classes', Cs), nb_setval('$cpp_classes', [C-cls(Base, Data, Ms, Statics, Defaults, Slots)|Cs]),
    cpp_declare_members(Ms, C), cpp_declare_statics(Statics, C).
%% the virtual slots of a class: the base's, an own virtual method (or one
%% that overrides a slot) appended when new, `$dtor' for a virtual destructor
cpp_slots(Base, Ms, C, Slots) :-
    ( Base == none -> S0 = [] ; cpp_class(Base, cls(_, _, _, _, _, S0)) ),
    cpp_own_slots(Ms, C, S0, Slots).
cpp_own_slots([], _, S, S).
cpp_own_slots([method(_, Qs, Ret, M, Ps, V, _)|Ms], C, S0, S) :-
    length(Ps, K),
    (   ( memberchk(virtual, Qs) ; memberchk(slot(M, K, _, _, _), S0) )
    ->  ( memberchk(slot(M, K, _, _, _), S0) -> S1 = S0 ; cpp_plain_params(Ps, Ps1), append(S0, [slot(M, K, Ret, Ps1, V)], S1) )
    ;   S1 = S0 ),
    cpp_own_slots(Ms, C, S1, S).
cpp_own_slots([dtor(_, Qs, _)|Ms], C, S0, S) :- memberchk(virtual, Qs), \+ memberchk(slot('$dtor', 0, _, _, _), S0), !,
    append(S0, [slot('$dtor', 0, base([], [void]), [], false)], S1), cpp_own_slots(Ms, C, S1, S).
cpp_own_slots([_|Ms], C, S0, S) :- cpp_own_slots(Ms, C, S0, S).
cpp_polymorphic(C) :- C \== none, cpp_class(C, cls(_, _, _, _, _, Slots)), Slots \== [].
cpp_slot(C, M, K, M) :- cpp_class(C, cls(_, _, _, _, _, Slots)), memberchk(slot(M, K, _, _, _), Slots), !.
%% the class whose table a pointer to C dispatches through: the first polymorphic one up the chain
cpp_vt_owner(C, Owner) :- cpp_class(C, cls(B, _, _, _, _, _)), ( cpp_polymorphic(B) -> cpp_vt_owner(B, Owner) ; Owner = C ).
cpp_vt_tag(C, VT) :- atomic_list_concat([C, '.vt'], VT).
cpp_vtable_name(C, N) :- atomic_list_concat([C, '.vtable'], N).
%% the implementation a class's table holds for a slot: its own, else the base's
cpp_slot_impl(C, '$dtor', _, Name) :- !, cpp_dtor(C, Name).
cpp_slot_impl(C, M, K, Name) :- cpp_class(C, cls(B, _, Ms, _, _, _)), ( member(method(_, _, _, M, Ps, _, _), Ms), length(Ps, K) -> cpp_mangle(C, M, Ps, Name) ; B \== none, cpp_slot_impl(B, M, K, Name) ).
cpp_split_members([], [], [], []).
cpp_split_members([member(base(Q, S), N, _)|Ms], Data, [N-base(Q1, S)|Ss], Ds) :- memberchk(static, Q), !, ccl_delete_one(Q, static, Q1), cpp_split_members(Ms, Data, Ss, Ds).
cpp_split_members([member(T0, N, _)|Ms], [member(T, N, none)|Data], Ss, Ds) :- !, cpp_type(T0, T), cpp_split_members(Ms, Data, Ss, Ds).
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
cpp_class_of_type_(base(_, [typedef(X)]), C) :- cpp_template_id(X, N, Args), !, cpp_types(Args, Args1), cpp_instantiate_class(N, Args1, C).   % a template-id the table still holds raw
cpp_pointee_class(T, C) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ), cpp_class_of_type(E, C).
cpp_class_of_type_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_class_of_type(T, C).
cpp_pointee_class_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_pointee_class(T, C).
%% the members: data (own and inherited, with the hops through '$base'), the statics, methods, constructors, the destructor
cpp_data_member(C, N, []) :- cpp_class(C, cls(_, Data, _, _, _, _)), memberchk(member(_, N, _), Data), !.
cpp_data_member(C, N, ['$base'|Hops]) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_data_member(B, N, Hops).
cpp_static_member(C, N, Name) :- cpp_class(C, cls(B, _, _, Ss, _, _)), ( memberchk(N-_, Ss) -> atomic_list_concat([C, '.', N], Name) ; B \== none, cpp_static_member(B, N, Name) ).
cpp_method(C, M, NArgs, Name, Hops) :-
    cpp_class(C, cls(B, _, Ms, _, _, _)),
    (   member(method(_, _, _, M, Ps, _, _), Ms), cpp_arity_fits(Ps, NArgs) -> cpp_mangle(C, M, Ps, Name), Hops = []
    ;   B \== none, cpp_method(B, M, NArgs, Name, Hops1), Hops = ['$base'|Hops1] ).
cpp_ctor(C, NArgs, Name) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, NArgs), !, cpp_mangle(C, C, Ps, Name).
cpp_ctor(C, 0, Name) :- cpp_implicit_ctor_needed(C), cpp_mangle(C, C, [], Name).
cpp_has_ctors(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), memberchk(ctor(_, _, _, _, _), Ms), !.
cpp_has_ctors(C) :- cpp_implicit_ctor_needed(C).
cpp_implicit_ctor_needed(C) :- cpp_class(C, cls(B, _, Ms, _, Defaults, _)), \+ memberchk(ctor(_, _, _, _, _), Ms), ( Defaults \== [] ; B \== none, cpp_has_ctors(B) ; cpp_polymorphic(C) ), !.
cpp_dtor(C, Name) :- cpp_own_dtor(C, Name), !.
cpp_dtor(C, Name) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_dtor(B, Name).      % none of its own: the base's runs on it (the base at offset 0)
cpp_own_dtor(C, Name) :- cpp_class(C, cls(_, _, Ms, _, _, _)), ( memberchk(dtor(_, _, _), Ms) ; nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ), !, atomic_list_concat([C, '.dtor.0'], Name).
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
cpp_plain_params([param(T0, N, _)|Ps], [param(T, N)|Qs]) :- !, cpp_type(T0, T), cpp_plain_params(Ps, Qs).
cpp_plain_params([param(T0, N)|Ps], [param(T, N)|Qs]) :- !, cpp_type(T0, T), cpp_plain_params(Ps, Qs).
cpp_plain_params([P|Ps], [P|Qs]) :- cpp_plain_params(Ps, Qs).
cpp_this_type(C, Quals, ptr([], base(Q, [typedef(C)]))) :- ( memberchk(const, Quals) -> Q = [const] ; Q = [] ).
cpp_refuse(L, What) :- throw(error(not_lowered(What), where(file, line(L)))).

%% ---- items ----------------------------------------------------------------------
cpp_items([], []).
cpp_items([I|Is], Out) :- cpp_item(I, Js), append(Js, Out1, Out), cpp_items(Is, Out1).
%% a class: the struct, the statics, then its members as functions
cpp_item(declare(L, base(Q, [class(_, C, _, _)])), Items) :- !,
    cpp_class(C, cls(Base, Data, Ms, Statics, Defaults, Slots)),
    ( Base == none -> Data1 = Data ; Data1 = [member(base([], [typedef(Base)]), '$base', none)|Data] ),
    cpp_static_decls(L, C, Statics, Fns0),
    cpp_member_fns(Ms, C, Base, Defaults, Fns1),
    ( cpp_implicit_ctor_needed(C) -> cpp_implicit_ctor(L, C, Base, Defaults, Fns2) ; Fns2 = [] ),
    append(Fns0, Fns1, Fns01), append(Fns01, Fns2, Fns),
    (   Slots == [] -> Items = [declare(L, base(Q, [struct(C, Data1)]))|Fns]
    ;   cpp_vt_struct(L, C, Slots, VtDecl), cpp_vtable(L, C, Slots, Table),
        Items = [VtDecl, declare(L, base(Q, [struct(C, Data1)]))|Fns1x], append(Fns, [Table], Fns1x) ).
%% the table's struct: a function pointer per slot, over the owner's pointer; the table: the class's implementations
cpp_vt_struct(L, C, Slots, declare(L, base([], [struct(VT, Ms)]))) :-
    cpp_vt_tag(C, VT), cpp_vt_owner(C, Owner), cpp_this_type(Owner, [], ThisT),
    findall(member(ptr([], fn(Ret, [param(ThisT, this)|Ps], V)), M, none), member(slot(M, _, Ret, Ps, V), Slots), Ms).
cpp_vtable(L, C, Slots, declaration(L, static, base([], [struct(VT, none)]), [var(Name, base([], [struct(VT, none)]), init(Items))])) :-
    cpp_vt_tag(C, VT), cpp_vtable_name(C, Name),
    findall(item([], E), ( member(slot(M, K, _, _, _), Slots), ( cpp_slot_impl(C, M, K, Impl) -> E = id(Impl) ; E = nullptr ) ), Items).
%% the store of the table's address, first thing after the base was constructed
cpp_vptr_store(L, C, [expr(L, assign('=', arrow(this, '$vptr'), cast(ptr([], base([], [struct(VT, none)])), addr(id(Table)))))]) :-
    cpp_polymorphic(C), !, cpp_vt_owner(C, Owner), cpp_vt_tag(Owner, VT), cpp_vtable_name(C, Table).
cpp_vptr_store(_, _, []).
cpp_item(declaration(L, Sto, B, [var(scoped([C], N), T, Init)]), [declaration(L, Sto, B, [var(Name, T, Init1)])]) :- cpp_class(C, _), !,
    atomic_list_concat([C, '.', N], Name), cpp_expr(none, Init, Init1).
cpp_item(function(L, Sto, Ret, scoped([C], M), Ps, V, Body), [function(L, Sto, Ret, Name, [param(ThisT, this)|Ps1], V, Body1)]) :- cpp_class(C, _), !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], ThisT),
    cpp_method_body(C, [param(ThisT, this)|Ps1], Body, Body1).
cpp_item(dtor_def(L, C, _, Body), [function(L, none, base([], [void]), Name, [param(ThisT, this)], false, Body1)]) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], ThisT), cpp_dtor_body(L, C, Body, Body0), cpp_method_body(C, [param(ThisT, this)], Body0, Body1).
%% a destructor's body, then the base's destructor over the base sub-object
cpp_dtor_body(L, C, block(Body), block(Body1)) :-
    cpp_class(C, cls(B, _, _, _, _, _)),
    ( B \== none, cpp_dtor(B, BName) -> append(Body, [expr(L, call(id(BName), [addr(arrow(this, '$base'))]))], Body1) ; Body1 = Body ).
cpp_item(function(L, Sto, Ret, operator(Op), Ps, V, Body), [function(L, Sto, Ret, Name, Ps1, V, Body1)]) :- !,
    cpp_free_operator(Op, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_method_body(none, Ps1, Body, Body1).
cpp_item(function(L, Sto, Ret0, N, Ps, V, Body), [function(L, Sto, Ret, N, Ps1, V, Body1)]) :- !,
    cpp_type(Ret0, Ret), cpp_plain_params(Ps, Ps1), cpp_method_body(none, Ps1, Body, Body1).
cpp_item(declaration(L, Sto, B, Vs), [declaration(L, Sto, B, Vs1)]) :- !, cpp_vars(none, Vs, Vs1).
cpp_item(typedef(L, Vs), [typedef(L, Vs1)]) :- !, cpp_vars(none, Vs, Vs1), ccl_note_typedefs(Vs1).   % the table learns the instance's name at once
cpp_item(template(_, _, _), []) :- !.
cpp_item(namespace(L, N, Is), [namespace(L, N, Js)]) :- !, cpp_items(Is, Js).
cpp_item(extern_c(L, Is), [extern_c(L, Js)]) :- !, cpp_items(Is, Js).
cpp_item(I, [I]).
cpp_vars(_, [], []).
cpp_vars(Ctx, [var(N, fn(R0, Ps, V), I)|Vs], [var(N, fn(R, Ps1, V), I)|Ws]) :- !, cpp_type(R0, R), cpp_plain_params(Ps, Ps1), cpp_vars(Ctx, Vs, Ws).
cpp_vars(Ctx, [var(N, T0, I)|Vs], [var(N, T, I1)|Ws]) :- cpp_type(T0, T), cpp_expr(Ctx, I, I1), cpp_vars(Ctx, Vs, Ws).
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
    ;   cpp_dtor_body(L, C, Body, Body0), cpp_method_body(C, Params, Body0, Body1), Fs = [function(L, none, base([], [void]), Name, Params, false, Body1)|Fs1] ),
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
    cpp_vptr_store(L, C, Store), append(Store, Pre2, Pre1),
    cpp_class(C, cls(_, Data, _, _, _, _)),
    cpp_member_inits(Data, Inits, Defaults, L, Pre2, Body).
cpp_member_inits([], _, _, _, Body, Body).
cpp_member_inits([member(_, '$vptr', _)|Ds], Inits, Defaults, L, Pre, Body) :- !, cpp_member_inits(Ds, Inits, Defaults, L, Pre, Body).
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
cpp_stmt(Ctx, for_each(L, var(N, T0, I), R, S), for_each(L, var(N, T, I), R1, S1)) :- !,
    cpp_type(T0, T), cpp_expr(Ctx, R, R1), ccl_scope_push, ccl_declare(N, T), cpp_stmt(Ctx, S, S1), ccl_scope_pop.
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
cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T0, I)|Vs], Pieces) :-
    cpp_type(T0, T),
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
cpp_expr(Ctx, new(T0, As), E) :- !, cpp_type(T0, T), cpp_exprs(Ctx, As, As1), cpp_new(T, As1, E).
cpp_expr(Ctx, new_array(T0, N), new_array(T, N1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, N, N1).
cpp_expr(Ctx, cast(T0, X), cast(T, X1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, X, X1).
cpp_expr(_, sizeof_type(T0), sizeof_type(T)) :- !, cpp_type(T0, T).
cpp_expr(Ctx, compound_lit(T0, I), compound_lit(T, I1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, I, I1).
cpp_expr(Ctx, delete(X), E) :- !, cpp_expr(Ctx, X, X1), cpp_delete(X1, E).
cpp_expr(Ctx, ccast(functional, base(Q, [typedef(C)]), X), E) :- cpp_class(C, _), !, cpp_expr(Ctx, X, X1), cpp_temporary(base(Q, [typedef(C)]), C, [X1], E).
cpp_expr(Ctx, ccast(K, T0, X), ccast(K, T, X1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, X, X1).
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
    ->  cpp_fill_defaults(Name, As, As1),
        (   cpp_slot(C, M, N, Slot), \+ cpp_static_object(X) -> cpp_dispatch(addr(X), C, Slot, As1, E)   % a reference, *p: the dynamic type's
        ;   cpp_hops(X, Hops, B), E = call(id(Name), [addr(B)|As1]) )
    ;   E = call(member(X, M), As) ).
cpp_call(Ctx, arrow(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_pointee_class_of(X, C), length(As, N), cpp_method(C, M, N, Name, Hops)
    ->  cpp_fill_defaults(Name, As, As1),
        (   cpp_slot(C, M, N, Slot) -> cpp_dispatch(X, C, Slot, As1, E)
        ;   ( Hops == [] -> P = X ; cpp_hops(deref(X), Hops, B), P = addr(B) ), E = call(id(Name), [P|As1]) )
    ;   E = call(arrow(X, M), As) ).
cpp_call(Ctx, id(M), As, E) :- Ctx \== none, \+ cpp_local(M), length(As, N), cpp_method(Ctx, M, N, Name, Hops), !,
    cpp_fill_defaults(Name, As, As1),
    (   cpp_slot(Ctx, M, N, Slot) -> cpp_dispatch(id(this), Ctx, Slot, As1, E)
    ;   ( Hops == [] -> P = id(this) ; cpp_hops(deref(id(this)), Hops, B), P = addr(B) ), E = call(id(Name), [P|As1]) ).
%% p->$vptr->slot(p, args), the pointer to the table found through the base sub-objects
cpp_dispatch(P, C, Slot, As, call(arrow(Vptr, Slot), [P|As])) :- cpp_data_member(C, '$vptr', Hops), cpp_access(P, '$vptr', Hops, Vptr).
%% a value whose dynamic type is its static one: a named object, or a member of one; not a reference
cpp_static_object(id(N)) :- ccl_declared(N, T), \+ T = ref(_, _), \+ T = rref(_, _).
cpp_static_object(member(X, _)) :- cpp_static_object(X).
cpp_call(_, tmpl(F, TArgs), As, call(id(Name), As)) :- cpp_template(F, _, function(_, _, _, _, _, _, _)), !, cpp_types(TArgs, TArgs1), cpp_instantiate_function(F, TArgs1, As, Name).
cpp_call(_, id(F), As, call(id(Name), As)) :- \+ cpp_local(F), cpp_template(F, _, function(_, _, _, _, _, _, _)), !, cpp_instantiate_function(F, [], As, Name).
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
    (   X = id(_) -> cpp_destroy(X, C, DName, D), E = comma(D, delete(X))
    ;   ccl_type_of(X, PT), ccl_gensym('$del', P), cpp_destroy(id(P), C, DName, D), E = stmt_expr(block([declaration(0, none, PT, [var(P, PT, X)]), expr(0, comma(D, delete(id(P))))])) ).
cpp_destroy(P, C, _, E) :- cpp_slot(C, '$dtor', 0, Slot), !, cpp_dispatch(P, C, Slot, [], E).
cpp_destroy(P, _, DName, call(id(DName), [P])).
cpp_delete(X, delete(X)).

%% ---- templates, instantiated on use --------------------------------------------------
%% '$cpp_templates' = [Name-tmpl(TParams, Item) ...]; '$cpp_instances' = [InstanceName-Template ...];
%% '$cpp_instance_items' the items the instances made, newest first
cpp_template_name(function(_, _, _, N, _, _, _), N) :- atom(N).
cpp_template_name(declare(_, base(_, [class(_, N, _, _)])), N).
cpp_template_name(declare(_, base(_, [struct(N, _)])), N).
cpp_template(N, TPs, Item) :- nb_getval('$cpp_templates', Ts), memberchk(N-tmpl(TPs, Item), Ts).
%% every type the walk meets goes through here: a template-id becomes its instance's name
cpp_type(T0, T) :- \+ compound(T0), !, T = T0.
cpp_type(base(Q, [typedef(X)]), base(Q, [typedef(Name)])) :- cpp_template_id(X, N, Args), !, cpp_types(Args, Args1), cpp_instantiate_class(N, Args1, Name).
cpp_type(base(Q, S), base(Q, S)) :- !.
cpp_type(ptr(Q, T0), ptr(Q, T)) :- !, cpp_type(T0, T).
cpp_type(ref(Q, T0), ref(Q, T)) :- !, cpp_type(T0, T).
cpp_type(rref(Q, T0), rref(Q, T)) :- !, cpp_type(T0, T).
cpp_type(arr(N, T0), arr(N, T)) :- !, cpp_type(T0, T).
cpp_type(fn(R0, Ps0, V), fn(R, Ps, V)) :- !, cpp_type(R0, R), cpp_plain_params(Ps0, Ps).
cpp_type(T, T).
cpp_types([], []).
cpp_types([T0|Ts], [T|Us]) :- cpp_type(T0, T), cpp_types(Ts, Us).
cpp_template_id(tmpl(N, Args), N, Args).
cpp_template_id(scoped(_, tmpl(N, Args)), N, Args).                      % a namespace flattens here too
%% the walk of an instance sees no local of the function that met it: the scopes are set aside
cpp_isolated(Goal) :- nb_getval('$ccl_scope', S), nb_setval('$ccl_scope', []), ( call(Goal) -> nb_setval('$ccl_scope', S) ; nb_setval('$ccl_scope', S), fail ).
cpp_add_instance_items(Items) :- nb_getval('$cpp_instance_items', Old), reverse(Items, R), append(R, Old, New), nb_setval('$cpp_instance_items', New).
%% a class template at its arguments: registered and desugared like a class written out, once
cpp_instantiate_class(N, Args, Name) :-
    ( cpp_template(N, TPs, Item) -> true ; cpp_refuse(0, template_without_body(N)) ),
    cpp_bind_targs(TPs, Args, B), cpp_instance_name(N, TPs, B, Name),
    nb_getval('$cpp_instances', Done),
    (   memberchk(Name-_, Done) -> true
    ;   nb_setval('$cpp_instances', [Name-N|Done]),
        cpp_subst(Item, B, Item1), cpp_instance_class(Item1, L, K, Bases, Ms),
        cpp_isolated(( cpp_register_class(L, Name, Bases, Ms), cpp_item(declare(L, base([], [class(K, Name, Bases, Ms)])), Items) )),
        cpp_add_instance_items(Items) ).
cpp_instance_class(declare(L, base(_, [class(K, _, Bases, Ms)])), L, K, Bases, Ms).
cpp_instance_class(declare(L, base(_, [struct(_, Ms)])), L, struct, [], Ms).
%% a function template at a call: its type arguments explicit, then deduced from the arguments' types, then defaulted
cpp_instantiate_function(F, Explicit, As, Name) :-
    cpp_template(F, TPs, function(L, Sto, Ret, _, Ps, V, Body)),
    cpp_bind_explicit(TPs, Explicit, B0), cpp_deduce_args(Ps, As, TPs, B0, B1), cpp_bind_defaults(TPs, B1, B),
    cpp_instance_name(F, TPs, B, Name),
    nb_getval('$cpp_instances', Done),
    (   memberchk(Name-_, Done) -> true
    ;   nb_setval('$cpp_instances', [Name-F|Done]),
        cpp_subst(fn(Ret, Ps, Body), B, fn(Ret1, Ps1, Body1)),
        cpp_isolated(( cpp_type(Ret1, Ret2), cpp_plain_params(Ps1, Ps2), ccl_declare(Name, fn(Ret2, Ps2, V)), cpp_note_defaults(Name, Ps1),
                       cpp_item(function(L, Sto, Ret1, Name, Ps1, V, Body1), Items) )),
        cpp_add_instance_items(Items) ).
cpp_bind_targs([], _, []).
cpp_bind_targs([tparam(_, P, D)|TPs], Args, [P-A|B]) :-
    ( Args = [A0|Rest] -> A = A0 ; D \== none -> A = D, Rest = [] ; cpp_refuse(0, template_argument_missing(P)) ),
    cpp_bind_targs(TPs, Rest, B).
cpp_bind_explicit([], _, []) :- !.
cpp_bind_explicit(_, [], []) :- !.
cpp_bind_explicit([tparam(_, P, _)|TPs], [A|As], [P-A|B]) :- cpp_bind_explicit(TPs, As, B).
cpp_bind_defaults([], B, B).
cpp_bind_defaults([tparam(_, P, D)|TPs], B0, B) :- ( memberchk(P-_, B0) -> B1 = B0 ; D \== none -> B1 = [P-D|B0] ; cpp_refuse(0, cannot_deduce(P)) ), cpp_bind_defaults(TPs, B1, B).
cpp_deduce_args([], _, _, B, B) :- !.
cpp_deduce_args(_, [], _, B, B) :- !.
cpp_deduce_args([P|Ps], [A|As], TPs, B0, B) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, cpp_deduce_one(PT, A, TPs, B0, B1), cpp_deduce_args(Ps, As, TPs, B1, B).
cpp_deduce_args([_|Ps], [_|As], TPs, B0, B) :- cpp_deduce_args(Ps, As, TPs, B0, B).
cpp_deduce_one(PT, A, TPs, B0, B) :- ( ccl_type_of(A, AT), AT \== unknown -> cpp_match(PT, AT, TPs, B0, B) ; B = B0 ).
cpp_match(base(_, [typedef(P)]), AT, TPs, B0, B) :- memberchk(tparam(type, P, _), TPs), !, ( memberchk(P-_, B0) -> B = B0 ; cpp_decayed(AT, AT1), B = [P-AT1|B0] ).
cpp_match(ptr(_, X), AT, TPs, B0, B) :- ccl_resolve_type(AT, AT1), ( AT1 = ptr(_, Y) ; AT1 = arr(_, Y) ), !, cpp_match(X, Y, TPs, B0, B).
cpp_match(ref(_, X), AT, TPs, B0, B) :- !, cpp_match(X, AT, TPs, B0, B).
cpp_match(rref(_, X), AT, TPs, B0, B) :- !, cpp_match(X, AT, TPs, B0, B).
cpp_match(_, _, _, B, B).
cpp_decayed(T, T1) :- ( ccl_resolve_type(T, arr(_, E)) -> T1 = ptr([], E) ; T = base(_, S) -> T1 = base([], S) ; T1 = T ).
%% the instance's name: the template's, then a key per argument
cpp_instance_name(N, TPs, B, Name) :- findall(K, ( member(tparam(_, P, _), TPs), memberchk(P-A, B), cpp_type_key(A, K) ), Ks), atomic_list_concat([N|Ks], '.', Name).
cpp_type_key(base(_, S), K) :- !, findall(W, ( member(X, S), cpp_spec_key(X, W) ), Ws), atomic_list_concat(Ws, '_', K).
cpp_type_key(ptr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_p', K).
cpp_type_key(ref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_r', K).
cpp_type_key(rref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_rr', K).
cpp_type_key(arr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_a', K).
cpp_type_key(int(N), N) :- !.
cpp_type_key(neg(int(N)), K) :- !, atom_concat(m, N, K).
cpp_type_key(chr(C), K) :- !, atom_concat(c, C, K).
cpp_type_key(bool(B), B) :- !.
cpp_type_key(id(X), X) :- !.
cpp_type_key(X, K) :- term_to_atom(X, A), atom_codes(A, Cs), findall(C, ( member(C, Cs), ( C >= 0'a, C =< 0'z ; C >= 0'A, C =< 0'Z ; C >= 0'0, C =< 0'9 ) ), Ds), atom_codes(K, Ds).
cpp_spec_key(typedef(X), X) :- atom(X), !.
cpp_spec_key(struct(T, _), T) :- !.
cpp_spec_key(class(_, T, _, _), T) :- !.
cpp_spec_key(enum(T, _), T) :- !.
cpp_spec_key(enum_class(T, _), T) :- !.
cpp_spec_key(X, X) :- atom(X), !.
cpp_spec_key(X, K) :- cpp_type_key(X, K).
%% the parameters substituted through the item: a type parameter's typedef becomes the
%% argument (its qualifiers kept), a non-type parameter's name the value
cpp_subst(T, _, T) :- \+ compound(T), !.
cpp_subst(base(Q, [typedef(P)]), B, T) :- memberchk(P-A, B), !, cpp_merge_quals(Q, A, T).
cpp_subst(id(P), B, V) :- memberchk(P-V, B), !.
cpp_subst(str(S), _, str(S)) :- !.
cpp_subst(T0, B, T) :- T0 =.. [F|As], cpp_subst_list(As, B, Bs), T =.. [F|Bs].
cpp_subst_list([], _, []).
cpp_subst_list([X|Xs], B, [Y|Ys]) :- cpp_subst(X, B, Y), cpp_subst_list(Xs, B, Ys).
cpp_merge_quals(Q, base(Q2, S), base(Q3, S)) :- !, append(Q, Q2, Q3).
cpp_merge_quals(_, A, A).
