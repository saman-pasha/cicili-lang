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
%% template item itself is nothing. The program's own headers, read whole,
%% give their templates and classes; a library header's summary has no
%% body to copy, and its template is refused: libc++'s containers await
%% the forms their bodies use (the standard library is libc++'s, never the
%% compiler's own -- the owner's rule).
%%
%% Lambdas, the fifth step: a lambda is a class `lambda.K' of its captures
%% -- a member per capture, by value a copy, by reference a reference
%% member (the lowering reads a reference member through, as a reference
%% variable) -- with `operator()' its body, made and desugared like a class
%% written out; the expression is a compound literal of the captures'
%% values (`&t' for a reference), `auto f = ...' takes its type, and a call
%% `f(a)' of a local of such a class goes to `lambda.K.op.call.n(&f, a)'.
%% A default capture takes every enclosing local the body names; the
%% result type is deduced from the first return when not given.
%%
%% Then, over classes of the program's own: overloads by type (a name
%% carries its parameters' types, a call picks by the arguments'), the rule
%% that a class with a destructor is never copied but moved (`std::move' is
%% Cicili's move, a struct moved whole empties its owners behind it, a
%% by-value argument hands its owners to the callee), the explicit
%% destructor call `x.~T()', and a member of class type constructed and
%% destroyed with its holder.
%%
%% Not this step (refused by name): more than one base, a member of class
%% type with a constructor, an array of a class, a global of a class with a
%% constructor, a temporary's destructor, operator= and copy constructors
%% (a struct copies), a pure virtual method, partial and explicit
%% specializations, a template's non-type argument deduced, `[this]' in a
%% lambda, a lambda in a template's body before its instantiation.

ccl_cpp_units(Units0, Units) :- cpp_register_units(Units0), cpp_units(Units0, Units).
cpp_units([], []).
cpp_units([unit(Is0)|Us0], [unit(Is)|Us]) :- cpp_items(Is0, Is1), cpp_flush_instances(Is1, Is), cpp_units(Us0, Us).
%% the instances made while the unit was walked join its items; walking them may make more
cpp_flush_instances(Is0, Is) :-
    findall(I, '$cpp_out'(I), New),
    ( New == [] -> Is = Is0 ; cpp_reset('$cpp_out'/1), append(Is0, New, Is1), cpp_flush_instances(Is1, Is) ).
%% the registries that hold class and template BODIES are facts, one row per name: a global list would be copied
%% whole at every lookup (nb_getval copies), and libc++'s bodies are megabytes (the finding in CLAUDE.md)
cpp_reset(F/A) :- ( catch(abolish(F/A), _, true) -> true ; true ), dynamic(F/A).
cpp_class_put(C, Cls) :- assertz('$cpp_cls'(C, Cls)).
cpp_template_put(N, TPs, Item) :- assertz('$cpp_tmpl'(N, TPs, Item)).
cpp_spec_put(N, TPs, Pat, Item) :- assertz('$cpp_spec'(N, TPs, Pat, Item)).
cpp_mt_put(C, K, TPs, M) :- assertz('$cpp_mt'(C, K, TPs, M)).
cpp_instance_done(Name) :- '$cpp_inst'(Name, _), !.
cpp_instance_note(Name, What) :- assertz('$cpp_inst'(Name, What)).

%% ---- the classes of the units: '$cpp_classes' = [C-cls(Base, Data, Members, Statics, Defaults) ...] --------
cpp_register_units(Units) :-
    cpp_reset('$cpp_cls'/2), cpp_reset('$cpp_tmpl'/3), cpp_reset('$cpp_spec'/4), cpp_reset('$cpp_mt'/4), cpp_reset('$cpp_inst'/2), cpp_reset('$cpp_out'/1),
    nb_setval('$cpp_defaults', []), nb_setval('$cpp_free_ops', []), nb_setval('$cpp_dtor_defs', []), nb_setval('$cpp_lambdas', 0),
    nb_setval('$cpp_concepts', []),
    nb_setval('$cpp_class_types', []), nb_setval('$cpp_static_inits', []),
    nb_setval('$cpp_lazy', []), nb_setval('$cpp_hdr_loaded', []), nb_setval('$cpp_budget', 0), nb_setval('$cpp_depth', 0), nb_setval('$cpp_class_ctx', none), ( catch(abolish('$cpp_hdr'/2), _, true) -> true ; true ), dynamic('$cpp_hdr'/2),
    forall(member(unit(Is), Units), cpp_register_(Is)).
cpp_register_([template(_, TPs, concept(_, N, E))|Is]) :- !, nb_getval('$cpp_concepts', Cs), nb_setval('$cpp_concepts', [N-concept(TPs, E)|Cs]), cpp_register_(Is).   % C++20
cpp_register_([concept(_, N, E)|Is]) :- !, nb_getval('$cpp_concepts', Cs), nb_setval('$cpp_concepts', [N-concept([], E)|Cs]), cpp_register_(Is).
cpp_register_([template(_, TPs, Item)|Is]) :- !,
    (   cpp_spec_name(Item, N, Pattern) -> cpp_spec_put(N, TPs, Pattern, Item)                                                     % a partial or full specialization, by its pattern
    ;   cpp_template_name(Item, N) -> cpp_template_put(N, TPs, Item)
    ;   true ),
    cpp_register_(Is).
cpp_spec_name(declare(_, base(_, [class(_, tmpl(N, P), _, _)])), N, P).
cpp_spec_name(declare(_, base(_, [struct(tmpl(N, P), _)])), N, P).
cpp_spec_name(declaration(_, _, _, [var(tmpl(N, P), _, _)]), N, P).
cpp_spec_name(function(_, _, _, tmpl(N, P), _, _, _), N, P).
cpp_register_([function(L, Sto, Ret, N, Ps, V, Body)|Is]) :- atom(N), cpp_auto_params(Ps, 0, Ps1, TPs), TPs \== [], !,    % C++20: an abbreviated function template, a template of invented parameters
    cpp_template_put(N, TPs, function(L, Sto, Ret, N, Ps1, V, Body)), cpp_register_(Is).
cpp_register_([include(_, _, file(_, preprocessed, unit(Js)))|Is]) :- !, cpp_index_header(Js), cpp_register_(Is).   % a library header, flattened: indexed by name, each item registered when a name is first asked for
cpp_register_([include(_, _, file(_, _, unit(Js)))|Is]) :- !, cpp_register_header(Js), cpp_register_(Is).   % a header read whole (the program's own): its classes and templates
%% '$cpp_hdr'(Name, Item): facts (found by name in microseconds; a global would copy the header at every read)
cpp_index_header(Js) :- cpp_index_items(Js).
cpp_index_items([]).
cpp_index_items([namespace(_, _, Js)|Is]) :- !, cpp_index_items(Js), cpp_index_items(Is).
cpp_index_items([extern_c(_, Js)|Is]) :- !, cpp_index_items(Js), cpp_index_items(Is).
cpp_index_items([I|Is]) :- ( cpp_index_name(I, N) -> assertz('$cpp_hdr'(N, I)) ; true ), cpp_index_items(Is).
cpp_index_name(template(_, _, I), N) :- !, ( cpp_spec_name(I, N, _) -> true ; cpp_template_name(I, N) ).
cpp_index_name(declare(_, base(_, [class(_, N, _, _)])), N) :- atom(N).
cpp_index_name(declare(_, base(_, [struct(N, Ms)])), N) :- atom(N), Ms \== none.
cpp_index_name(function(_, _, _, N, _, _, B), N) :- atom(N), B \== none.
cpp_index_name(ctor_def(_, C, _, _, _, _), C).
cpp_index_name(dtor_def(_, C, _, _), C).
%% a name the registries do not have: the header's items of that name, registered now (a class as a lazy one)
cpp_hdr_load(N) :- atom(N), '$cpp_hdr'(N, _), \+ ( nb_getval('$cpp_hdr_loaded', Ls), memberchk(N, Ls) ), !,
    cpp_spend(load(N)), nb_getval('$cpp_hdr_loaded', Ls0), nb_setval('$cpp_hdr_loaded', [N|Ls0]),
    findall(I, '$cpp_hdr'(N, I), Items), cpp_register_lazy(Items).
cpp_register_lazy([]).
cpp_register_lazy([declare(L, base(_, [class(K, C, Bases, Ms)]))|Is]) :- !, cpp_lazy_class(L, K, C, Bases, Ms), cpp_register_lazy(Is).
cpp_register_lazy([declare(L, base(_, [struct(C, Ms)]))|Is]) :- !, cpp_lazy_class(L, struct, C, [], Ms), cpp_register_lazy(Is).
cpp_register_lazy([function(L, Sto, Ret, N, Ps, V, Body)|Is]) :- atom(N), Body \== none, !,      % an inline function of the header: emitted, linkonce
    ( cpp_instance_done(N) -> true
    ; cpp_instance_note(N, hdr), cpp_isolated(cpp_item(function(L, Sto, Ret, N, Ps, V, Body), Items)), cpp_add_instance_items(Items) ),
    cpp_register_lazy(Is).
cpp_register_lazy([I|Is]) :- cpp_register_(I), cpp_register_lazy(Is).
cpp_register_(I) :- \+ ( I == [] ; I = [_|_] ), !, cpp_register_([I]).
%% a lazy class: registered, its struct emitted, its members emitted as they are first used (the standard's rule for a
%% template's members; a library class's methods are hundreds, a program uses three)
cpp_lazy_class(L, K, C, Bases, Ms) :-
    ( cpp_class(C, _) -> true
    ; nb_getval('$cpp_lazy', Lz), nb_setval('$cpp_lazy', [C|Lz]),
      cpp_isolated(( cpp_register_class(L, C, Bases, Ms), cpp_item(declare(L, base([], [class(K, C, Bases, Ms)])), Items) )), cpp_add_instance_items(Items) ).
cpp_is_lazy(C) :- nb_getval('$cpp_lazy', Lz), memberchk(C, Lz).
%% a member of a lazy class, first used: its function emitted now
cpp_use_member(C, Name) :-
    (   cpp_is_lazy(C), \+ cpp_instance_done(Name),
        cpp_class(C, cls(Base, _, Ms, _, Defaults, _)), member(M, Ms), cpp_member_mangled(C, M, Name)
    ->  cpp_instance_note(Name, C), cpp_isolated(cpp_in_class(C, cpp_member_fns([M], C, Base, Defaults, Fns))), cpp_add_instance_items(Fns)
    ;   true ).
cpp_member_mangled(C, method(_, _, _, M, Ps, _, _), Name) :- cpp_mangle(C, M, Ps, Name).
cpp_member_mangled(C, ctor(_, _, Ps, _, _), Name) :- cpp_mangle(C, C, Ps, Name).
cpp_member_mangled(C, dtor(_, _, _), Name) :- atomic_list_concat([C, '.dtor.0'], Name).
%% a header's items: its templates registered, its classes registered AND emitted into the unit (once), as an instance is
%% (a library header's summary carries names, not bodies: libc++'s templates do not instantiate yet)
cpp_register_header([]).
cpp_register_header([declare(L, base(_, [class(K, C, Bases, Ms)]))|Is]) :- !,
    (   cpp_class(C, _) -> true
    ;   cpp_isolated(( cpp_register_class(L, C, Bases, Ms), cpp_item(declare(L, base([], [class(K, C, Bases, Ms)])), Items) )), cpp_add_instance_items(Items) ),
    cpp_register_header(Is).
cpp_register_header([namespace(_, _, Js)|Is]) :- !, cpp_register_header(Js), cpp_register_header(Is).
cpp_register_header([I|Is]) :- cpp_register_([I]), cpp_register_header(Is).
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
cpp_register_class(L, C, Bases, Ms0) :- cpp_norm_members(Ms0, Ms), cpp_register_class_extras(C, Ms), cpp_in_class(C, cpp_register_class_(L, C, Bases, Ms)).   % its own typedefs resolve its members' types
cpp_register_class_(L, C, Bases, Ms) :-
    (   Bases = [] -> Base = none
    ;   Bases = [base(_, B0)] -> cpp_base_name(B0, Base)
    ;   cpp_refuse(L, multiple_inheritance(C)) ),

    cpp_split_members(Ms, Data0, Statics, Defaults),
    cpp_slots(Base, Ms, C, Slots),
    (   Slots \== [], \+ cpp_polymorphic(Base)                          % the class introduces the table: its pointer is a member of its own
    ->  cpp_vt_tag(C, VT), Data = [member(ptr([], base([], [struct(VT, none)])), '$vptr', none)|Data0]
    ;   Data = Data0 ),
    cpp_class_put(C, cls(Base, Data, Ms, Statics, Defaults, Slots)),
    ( Base == none -> Data1 = Data ; Data1 = [member(base([], [typedef(Base)]), '$base', none)|Data] ),
    ccl_note_tag(C, Data1),                                              % the struct it becomes, in the table at once: its members have types while its methods are walked
    cpp_in_class(C, ( cpp_declare_members(Ms, C), cpp_declare_statics(Statics, C) )).
%% what else a class carries: its member templates (by name; a constructor under `ctor'), its typedefs
%% (`typedef T value_type;', `using x = T;': what a dependent name `C::value_type' resolves to), and the
%% constant initializers of its static members (`static const bool value = true;': what `C::value' folds to)
cpp_register_class_extras(C, Ms) :-
    forall(( member(template(_, TPs, M), Ms), cpp_member_key(M, K) ), cpp_mt_put(C, K, TPs, M)),
    forall(( member(typedef(_, Vs), Ms), member(var(N, T, _), Vs) ), ( nb_getval('$cpp_class_types', L2), nb_setval('$cpp_class_types', [C-N-T|L2]) )),
    forall(( member(member(base(Q, _), N, _), Ms), memberchk(static, Q), member(default_init(N, E), Ms) ), ( nb_getval('$cpp_static_inits', L3), nb_setval('$cpp_static_inits', [C-N-E|L3]) )).
cpp_member_key(method(_, _, _, M, _, _, _), M).
cpp_member_key(ctor(_, _, _, _, _), ctor).
%% the class whose members are being declared, walked or emitted: a bare name in them may be its typedef
cpp_in_class(C, Goal) :- nb_getval('$cpp_class_ctx', C0), nb_setval('$cpp_class_ctx', C), ( catch(Goal, E, (nb_setval('$cpp_class_ctx', C0), throw(E))) -> nb_setval('$cpp_class_ctx', C0) ; nb_setval('$cpp_class_ctx', C0), fail ).
cpp_class_ctx(C) :- nb_getval('$cpp_class_ctx', C), C \== none.
cpp_class_typedef(C, N, T) :- nb_getval('$cpp_class_types', L), memberchk(C-N-T, L), !.
cpp_class_typedef(C, N, T) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_class_typedef(B, N, T).
cpp_static_const(C, N, V) :- nb_getval('$cpp_static_inits', L), memberchk(C-N-E, L), ( E = bool(_) -> V = E ; ccl_const_eval(E, K), V = int(K) ), !.
%% a base named by a template-id is its instance
cpp_base_name(B, B) :- atom(B), !.
cpp_base_name(B0, B) :- cpp_type(base([], [typedef(B0)]), base(_, [typedef(B)])), atom(B), !.
cpp_base_name(B0, _) :- cpp_refuse(0, base_not_a_class(B0)).
%% the class a scope names: `C', `X<T>' (its instance), `A::B<T>'; a namespace is no class
cpp_scope_class(Path, C) :- ccl_last(Path, P), cpp_path_class(P, C).
cpp_path_class(P, P) :- atom(P), cpp_class(P, _), !.
cpp_path_class(P, C) :- atom(P), cpp_class_ctx(Cx), cpp_class_typedef(Cx, P, T0), !, cpp_type(T0, T), cpp_class_of_type(T, C).   % __alloc_traits::pointer inside its class
cpp_path_class(tmpl(N, Args0), C) :- !, cpp_targ_values(Args0, Args), cpp_instantiate_type(N, Args, T), cpp_class_of_type(T, C).
cpp_path_class(scoped(_, Last), C) :- cpp_path_class(Last, C).
%% C++23: a method's explicit object parameter (`this Self &self', read as param(this(T), N) first among
%% the parameters) becomes the qualifier explicit_this(N, T), so the parameters are the ones a caller passes
cpp_norm_members([], []).
cpp_norm_members([M|Ms], Ms1) :- cpp_member_body(M, B), ( B == delete ; B == default ), !, cpp_norm_members(Ms, Ms1).   % `= delete': not there; `= default': the implicit one
cpp_norm_members([method(L, Qs, Ret, M, Ps, V, pure)|Ms], [method(L, [pure|Qs], Ret, M, Ps, V, none)|Ms1]) :- !, cpp_norm_members(Ms, Ms1).
cpp_norm_members([method(L, Qs, Ret, M, [param(this(T), N)|Ps], V, Body)|Ms], [method(L, [explicit_this(N, T)|Qs], Ret, M, Ps, V, Body)|Ms1]) :- !, cpp_norm_members(Ms, Ms1).
cpp_norm_members([M|Ms], [M|Ms1]) :- cpp_norm_members(Ms, Ms1).
cpp_member_body(method(_, _, _, _, _, _, B), B).
cpp_member_body(ctor(_, _, _, _, B), B).
cpp_member_body(dtor(_, _, B), B).
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
cpp_declare_members([method(L, Qs, Ret, M, Ps, V, _)|Ms], C) :- memberchk(explicit_this(N, T0), Qs), !,        % C++23: the object parameter as declared, no implicit this
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_self_param(L, C, N, T0, Self),
    ccl_declare(Name, fn(Ret, [Self|Ps1], V)), cpp_note_defaults(Name, Ps), cpp_declare_members(Ms, C).
cpp_declare_members([method(_, Qs, Ret0, M, Ps, V, Body)|Ms], C) :- !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, Qs, ThisT),
    cpp_method_ret(C, Ret0, [param(ThisT, this)|Ps1], Body, Ret),
    ccl_declare(Name, fn(Ret, [param(ThisT, this)|Ps1], V)), cpp_note_defaults(Name, Ps), cpp_declare_members(Ms, C).
%% `auto f()': the first return's expression, desugared (an instance's call has a type only then), typed
cpp_method_ret(C, base(_, [auto]), Params, Body, Ret) :- Body \== none, !,
    (   cpp_first_return(Body, E)
    ->  ccl_scope_push, ccl_declare_params(Params), cpp_expr(C, E, E1), ( ccl_type_of(E1, T), T \== unknown -> cpp_decayed(T, Ret) ; Ret = none ), ccl_scope_pop,
        ( Ret == none -> cpp_refuse(0, auto_result(C)) ; true )
    ;   Ret = base([], [void]) ).
cpp_method_ret(_, Ret0, _, _, Ret) :- cpp_type(Ret0, Ret).
cpp_declare_members([ctor(_, _, Ps, _, _)|Ms], C) :- !,
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], [fresh], ThisT),
    ccl_declare(Name, fn(base([], [void]), [param(ThisT, this)|Ps1], false)), cpp_note_defaults(Name, Ps), cpp_declare_members(Ms, C).
cpp_declare_members([dtor(_, _, _)|Ms], C) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], [dying], ThisT),
    ccl_declare(Name, fn(base([], [void]), [param(ThisT, this)], false)), cpp_declare_members(Ms, C).
cpp_declare_members([_|Ms], C) :- cpp_declare_members(Ms, C).
%% the explicit object parameter as the function's first: `this auto` on a method would make it a template (deduced_this)
cpp_self_param(L, C, N, T0, param(T, N)) :- ( cpp_auto_in(T0, 0, _, _) -> cpp_refuse(L, deduced_this(C)) ; cpp_type(T0, T) ).
%% a method with an explicit object parameter takes the object as declared -- by reference (its address, as any
%% reference argument), or a copy -- where an implicit this takes its address
cpp_object_arg(Name, Addr, Obj) :- ccl_declared(Name, fn(_, [param(_, First)|_], _)), First \== this, !, ( Addr = addr(B) -> Obj = B ; Obj = deref(Addr) ).
cpp_object_arg(_, Addr, Addr).
cpp_declare_statics([], _).
cpp_declare_statics([N-T|Ss], C) :- atomic_list_concat([C, '.', N], Name), ccl_declare(Name, T), cpp_declare_statics(Ss, C).
cpp_class(C, Cls) :- '$cpp_cls'(C, Cls), !.
cpp_class(C, Cls) :- cpp_hdr_load(C), '$cpp_cls'(C, Cls), !.
%% the class a type names, and the one a pointer's or an array's element names
cpp_class_of_type(T, C) :- ccl_resolve_type(T, T1), cpp_class_of_type_(T1, C).
cpp_class_of_type_(base(_, [class(_, C, _, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [struct(C, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [typedef(C)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [typedef(X)]), C) :- cpp_template_id(X, N, Args), !, cpp_targ_values(Args, Args1), cpp_instantiate_type(N, Args1, T), cpp_class_of_type(T, C).   % a template-id the table still holds raw
cpp_class_of_type_(base(_, [typedef(scoped(_, C))]), C) :- cpp_class(C, _), !.
cpp_pointee_class(T, C) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ), cpp_class_of_type(E, C).
cpp_class_of_type_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_class_of_type(T, C).
cpp_pointee_class_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_pointee_class(T, C).
%% the members: data (own and inherited, with the hops through '$base'), the statics, methods, constructors, the destructor
cpp_data_member(C, N, []) :- cpp_class(C, cls(_, Data, _, _, _, _)), memberchk(member(_, N, _), Data), !.
cpp_data_member(C, N, ['$base'|Hops]) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_data_member(B, N, Hops).
cpp_static_member(C, N, Name) :- cpp_class(C, cls(B, _, _, Ss, _, _)), ( memberchk(N-_, Ss) -> atomic_list_concat([C, '.', N], Name) ; B \== none, cpp_static_member(B, N, Name) ).
%% a method by its name and the ARGUMENTS: the overloads whose arity fits, the
%% one whose parameter types fit the arguments' best (cpp_pick/3); the base's
%% when the class has none
cpp_method(C, M, Args, Name, Hops) :-
    cpp_class(C, cls(B, _, Ms, _, _, _)), length(Args, N),
    findall(Ps, ( member(method(_, _, _, M, Ps, _, _), Ms), cpp_arity_fits(Ps, N) ), Cands),
    (   Cands \== [] -> cpp_pick(Cands, Args, Ps), cpp_mangle(C, M, Ps, Name), Hops = [], cpp_use_member(C, Name)
    ;   cpp_member_template_call(C, M, [], Args, Name) -> Hops = []                              % a member template, deduced from the arguments
    ;   B \== none, cpp_method(B, M, Args, Name, Hops1), Hops = ['$base'|Hops1] ).
%% an abstract class (a pure virtual method no class of the chain overrides) is declared, never constructed
cpp_not_abstract(C) :- ( cpp_class(C, cls(_, _, _, _, _, Slots)), member(slot(M, K, _, _, _), Slots), \+ cpp_slot_impl(C, M, K, _) -> cpp_refuse(0, pure_virtual(C)) ; true ).
cpp_ctor(C, Args, Name) :-
    cpp_not_abstract(C), cpp_class(C, cls(_, _, Ms, _, _, _)), length(Args, N),
    findall(Ps, ( member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, N) ), Cands), Cands \== [], !,
    cpp_pick(Cands, Args, Ps), cpp_mangle(C, C, Ps, Name), cpp_use_member(C, Name).
cpp_ctor(C, Args, Name) :- cpp_member_template_ctor(C, Args, Name), !.                       % a constructor template, deduced
cpp_ctor(C, [], Name) :- cpp_implicit_ctor_needed(C), cpp_mangle(C, C, [], Name).
cpp_pick([Ps], _, Ps) :- !.
cpp_pick(Cands, Args, Ps) :- cpp_best(Cands, Args, none, -1, Ps).
cpp_best([], _, Best, _, Best).
cpp_best([Ps|Cs], Args, B0, S0, Best) :- cpp_score(Ps, Args, S), ( S > S0 -> cpp_best(Cs, Args, Ps, S, Best) ; cpp_best(Cs, Args, B0, S0, Best) ).
cpp_score([], _, 0) :- !.
cpp_score(_, [], 0) :- !.
cpp_score([P|Ps], [A|As], S) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, cpp_arg_fit(PT, A, S1), cpp_score(Ps, As, S2), S is S1 + S2.
%% how an argument fits a parameter: the same class 3, both pointers 2, both arithmetic 2, unknown 1, else 0
cpp_arg_fit(PT, A, 0) :- cpp_category_mismatch(PT, A), !.                                    % an rvalue reference binds no lvalue, a plain one no rvalue
cpp_arg_fit(PT, A, S) :-
    (   ccl_type_of(A, AT), AT \== unknown
    ->  ccl_unref(PT, PT1), ccl_unref(AT, AT1),
        (   cpp_class_of_type(PT1, C), cpp_class_of_type(AT1, C) -> ( PT = rref(_, _), \+ cpp_lvalue(A) -> S = 4 ; S = 3 )   % an rvalue takes the move constructor first
        ;   cpp_pointerish(PT1), cpp_pointerish(AT1) -> S = 2
        ;   ccl_is_arith(PT1), ccl_is_arith(AT1) -> S = 2
        ;   S = 0 )
    ;   S = 1 ).
cpp_pointerish(T) :- ccl_resolve_type(T, R), ( R = ptr(_, _) ; R = arr(_, _) ), !.
cpp_category_mismatch(rref(_, _), A) :- cpp_lvalue(A), !.
cpp_category_mismatch(ref(Q, base(Q2, _)), A) :- \+ memberchk(const, Q), \+ memberchk(const, Q2), \+ cpp_lvalue(A), \+ A = move(_), !.
%% a reference parameter takes the object: `move(x)' handed to `C &&' is x itself (its address), the move being the callee's
cpp_ref_args(Name, As, As1) :- ccl_declared(Name, fn(_, Ps, _)), !, cpp_ref_args_(Ps, As, As1).
cpp_ref_args(_, As, As).
cpp_ref_args_of(Name, As, As1) :- ccl_declared(Name, fn(_, [_|Ps], _)), !, cpp_ref_args_(Ps, As, As1).   % a method's or constructor's: the object apart
cpp_ref_args_of(_, As, As).
cpp_ref_args_([], As, As).
cpp_ref_args_(_, [], []).
cpp_ref_args_([P|Ps], [A|As], [A1|Bs]) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, ( ( PT = rref(_, _) ; PT = ref(_, _) ), A = move(X) -> A1 = X ; A1 = A ), cpp_ref_args_(Ps, As, Bs).
cpp_ref_args_([_|Ps], [A|As], [A|Bs]) :- cpp_ref_args_(Ps, As, Bs).
%% a type that holds an owner: an own pointer, an own array, a struct with one inside
cpp_holds_owners(T) :- ck_own_type(T), !.
cpp_holds_owners(T) :- ccl_resolve_type(T, base(_, [struct(_, Ms)])), Ms \== none, member(member(MT, _, _), Ms), cpp_holds_owners(MT), !.
cpp_has_ctors(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), memberchk(ctor(_, _, _, _, _), Ms), !.
cpp_has_ctors(C) :- '$cpp_mt'(C, ctor, _, _), !.                                              % a constructor template
cpp_has_ctors(C) :- cpp_implicit_ctor_needed(C).
cpp_implicit_ctor_needed(C) :- cpp_class(C, cls(B, Data, Ms, _, Defaults, _)), \+ memberchk(ctor(_, _, _, _, _), Ms),
    ( Defaults \== [] ; B \== none, cpp_has_ctors(B) ; cpp_polymorphic(C) ; member(member(MT, _, _), Data), cpp_class_of_type(MT, MC), cpp_has_ctors(MC) ), !.
%% an implicit destructor: none of its own, a member with one to destroy
cpp_implicit_dtor_needed(C) :- cpp_class(C, cls(_, Data, Ms, _, _, _)), \+ memberchk(dtor(_, _, _), Ms), \+ ( nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ),
    member(member(MT, _, _), Data), cpp_class_of_type(MT, MC), cpp_dtor(MC, _), !.
cpp_implicit_dtor(L, C, [function(L, none, base([], [void]), Name, Params, false, Body1)]) :-
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], [dying], ThisT), Params = [param(ThisT, this)],
    ccl_declare(Name, fn(base([], [void]), Params, false)),
    cpp_dtor_body(L, C, block([]), Body0), cpp_method_body(C, Params, Body0, Body1).
cpp_dtor(C, Name) :- cpp_own_dtor(C, Name), !.
cpp_dtor(C, Name) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_dtor(B, Name).      % none of its own: the base's runs on it (the base at offset 0)
cpp_own_dtor(C, Name) :- cpp_class(C, cls(_, _, Ms, _, _, _)), ( memberchk(dtor(_, _, _), Ms) ; nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ; cpp_implicit_dtor_needed(C) ), !, atomic_list_concat([C, '.dtor.0'], Name), cpp_use_member(C, Name).
cpp_arity_fits(Ps, N) :- length(Ps, Max), Max >= N, cpp_required(Ps, Min), Min =< N.
cpp_required([], 0).
cpp_required([param(_, _, _)|_], 0) :- !.
cpp_required([_|Ps], N) :- cpp_required(Ps, N0), N is N0 + 1.

%% ---- names ----------------------------------------------------------------------
cpp_mangle(C, operator(Op), Ps, Name) :- !, cpp_op_word(Op, W), cpp_params_key(Ps, K), atomic_list_concat([C, '.op.', W, '.', K], Name).
cpp_mangle(C, M, Ps, Name) :- cpp_params_key(Ps, K), atomic_list_concat([C, '.', M, '.', K], Name).
%% the parameters' types, keyed (cpp_type_key): overloads by type get names of their own; none is `0'
cpp_params_key([], '0') :- !.
cpp_params_key(Ps, K) :- findall(TK, ( member(P, Ps), ( P = param(T, _) ; P = param(T, _, _) ), cpp_type_key(T, TK) ), Ks), atomic_list_concat(Ks, '.', K).
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
cpp_this_type(C, Quals, T) :- cpp_this_type(C, Quals, [], T).
%% a constructor's this is marked fresh, a destructor's dying: the check reads the marks (ck_this_marker/2)
cpp_this_type(C, Quals, Marks, ptr([], base(Q, [typedef(C)]))) :- ( memberchk(const, Quals) -> Q = [const|Marks] ; Q = Marks ).
cpp_refuse(L, What) :- throw(error(not_lowered(What), where(file, line(L)))).

%% ---- items ----------------------------------------------------------------------
cpp_items([], []).
cpp_items([I|Is], Out) :- cpp_item(I, Js), append(Js, Out1, Out), cpp_items(Is, Out1).
%% a class: the struct, the statics, then its members as functions
cpp_item(declare(L, base(Q, [class(_, C, _, _)])), Items) :- !,
    cpp_class(C, cls(Base, Data, Ms, Statics, Defaults, Slots)),
    ( Base == none -> Data1 = Data ; Data1 = [member(base([], [typedef(Base)]), '$base', none)|Data] ),
    cpp_static_decls(L, C, Statics, Fns0),
    ( cpp_is_lazy(C), Slots == [] -> Fns1 = [] ; cpp_in_class(C, cpp_member_fns(Ms, C, Base, Defaults, Fns1)) ),   % a lazy class's members come as they are used
    ( cpp_implicit_ctor_needed(C) -> cpp_implicit_ctor(L, C, Base, Defaults, Fns2) ; Fns2 = [] ),
    ( cpp_implicit_dtor_needed(C) -> cpp_implicit_dtor(L, C, Fns3) ; Fns3 = [] ),
    append(Fns0, Fns1, Fns01), append(Fns01, Fns2, Fns012), append(Fns012, Fns3, Fns),
    (   Slots == [] -> Items = [declare(L, base(Q, [struct(C, Data1)]))|Fns]
    ;   cpp_vt_struct(L, C, Slots, VtDecl), cpp_vtable(L, C, Slots, Table),
        Items = [VtDecl, declare(L, base(Q, [struct(C, Data1)]))|Fns1x], append(Fns, [Table], Fns1x) ).
%% the table's struct: a function pointer per slot, over the owner's pointer; the table: the class's implementations
cpp_vt_struct(L, C, Slots, declare(L, base([], [struct(VT, Ms)]))) :-
    cpp_vt_tag(C, VT), cpp_vt_owner(C, Owner), cpp_this_type(Owner, [], ThisT), cpp_this_type(Owner, [], [dying], DyingT),
    findall(member(ptr([], fn(Ret, [param(TT, this)|Ps], V)), M, none), ( member(slot(M, _, Ret, Ps, V), Slots), ( M == '$dtor' -> TT = DyingT ; TT = ThisT ) ), Ms).
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
    cpp_method_body(C, Ret, [param(ThisT, this)|Ps1], Body, Body1).
cpp_item(dtor_def(L, C, _, Body), [function(L, none, base([], [void]), Name, [param(ThisT, this)], false, Body1)]) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], [dying], ThisT), cpp_dtor_body(L, C, Body, Body0), cpp_method_body(C, [param(ThisT, this)], Body0, Body1).
%% a destructor's body, then the base's destructor over the base sub-object
cpp_dtor_body(L, C, block(Body), block(Body1)) :-
    cpp_class(C, cls(B, Data, _, _, _, _)),
    reverse(Data, RData),
    findall(expr(L, call(id(DName), [addr(arrow(this, N))])), ( member(member(MT, N, _), RData), cpp_class_of_type(MT, MC), cpp_dtor(MC, DName) ), MemberDtors),
    ( B \== none, cpp_dtor(B, BName) -> BaseDtor = [expr(L, call(id(BName), [addr(arrow(this, '$base'))]))] ; BaseDtor = [] ),
    append(Body, MemberDtors, Body0), append(Body0, BaseDtor, Body1).
cpp_item(function(L, Sto, Ret, operator(Op), Ps, V, Body), [function(L, Sto, Ret, Name, Ps1, V, Body1)]) :- !,
    cpp_free_operator(Op, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_method_body(none, Ret, Ps1, Body, Body1).
cpp_item(function(_, _, _, N, Ps, _, _), []) :- atom(N), cpp_auto_params(Ps, 0, _, TPs), TPs \== [], !.   % an abbreviated template: instantiated on use
cpp_item(function(L, Sto, Ret0, N, Ps, V, Body), [function(L, Sto, Ret, N, Ps1, V, Body1)]) :- !,
    cpp_plain_params(Ps, Ps1), ( Ret0 = base(_, [auto]) -> cpp_lambda_ret(Ps1, Body, Ret) ; cpp_type(Ret0, Ret) ),   % C++14: auto f(...): the first return's type
    cpp_method_body(none, Ret, Ps1, Body, Body1).
cpp_item(declaration(L, Sto, B, Vs), [declaration(L, Sto, B, Vs1)]) :- !, cpp_vars(none, Vs, Vs1).
cpp_item(typedef(L, Vs), [typedef(L, Vs1)]) :- !, cpp_vars(none, Vs, Vs1), ccl_note_typedefs(Vs1).   % the table learns the instance's name at once
cpp_item(template(_, _, _), []) :- !.
cpp_item(concept(_, _, _), []) :- !.                                                               % C++20: a constraint, checked where a template is instantiated
%% auto parameters become invented type parameters, in order: `$A1', `$A2' ...
cpp_auto_params([], _, [], []).
cpp_auto_params([P|Ps], K, [P1|Ps1], TPs) :-
    ( P = param(T0, N) -> D = none ; P = param(T0, N, D) ),
    (   cpp_auto_in(T0, K, T1, K1)
    ->  atom_concat('$A', K1, A), ( D == none -> P1 = param(T1, N) ; P1 = param(T1, N, D) ), TPs = [tparam(type, A, none)|TPs1]
    ;   P1 = P, K1 = K, TPs = TPs1 ),
    cpp_auto_params(Ps, K1, Ps1, TPs1).
cpp_auto_in(base(Q, [auto]), K, base(Q, [typedef(A)]), K1) :- !, K1 is K + 1, atom_concat('$A', K1, A).
cpp_auto_in(ptr(Q, T0), K, ptr(Q, T), K1) :- !, cpp_auto_in(T0, K, T, K1).
cpp_auto_in(ref(Q, T0), K, ref(Q, T), K1) :- !, cpp_auto_in(T0, K, T, K1).
cpp_auto_in(rref(Q, T0), K, rref(Q, T), K1) :- !, cpp_auto_in(T0, K, T, K1).
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
cpp_member_fns([method(L, Qs, Ret, M, Ps, V, Body)|Ms], C, B, Ds, [F|Fs]) :- memberchk(explicit_this(N, T0), Qs), !,     % C++23: the object parameter as declared; the body has no implicit this
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_self_param(L, C, N, T0, Self), Params = [Self|Ps1],
    ( memberchk(closure, Qs) -> Ctx = self(C, N) ; Ctx = none ),                                                           % a lambda's captures are reached through it
    (   Body == none -> F = declaration(L, none, Ret, [var(Name, fn(Ret, Params, V), none)])
    ;   cpp_method_body(Ctx, Ret, Params, Body, Body1), F = function(L, none, Ret, Name, Params, V, Body1) ),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([method(L, Qs, Ret0, M, Ps, V, Body)|Ms], C, B, Ds, [F|Fs]) :- !,
    cpp_mangle(C, M, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, Qs, ThisT), Params = [param(ThisT, this)|Ps1],
    cpp_method_ret(C, Ret0, Params, Body, Ret),
    (   Body == none -> F = declaration(L, none, Ret, [var(Name, fn(Ret, Params, V), none)])
    ;   cpp_method_body(C, Ret, Params, Body, Body1), F = function(L, none, Ret, Name, Params, V, Body1) ),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([ctor(L, _, Ps, Inits, Body)|Ms], C, B, Ds, [F|Fs]) :- !,
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], [fresh], ThisT), Params = [param(ThisT, this)|Ps1],
    cpp_ctor_body(L, C, B, Ds, Inits, Body, Body0), cpp_method_body(C, Params, Body0, Body1),
    F = function(L, none, base([], [void]), Name, Params, false, Body1),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([dtor(L, _, Body)|Ms], C, B, Ds, Fs) :- !,
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], [dying], ThisT), Params = [param(ThisT, this)],
    (   Body == none -> Fs = [declaration(L, none, base([], [void]), [var(Name, fn(base([], [void]), Params, false), none)])|Fs1]
    ;   cpp_dtor_body(L, C, Body, Body0), cpp_method_body(C, Params, Body0, Body1), Fs = [function(L, none, base([], [void]), Name, Params, false, Body1)|Fs1] ),
    cpp_member_fns(Ms, C, B, Ds, Fs1).
cpp_member_fns([_|Ms], C, B, Ds, Fs) :- cpp_member_fns(Ms, C, B, Ds, Fs).
%% a constructor's body: the base's constructor, then every member from its
%% initializer, else its default, in the members' order; then the body
cpp_ctor_body(L, C, B, Defaults, Inits0, block(Body), block(Pre)) :-
    cpp_norm_inits(Inits0, Inits),
    (   B \== none
    ->  ( memberchk(init(B, BArgs), Inits) -> true ; BArgs = [] ),
        ( cpp_ctor(B, BArgs, BName) -> cpp_fill_defaults(BName, BArgs, BArgs1), Pre = [expr(L, call(id(BName), [addr(arrow(this, '$base'))|BArgs1]))|Pre1]
        ; BArgs == [] -> Pre = Pre1
        ; cpp_refuse(L, base_constructor(B)) )
    ;   Pre = Pre1 ),
    cpp_vptr_store(L, C, Store), append(Store, Pre2, Pre1),
    cpp_class(C, cls(_, Data, _, _, _, _)),
    cpp_member_inits(Data, Inits, Defaults, L, Pre2, Body).
%% an initializer naming a base by its template-id names the instance
cpp_norm_inits([], []).
cpp_norm_inits([init(N0, As)|Is], [init(N, As)|Js]) :- ( atom(N0) -> N = N0 ; cpp_base_name(N0, N) ), cpp_norm_inits(Is, Js).
cpp_norm_inits([I|Is], [I|Js]) :- cpp_norm_inits(Is, Js).
cpp_member_inits([], _, _, _, Body, Body).
cpp_member_inits([member(_, '$vptr', _)|Ds], Inits, Defaults, L, Pre, Body) :- !, cpp_member_inits(Ds, Inits, Defaults, L, Pre, Body).
cpp_member_inits([member(MT, N, _)|Ds], Inits, Defaults, L, Pre, Body) :- cpp_class_of_type(MT, MC), cpp_has_ctors(MC), !,   % a member of a class with constructors: constructed
    ( memberchk(init(N, Args), Inits) -> true ; memberchk(N-E, Defaults) -> Args = [E] ; Args = [] ),
    length(Args, NA), ( cpp_ctor(MC, Args, CName) -> true ; cpp_refuse(L, member_not_constructed(N, MC, NA)) ),
    cpp_fill_defaults(CName, Args, Args1), Pre = [expr(L, call(id(CName), [addr(arrow(this, N))|Args1]))|Pre1],
    cpp_member_inits(Ds, Inits, Defaults, L, Pre1, Body).
cpp_member_inits([member(_, N, _)|Ds], Inits, Defaults, L, Pre, Body) :-
    (   memberchk(init(N, [E]), Inits) -> Pre = [expr(L, assign('=', arrow(this, N), E))|Pre1]
    ;   memberchk(N-E, Defaults) -> Pre = [expr(L, assign('=', arrow(this, N), E))|Pre1]
    ;   Pre = Pre1 ),
    cpp_member_inits(Ds, Inits, Defaults, L, Pre1, Body).
%% a class with no constructor of its own but defaults to set, or a base to construct: C.C.0
cpp_implicit_ctor(L, C, B, Defaults, [function(L, none, base([], [void]), Name, Params, false, Body1)]) :-
    cpp_mangle(C, C, [], Name), cpp_this_type(C, [], [fresh], ThisT), Params = [param(ThisT, this)],
    ccl_declare(Name, fn(base([], [void]), Params, false)),
    cpp_ctor_body(L, C, B, Defaults, [], block([]), Body0), cpp_method_body(C, Params, Body0, Body1).
%% a body under its parameters, the class's members in reach
cpp_method_body(Ctx, Params, Body, Body1) :- cpp_method_body(Ctx, none, Params, Body, Body1).
cpp_method_body(Ctx, Ret, Params, Body, Body1) :-
    ( catch(nb_getval('$cpp_ret', R0), _, fail) -> true ; R0 = none ), nb_setval('$cpp_ret', Ret),
    ccl_scope_push, ccl_declare_params(Params), cpp_stmt(Ctx, Body, Body0), ccl_scope_pop,
    nb_setval('$cpp_ret', R0),
    cpp_param_defers(Params, Defers), ( Defers == [], ! ; Body0 = block(Ss), Body1 = block(Ss1), append(Defers, Ss, Ss1) ), ( Defers == [] -> Body1 = Body0 ; true ).
%% a by-value parameter of a class with a destructor is the callee's to destroy, at every exit
cpp_param_defers([], []).
cpp_param_defers([param(T, N)|Ps], Ds) :- atom(N), N \== this, cpp_class_of_type(T, C), cpp_dtor(C, DName), !,
    Ds = [defer(0, [], block([expr(0, call(id(DName), [addr(id(N))]))]))|Ds1], cpp_param_defers(Ps, Ds1).
cpp_param_defers([_|Ps], Ds) :- cpp_param_defers(Ps, Ds).

%% ---- statements, the scopes kept -------------------------------------------------
cpp_stmt(Ctx, block(Is), block(Js)) :- !, ccl_scope_push, cpp_stmts(Ctx, Is, Js), ccl_scope_pop.
cpp_stmt(Ctx, '$splice'(Is), '$splice'(Js)) :- !, cpp_stmts(Ctx, Is, Js).
cpp_stmt(Ctx, declaration(L, Sto, B, Vs), S) :- !, cpp_decl_stmt(Ctx, L, Sto, B, Vs, S).
cpp_stmt(Ctx, expr(L, E), expr(L, E1)) :- !, cpp_expr(Ctx, E, E1).
cpp_stmt(_, using(_, enum(_)), empty) :- !.                                                    % C++20: the enumerators are in scope already (a namespace flattens)
cpp_stmt(Ctx, defer(L, Vs, Body), defer(L, Vs, Body1)) :- !, cpp_stmt(Ctx, Body, Body1).
cpp_stmt(Ctx, if_constexpr(L, C, T, E), Out) :- !,                                          % C++17: decided here when the condition is a constant, else a plain if
    cpp_expr(Ctx, C, C1),
    (   cpp_const_bool(C1, V) -> ( V == true -> cpp_stmt(Ctx, T, Out) ; E == none -> Out = empty ; cpp_stmt(Ctx, E, Out) )
    ;   cpp_stmt(Ctx, T, T1), ( E == none -> E1 = none ; cpp_stmt(Ctx, E, E1) ), Out = if(L, C1, T1, E1) ).
cpp_stmt(Ctx, if_consteval(_, Neg, T, E), Out) :- !,                                          % C++23: nothing runs at compile time here, so the run-time branch is kept
    ( Neg == yes -> Keep = T ; Keep = E ), ( Keep == none -> Out = empty ; cpp_stmt(Ctx, Keep, Out) ).
cpp_stmt(_, co_return(L, _), _) :- !, cpp_refuse(L, coroutine).                               % C++20 coroutines: no runtime to suspend into
cpp_stmt(Ctx, if(L, C, T, E), if(L, C1, T1, E1)) :- !, cpp_expr(Ctx, C, C1), cpp_stmt(Ctx, T, T1), ( E == none -> E1 = none ; cpp_stmt(Ctx, E, E1) ).
cpp_stmt(Ctx, while(L, C, S), while(L, C1, S1)) :- !, cpp_expr(Ctx, C, C1), cpp_stmt(Ctx, S, S1).
cpp_stmt(Ctx, do(L, S, C), do(L, S1, C1)) :- !, cpp_stmt(Ctx, S, S1), cpp_expr(Ctx, C, C1).
cpp_stmt(Ctx, for(L, Init, C, Step, S), for(L, Init1, C1, Step1, S1)) :- !,
    ccl_scope_push,
    ( Init = decl(B, Vs) -> cpp_vars(Ctx, Vs, Vs1), ccl_declare_vars(Vs1), Init1 = decl(B, Vs1) ; cpp_opt_expr(Ctx, Init, Init1) ),
    cpp_opt_expr(Ctx, C, C1), cpp_opt_expr(Ctx, Step, Step1), cpp_stmt(Ctx, S, S1), ccl_scope_pop.
cpp_stmt(Ctx, for_each(L, var(N, T0, I), R, S), Out) :- !,
    cpp_type(T0, T), cpp_expr(Ctx, R, R1),
    (   cpp_class_of_type_of(R1, C), cpp_method(C, size, [], _, _), cpp_method(C, operator('[]'), [int(0)], IxName, _)   % a range-for over an object: by size() and []
    ->  ( cpp_lvalue(R1) -> true ; cpp_refuse(L, range_for_over_a_value(C)) ),
        ccl_declared(IxName, fn(ERet, _, _)), ccl_unref(ERet, ET), cpp_range_type(T, ET, T1), ccl_gensym('$i', Ix),
        For = for(L, decl(base([], [int]), [var(Ix, base([], [int]), int(0))]), bin('<', id(Ix), call(member(R1, size), [])), postinc(id(Ix)),
                  block([declaration(L, none, ET, [var(N, T1, index(R1, id(Ix)))]), S])),
        cpp_stmt(Ctx, For, Out)
    ;   Out = for_each(L, var(N, T, I), R1, S1), ccl_scope_push, ccl_declare(N, T), cpp_stmt(Ctx, S, S1), ccl_scope_pop ).
cpp_range_type(base(_, [auto]), ET, ET) :- !.
cpp_range_type(ref(Q, base(_, [auto])), ET, ref(Q, ET)) :- !.
cpp_range_type(rref(Q, base(_, [auto])), ET, ref(Q, ET)) :- !.
cpp_range_type(T, _, T).
cpp_lvalue(id(_)).
cpp_lvalue(member(_, _)).
cpp_lvalue(arrow(_, _)).
cpp_lvalue(deref(_)).
cpp_lvalue(index(_, _)).
cpp_stmt(Ctx, return(L, E), return(L, E2)) :- !, cpp_expr(Ctx, E, E1),
    (   nb_getval('$cpp_ret', Ret), Ret \== none, cpp_class_of_type(Ret, C), cpp_dtor(C, _), cpp_lvalue(E1)   % by value, of a class with a destructor, an object that is destroyed here
    ->  (   ( cpp_copy_ctor(C, rref), Arg = move(E1) ; cpp_copy_ctor(C, ref), Arg = E1 )                     % C++'s implicit move out of a local, else its copy
        ->  T = base([], [typedef(C)]), cpp_ctor(C, [Arg], CName), ccl_gensym('$ret', Tmp),
            E2 = stmt_expr(block([declaration(L, none, T, [var(Tmp, T, none)]), expr(L, call(id(CName), [addr(id(Tmp)), E1])), expr(L, id(Tmp))]))
        ;   cpp_refuse(L, return_of_a_class_with_destructor(C)) )
    ;   E2 = E1 ).
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
cpp_decl_pieces(Ctx, L, Sto, B, [var(N, base(Q, [auto]), I0)|Vs], Pieces) :- !,           % auto the reader could not infer: a lambda, a call of a method or a template
    cpp_expr(Ctx, I0, I), ( ccl_type_of(I, T0), T0 \== unknown -> cpp_decayed(T0, T1), T1 = base(_, S), T = base(Q, S) ; cpp_refuse(L, auto(N)) ),
    cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T, I)|Vs], Pieces).
cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T0, init(Items))|Vs], Pieces) :-
    cpp_type(T0, T), Sto \== static, Sto \== extern, cpp_class_of_type(T, C), cpp_implicit_ctor_needed(C), !,   % an aggregate of members that construct: each from its item
    ccl_declare(N, T), cpp_class(C, cls(_, Data, _, _, _, _)),
    findall(E, member(item(_, E), Items), Es), cpp_exprs(Ctx, Es, Es1), cpp_aggregate_inits(Data, Es1, id(N), L, Inits),
    Pieces = [declaration(L, Sto, B, [var(N, T, none)])|P1], append(Inits, P2, P1),
    ( cpp_dtor(C, DName) -> P2 = [defer(L, [], block([expr(L, call(id(DName), [addr(id(N))]))]))|P3] ; P2 = P3 ),
    cpp_decl_pieces(Ctx, L, Sto, B, Vs, P3).
cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T0, I)|Vs], Pieces) :-
    cpp_type(T0, T),
    (   Sto \== static, Sto \== extern, cpp_class_of_type(T, C), cpp_has_ctors(C), cpp_ctor_args(Ctx, I, C, Args)
    ->  length(Args, NA),
        ( cpp_ctor(C, Args, CName) -> true ; cpp_refuse(L, no_constructor(C, NA)) ),
        cpp_fill_defaults(CName, Args, Args0), cpp_ref_args_of(CName, Args0, Args1),
        ccl_declare(N, T),
        Pieces = [declaration(L, Sto, B, [var(N, T, none)]), expr(L, call(id(CName), [addr(id(N))|Args1]))|P1]
    ;   cpp_expr(Ctx, I, I1), ccl_declare(N, T),
        ( cpp_class_of_type(T, C0), cpp_dtor(C0, _), cpp_lvalue(I1) -> cpp_refuse(L, copy_of_a_class_with_destructor(C0)) ; true ),   % two owners of one buffer
        Pieces = [declaration(L, Sto, B, [var(N, T, I1)])|P1] ),
    ( Sto \== static, Sto \== extern, cpp_class_of_type(T, C2), cpp_dtor(C2, DName) -> P1 = [defer(L, [], block([expr(L, call(id(DName), [addr(id(N))]))]))|P2] ; P1 = P2 ),
    cpp_decl_pieces(Ctx, L, Sto, B, Vs, P2).
cpp_aggregate_inits([], _, _, _, []).
cpp_aggregate_inits(_, [], _, _, []) :- !.
cpp_aggregate_inits([member(_, '$vptr', _)|Ds], Es, Obj, L, Inits) :- !, cpp_aggregate_inits(Ds, Es, Obj, L, Inits).
cpp_aggregate_inits([member(MT, M, _)|Ds], [E|Es], Obj, L, [S|Inits]) :-
    (   cpp_class_of_type(MT, MC), cpp_has_ctors(MC)
    ->  ( cpp_ctor(MC, [E], CName) -> true ; cpp_refuse(L, member_not_constructed(M, MC, 1)) ), cpp_fill_defaults(CName, [E], Args), S = expr(L, call(id(CName), [addr(member(Obj, M))|Args]))
    ;   S = expr(L, assign('=', member(Obj, M), E)) ),
    cpp_aggregate_inits(Ds, Es, Obj, L, Inits).
cpp_ctor_args(_, none, _, []) :- !.
cpp_ctor_args(Ctx, ctor(As), _, As1) :- !, cpp_exprs(Ctx, As, As1).
cpp_ctor_args(Ctx, init(Items), _, As1) :- !, findall(E, member(item(_, E), Items), As), cpp_exprs(Ctx, As, As1).
cpp_ctor_args(Ctx, E, C, [E2]) :- cpp_expr(Ctx, E, E1),
    (   \+ cpp_class_of_type_of(E1, C) -> E2 = E1
    ;   cpp_lvalue(E1), cpp_copy_ctor(C, ref) -> E2 = E1                                          % a copy, through the copy constructor
    ;   E1 = move(X), cpp_lvalue(X), cpp_copy_ctor(C, rref) -> E2 = X                             % a move, through the move constructor (the argument's address)
    ;   fail ).                                                                                    % a prvalue moves bitwise (C++17 elides that copy); an lvalue with no copy constructor is refused below
%% a constructor from the class itself: Kind ref for `C(const C &)', rref for `C(C &&)'
cpp_copy_ctor(C, Kind) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(ctor(_, _, [P], _, _), Ms), ( P = param(RT, _) ; P = param(RT, _, _) ), RT =.. [Kind, _, base(_, [typedef(C)])], !.
%% a by-value parameter of a class with a destructor takes a copy: the copy constructor's, in a temporary the callee owns
cpp_copies(call(id(Name), Args), call(id(Name), Args1)) :- ccl_declared(Name, fn(_, Ps, _)), !, cpp_copies_(Ps, Args, Args1).
cpp_copies(E, E).
cpp_copies_([], As, As).
cpp_copies_(_, [], []).
cpp_copies_([P|Ps], [A|As], [A1|Bs]) :-
    ( P = param(PT, _) ; P = param(PT, _, _) ), !,
    (   cpp_class_of_type(PT, C), cpp_dtor(C, _), cpp_lvalue(A)
    ->  ( cpp_copy_ctor(C, ref) -> cpp_copy_temp(C, A, A1) ; cpp_refuse(0, class_with_destructor_by_value(C)) )
    ;   A1 = A ),
    cpp_copies_(Ps, As, Bs).
cpp_copies_([_|Ps], [A|As], [A|Bs]) :- cpp_copies_(Ps, As, Bs).
cpp_copy_temp(C, A, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, none)]), expr(0, call(id(CName), [addr(id(Tmp)), A])), expr(0, id(Tmp))]))) :-
    T = base([], [typedef(C)]), cpp_ctor(C, [A], CName), ccl_gensym('$copy', Tmp).

%% ---- expressions, bottom up ----------------------------------------------------------
cpp_exprs(_, [], []).
cpp_exprs(Ctx, [E|Es], [E1|Fs]) :- cpp_expr(Ctx, E, E1), cpp_exprs(Ctx, Es, Fs).
cpp_expr(_, this, id(this)) :- !.
cpp_expr(_, E, E) :- \+ compound(E), !.
cpp_expr(Ctx, id(N), E) :- !,
    (   cpp_local(N) -> E = id(N)
    ;   Ctx = self(C, SN), cpp_data_member(C, N, []) -> E = member(id(SN), N)                   % C++23: a capture, through the closure's explicit object parameter
    ;   Ctx \== none, cpp_data_member(Ctx, N, Hops) -> cpp_access(id(this), N, Hops, E)
    ;   Ctx \== none, cpp_static_member(Ctx, N, Name) -> E = id(Name)
    ;   E = id(N) ).
cpp_expr(_, scoped(Path, N), E) :- cpp_scope_class(Path, C), !,
    (   cpp_static_const(C, N, V) -> E = V                                                        % C::value, a static const with a constant: the constant
    ;   cpp_static_member(C, N, Name) -> E = id(Name)
    ;   atomic_list_concat([C, '.', N], Name), E = id(Name) ).
cpp_expr(_, tmpl(N, Args0), E) :- cpp_template(N, _, declaration(_, _, _, _)), !,               % a variable template: its instance's value
    cpp_targ_values(Args0, Args), cpp_instantiate_variable(N, Args, E).
cpp_expr(Ctx, call(F, As), E) :- !, cpp_exprs(Ctx, As, As1), cpp_call(Ctx, F, As1, E0), cpp_copies(E0, E).
%% an argument of a class with a destructor goes by reference or by pointer, never by value
cpp_no_copies(call(id(Name), Args)) :- ccl_declared(Name, fn(_, Ps, _)), !, cpp_no_copies_(Ps, Args).
cpp_no_copies(_).
cpp_no_copies_([], _).
cpp_no_copies_(_, []).
cpp_no_copies_([P|Ps], [A|As]) :-
    ( P = param(PT, _) ; P = param(PT, _, _) ), !,
    ( cpp_class_of_type(PT, C), cpp_dtor(C, _), cpp_lvalue(A) -> cpp_refuse(0, class_with_destructor_by_value(C)) ; true ),
    cpp_no_copies_(Ps, As).
cpp_no_copies_([_|Ps], [_|As]) :- cpp_no_copies_(Ps, As).
cpp_expr(Ctx, member(X, N), E) :- !, cpp_expr(Ctx, X, X1), ( cpp_class_of_type_of(X1, C), cpp_data_member(C, N, Hops), Hops \== [] -> cpp_hops(X1, Hops, B), E = member(B, N) ; E = member(X1, N) ).
cpp_expr(Ctx, arrow(X, N), E) :- !, cpp_expr(Ctx, X, X1), ( cpp_pointee_class_of(X1, C), cpp_data_member(C, N, Hops), Hops \== [] -> cpp_access(X1, N, Hops, E) ; E = arrow(X1, N) ).
cpp_expr(Ctx, bin('<=>', A, B), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1),         % C++20: the three-way comparison, an int for scalars (-1, 0, 1); a class's operator<=> when it has one
    (   cpp_class_of_type_of(A1, C) -> ( cpp_method(C, operator('<=>'), [B1], Name, Hops) -> cpp_hops(A1, Hops, Base), cpp_object_arg(Name, addr(Base), Obj), E = call(id(Name), [Obj, B1]) ; cpp_refuse(0, three_way_comparison_of_a_class(C)) )
    ;   E = bin('-', bin('>', A1, B1), bin('<', A1, B1)) ).
cpp_expr(_, co_await(_), _) :- !, cpp_refuse(0, coroutine).
cpp_expr(_, co_yield(_), _) :- !, cpp_refuse(0, coroutine).
cpp_expr(Ctx, bin(Op, A, B), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_operator(Op, A1, [B1], bin(Op, A1, B1), E).
cpp_expr(Ctx, assign(Op, A, B), E) :- Op \== '=', !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_operator(Op, A1, [B1], assign(Op, A1, B1), E).
cpp_expr(Ctx, assign('=', A, B), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1),
    (   cpp_class_of_type_of(A1, C), cpp_method(C, operator('='), [B1], Name, Hops)              % the class's operator=, copy or move by the value category
    ->  cpp_hops(A1, Hops, Base), cpp_object_arg(Name, addr(Base), Obj), cpp_ref_args_of(Name, [B1], [B2]), E = call(id(Name), [Obj, B2])
    ;   cpp_class_of_type_of(A1, C), cpp_dtor(C, _), \+ B1 = move(_) -> cpp_refuse(0, assignment_to_a_class_with_destructor(C))   % the old value would never be destroyed, the new freed twice; a move into a fresh slot is the holder's business
    ;   E = assign('=', A1, B1) ).
cpp_expr(Ctx, index(A, args(Is)), E) :- !, cpp_expr(Ctx, A, A1), cpp_exprs(Ctx, Is, Is1),        % C++23: a[i, j] is the class's operator[](i, j)
    ( cpp_operator('[]', A1, Is1, none, E), E \== none -> true ; length(Is1, N), cpp_refuse(0, subscript_arity(N)) ).
cpp_expr(Ctx, index(A, I), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, I, I1), cpp_operator('[]', A1, [I1], index(A1, I1), E).
cpp_expr(Ctx, decay_copy(X), E) :- !, cpp_expr(Ctx, X, X1),                                       % C++23: auto(x), auto{x}: a copy of the decayed value
    (   ccl_type_of(X1, T0), T0 \== unknown
    ->  cpp_decayed(T0, T), ( cpp_class_of_type(T, C) -> ( cpp_dtor(C, _), cpp_lvalue(X1) -> cpp_refuse(0, copy_of_a_class_with_destructor(C)) ; E = X1 ) ; E = cast(T, X1) )
    ;   E = X1 ).
cpp_expr(Ctx, new(T0, As), E) :- !, cpp_type(T0, T), cpp_exprs(Ctx, As, As1), cpp_new(T, As1, E).
cpp_expr(Ctx, new_array(T0, N), new_array(T, N1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, N, N1).
cpp_expr(Ctx, cast(T0, X), cast(T, X1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, X, X1).
cpp_expr(_, sizeof_type(T0), sizeof_type(T)) :- !, cpp_type(T0, T).
cpp_expr(Ctx, compound_lit(T0, I), compound_lit(T, I1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, I, I1).
cpp_expr(Ctx, delete(X), E) :- !, cpp_expr(Ctx, X, X1), cpp_delete(X1, E).
cpp_expr(Ctx, ccast(functional, base(Q, [typedef(C)]), X), E) :- cpp_class(C, _), !, cpp_expr(Ctx, X, X1), cpp_temporary(base(Q, [typedef(C)]), C, [X1], E).
cpp_expr(Ctx, ccast(K, T0, X), ccast(K, T, X1)) :- !, cpp_type(T0, T), cpp_expr(Ctx, X, X1).
cpp_expr(Ctx, move(X), E) :- !, cpp_expr(Ctx, X, X1), ( ccl_type_of(X1, T), T \== unknown, cpp_holds_owners(T) -> E = move(X1) ; E = X1 ).   % move of an int is the int (a template's T)
cpp_expr(Ctx, stmt_expr(block(Is)), stmt_expr(block(Js))) :- !, ccl_scope_push, cpp_stmts(Ctx, Is, Js), ccl_scope_pop.
cpp_expr(Ctx, lambda(Caps, Ps, Ret, Body), E) :- !, cpp_lambda(Ctx, Caps, Ps, Ret, Body, E).
cpp_expr(_, str(S), str(S)) :- !.
cpp_expr(Ctx, E, E1) :- E =.. [F|As], cpp_exprs(Ctx, As, Bs), E1 =.. [F|Bs].
cpp_local(N) :- ccl_locals(Fs), member(F, Fs), memberchk(N-_, F), !.
%% the way to a member: o.$base...n by value, p->n or p->$base...n through a pointer
cpp_hops(X, [], X).
cpp_hops(X, [H|Hs], B) :- cpp_hops(member(X, H), Hs, B).
cpp_access(P, N, [], arrow(P, N)) :- !.
cpp_access(P, N, Hops, member(B, N)) :- cpp_hops(deref(P), Hops, B).
%% calls: a method through its object, a method of this, a constructor as a temporary, a free function with its defaults
cpp_call(Ctx, member(X0, dtor(_)), [], E) :- !, cpp_expr(Ctx, X0, X), ( cpp_class_of_type_of(X, C), cpp_dtor(C, DName) -> E = call(id(DName), [addr(X)]) ; E = int(0) ).   % x.~T(): the destructor called, nothing for a trivial one
cpp_call(Ctx, arrow(X0, dtor(_)), [], E) :- !, cpp_expr(Ctx, X0, X), ( cpp_pointee_class_of(X, C), cpp_dtor(C, DName) -> E = call(id(DName), [X]) ; E = int(0) ).
cpp_call(Ctx, member(X0, tmpl(M, TArgs0)), As, E) :- !,                                       % o.f<T>(args): a member template, its arguments given
    cpp_expr(Ctx, X0, X), cpp_targ_values(TArgs0, TArgs),
    (   cpp_class_of_type_of(X, C), cpp_member_template_call(C, M, TArgs, As, Name) -> cpp_object_arg(Name, addr(X), Obj), E = call(id(Name), [Obj|As])
    ;   cpp_refuse(0, no_member_template(M)) ).
cpp_call(Ctx, scoped(Path, M), As, E) :- cpp_scope_class(Path, C), cpp_method(C, M, As, Name, _), !,   % X<T>::f(args), C::f(args): a static method (its this null)
    cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, nullptr, Obj), E = call(id(Name), [Obj|As1]).
cpp_call(_, id(N), Args, V) :- ccl_builtin_trait(N), !, cpp_trait(N, Args, V).                 % __is_same(T, U): the compiler's trait, decided here
cpp_call(Ctx, member(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_class_of_type_of(X, C), length(As, N), cpp_method(C, M, As, Name, Hops)
    ->  cpp_fill_defaults(Name, As, As1),
        (   cpp_slot(C, M, N, Slot), \+ cpp_static_object(X) -> cpp_dispatch(addr(X), C, Slot, As1, E)   % a reference, *p: the dynamic type's
        ;   cpp_hops(X, Hops, B), cpp_object_arg(Name, addr(B), Obj), cpp_ref_args_of(Name, As1, As2), E = call(id(Name), [Obj|As2]) )
    ;   E = call(member(X, M), As) ).
cpp_call(Ctx, arrow(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_pointee_class_of(X, C), length(As, N), cpp_method(C, M, As, Name, Hops)
    ->  cpp_fill_defaults(Name, As, As1),
        (   cpp_slot(C, M, N, Slot) -> cpp_dispatch(X, C, Slot, As1, E)
        ;   ( Hops == [] -> P = X ; cpp_hops(deref(X), Hops, B), P = addr(B) ), cpp_object_arg(Name, P, Obj), cpp_ref_args_of(Name, As1, As2), E = call(id(Name), [Obj|As2]) )
    ;   E = call(arrow(X, M), As) ).
cpp_call(Ctx, id(M), As, E) :- Ctx \== none, \+ cpp_local(M), length(As, N), cpp_method(Ctx, M, As, Name, Hops), !,
    cpp_fill_defaults(Name, As, As1),
    (   cpp_slot(Ctx, M, N, Slot) -> cpp_dispatch(id(this), Ctx, Slot, As1, E)
    ;   ( Hops == [] -> P = id(this) ; cpp_hops(deref(id(this)), Hops, B), P = addr(B) ), cpp_object_arg(Name, P, Obj), E = call(id(Name), [Obj|As1]) ).
%% p->$vptr->slot(p, args), the pointer to the table found through the base sub-objects
cpp_dispatch(P, C, Slot, As, call(arrow(Vptr, Slot), [P|As])) :- cpp_data_member(C, '$vptr', Hops), cpp_access(P, '$vptr', Hops, Vptr).
%% a value whose dynamic type is its static one: a named object, or a member of one; not a reference
cpp_static_object(id(N)) :- ccl_declared(N, T), \+ T = ref(_, _), \+ T = rref(_, _).
cpp_static_object(member(X, _)) :- cpp_static_object(X).
cpp_call(_, scoped([std], move), [X], move(X)) :- !.                                           % std::move is Cicili's move: the fields go, the source is emptied
cpp_call(_, id(F), As, call(id(Name), [Obj|As1])) :- cpp_local(F), cpp_class_of_type_of(id(F), C), cpp_method(C, operator('()'), As, Name, _), !, cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, addr(id(F)), Obj).   % a lambda, or any object with operator()
cpp_call(_, tmpl(F, TArgs), As, call(id(Name), As)) :- cpp_template(F, _, function(_, _, _, _, _, _, _)), !, cpp_types(TArgs, TArgs1), cpp_instantiate_function(F, TArgs1, As, Name).
cpp_call(_, id(F), As, call(id(Name), As)) :- \+ cpp_local(F), cpp_template(F, _, function(_, _, _, _, _, _, _)), !, cpp_instantiate_function(F, [], As, Name).
cpp_call(_, id(C), As, E) :- cpp_class(C, _), !, cpp_temporary(base([], [typedef(C)]), C, As, E).
cpp_call(_, id(T), As, compound_lit(base([], [typedef(T)]), init(Items))) :- ccl_tag(T, _), !, findall(item([], A), member(A, As), Items).   % P{3, 4} of a plain struct: C's compound literal
cpp_call(_, scoped(_, C), As, E) :- atom(C), cpp_class(C, _), !, cpp_temporary(base([], [typedef(C)]), C, As, E).   % std::string("x"): a temporary of the class
cpp_call(_, id(F), As, call(id(F), As2)) :- !, cpp_fill_defaults(F, As, As1), cpp_ref_args(F, As1, As2).
cpp_call(Ctx, F, As, call(F1, As)) :- cpp_expr(Ctx, F, F1).
%% a temporary of the class: constructed in a statement expression, its value the last expression
cpp_temporary(T, C, As, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, none)]), expr(0, call(id(Name), [addr(id(Tmp))|As1])), expr(0, id(Tmp))]))) :-
    cpp_not_abstract(C), length(As, N), ( cpp_ctor(C, As, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As0), cpp_ref_args_of(Name, As0, As1), ccl_gensym('$tmp', Tmp).
%% an operator on a class-typed left operand: the class's member operator, else a free one declared, else the form as it is
cpp_operator(Op, A, Args, Plain, E) :-
    (   cpp_class_of_type_of(A, C), cpp_method(C, operator(Op), Args, Name, Hops)
    ->  cpp_hops(A, Hops, B), cpp_fill_defaults(Name, Args, Args0), cpp_ref_args_of(Name, Args0, Args1), cpp_object_arg(Name, addr(B), Obj), E = call(id(Name), [Obj|Args1])
    ;   cpp_class_of_type_of(A, _), length(Args, N0), N1 is N0 + 1, length(Ps, N1), cpp_free_operator(Op, Ps, Name), nb_getval('$cpp_free_ops', Os), memberchk(Name, Os)
    ->  E = call(id(Name), [A|Args])
    ;   E = Plain ).
%% new C(args): malloc's block constructed; delete p: destroyed, then freed
cpp_new(T, As, stmt_expr(block([declaration(0, none, T, [var(P, PT, new(T, []))]), expr(0, call(id(Name), [id(P)|As1])), expr(0, id(P))]))) :-
    cpp_class_of_type(T, C), cpp_has_ctors(C), !,
    length(As, N), ( cpp_ctor(C, As, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As1), ccl_gensym('$new', P), PT = ptr([], T).
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
cpp_template_name(declare(_, base(_, [class(_, N, _, _)])), N) :- atom(N).
cpp_template_name(declare(_, base(_, [struct(N, _)])), N) :- atom(N).
cpp_template_name(declare(_, base(_, [class(N, none)])), N) :- atom(N).                     % a forward declaration (its defaults count)
cpp_template_name(declare(_, base(_, [union(N, _)])), N) :- atom(N).
cpp_template_name(declaration(_, _, _, [var(N, _, _)]), N) :- atom(N).      % a variable template
cpp_template_name(typedef(_, [var(N, _, _)]), N) :- atom(N).                 % an alias template
cpp_template(N, TPs, Item) :- ( '$cpp_tmpl'(N, _, _) -> true ; cpp_hdr_load(N) ), '$cpp_tmpl'(N, TPs, Item).
%% a class template's primary: the definition when one was read after a forward declaration
cpp_class_template(N, TPs, Item) :- ( '$cpp_tmpl'(N, _, _) -> true ; cpp_hdr_load(N) ),
    (   '$cpp_tmpl'(N, TPs0, Item), cpp_template_class_def(Item) -> true            % a class's definition first (std::pmr::vector, an alias, shares the flattened name)
    ;   '$cpp_tmpl'(N, TPs0, Item), cpp_template_defined(Item) -> true
    ;   '$cpp_tmpl'(N, TPs0, Item) -> true ),
    findall(N-tmpl(TPs2, It2), '$cpp_tmpl'(N, TPs2, It2), Ts), cpp_merge_defaults(N, TPs0, Ts, TPs).
%% a default the definition lacks comes from another declaration of the name (C++ merges them), its parameters renamed to these
cpp_merge_defaults(N, TPs0, Ts, TPs) :- findall(TPs2, ( member(N-tmpl(TPs2, _), Ts), TPs2 \== TPs0, length(TPs2, K), length(TPs0, K) ), Others), cpp_merge_defaults_(TPs0, 1, TPs0, Others, TPs).
cpp_merge_defaults_([], _, _, _, []).
cpp_merge_defaults_([tparam(K, P, none)|Ps], I, All, Others, [tparam(K, P, D)|Qs]) :-
    member(TPs2, Others), ccl_nth(I, TPs2, tparam(_, _, D2)), D2 \== none, !,
    cpp_rename_params(TPs2, All, B), cpp_subst(D2, B, D), I1 is I + 1, cpp_merge_defaults_(Ps, I1, All, Others, Qs).
cpp_merge_defaults_([P|Ps], I, All, Others, [P|Qs]) :- I1 is I + 1, cpp_merge_defaults_(Ps, I1, All, Others, Qs).
cpp_rename_params([], [], []).
cpp_rename_params([tparam(K, P2, _)|Ps2], [tparam(_, P, _)|Ps], B) :- ( P2 == P -> B = B1 ; ( K == type ; K == pack ; K == template ) -> B = [P2-base([], [typedef(P)])|B1] ; B = [P2-id(P)|B1] ), cpp_rename_params(Ps2, Ps, B1).
cpp_rename_params([requires(_)|Ps2], Ps, B) :- cpp_rename_params(Ps2, Ps, B).
cpp_rename_params(Ps2, [requires(_)|Ps], B) :- cpp_rename_params(Ps2, Ps, B).
cpp_template_class_def(declare(_, base(_, [class(_, _, _, Ms)]))) :- Ms \== none.
cpp_template_class_def(declare(_, base(_, [struct(_, Ms)]))) :- Ms \== none.
%% a template-id as a type: a class template's instance, or an alias template's type under the bindings
cpp_instantiate_type(N, Args, T) :-
    (   cpp_class_template(N, TPs, Item), Item = typedef(_, [var(_, T0, _)]) -> cpp_bind_targs(TPs, Args, B), cpp_subst(T0, B, T1), cpp_type(T1, T)   % an alias template (the class definition wins the name)
    ;   cpp_instantiate_class(N, Args, Name), T = base([], [typedef(Name)]) ).
cpp_template_defined(declare(_, base(_, [class(_, _, _, Ms)]))) :- Ms \== none.
cpp_template_defined(declare(_, base(_, [struct(_, Ms)]))) :- Ms \== none.
cpp_template_defined(declaration(_, _, _, _)).
cpp_template_defined(typedef(_, _)).
%% template arguments as the bindings take them: a type resolved, an expression desugared and folded to its constant
cpp_targ_values([], []).
cpp_targ_values([A0|As], [A|Bs]) :- cpp_targ_value(A0, A), cpp_targ_values(As, Bs).
cpp_targ_value(type(T0), T) :- !, cpp_type(T0, T).
cpp_targ_value(base([], [typedef(scoped(Path, N))]), A) :- cpp_scope_class(Path, C), \+ cpp_class_typedef(C, N, _), !,   % X<T>::value read as a type: the class has no such type, so a value
    cpp_targ_value(scoped(Path, N), A).
cpp_targ_value(A0, A) :- cpp_is_type(A0), !, cpp_type(A0, A).
cpp_targ_value(pack(X), pack(X)) :- !.
cpp_targ_value(A0, A) :- cpp_expr(none, A0, A1), ( A1 = bool(_) -> A = A1 ; ccl_const_eval(A1, V) -> A = int(V) ; A = A1 ).
cpp_type_or_value(D, A) :- ( cpp_is_type(D) -> cpp_type(D, A) ; cpp_targ_value(D, A) ).
%% every type the walk meets goes through here: a template-id becomes its instance's name
cpp_type(T0, T) :- \+ compound(T0), !, T = T0.
cpp_type(base(Q, [typedef(X)]), T) :- cpp_template_id(X, N, Args), !, cpp_targ_values(Args, Args1), cpp_instantiate_type(N, Args1, T0), cpp_merge_quals(Q, T0, T).
cpp_type(base(Q, [typedef(scoped(Path, N))]), T) :- cpp_scope_class(Path, C), !,           % C::value_type, X<T>::type: the class's typedef (none: no type -- what SFINAE reads)
    ( cpp_class_typedef(C, N, T0) -> cpp_type(T0, T1), cpp_merge_quals(Q, T1, T) ; cpp_refuse(0, no_member_type(C, N)) ).
cpp_type(base(Q, [decltype(E)]), T) :- !, cpp_expr(none, E, E1), ( ccl_type_of(E1, T0), T0 \== unknown -> cpp_merge_quals(Q, T0, T) ; cpp_refuse(0, decltype_unknown) ).
cpp_type(base(Q, [builtin_type(N, Args)]), T) :- !, cpp_builtin_type(N, Args, T0), cpp_merge_quals(Q, T0, T).
cpp_type(base(Q, [typedef(scoped(_, N))]), base(Q, [typedef(N)])) :- atom(N), !.        % std::string: the namespace flattens
cpp_type(base(Q, [typedef(N)]), T) :- atom(N), cpp_class_ctx(C), \+ ccl_typedef_of(N, _), cpp_class_typedef(C, N, T0), !, cpp_type(T0, T1), cpp_merge_quals(Q, T1, T).   % value_type inside its class
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
cpp_add_instance_items(Items) :- cpp_linkonce(Items, Items1), forall(member(I, Items1), assertz('$cpp_out'(I))).
%% what a header or a template gives every unit alike links once: linkonce_odr
cpp_linkonce([], []).
cpp_linkonce([function(L, none, R, N, Ps, V, B)|Is], [function(L, linkonce, R, N, Ps, V, B)|Js]) :- !, cpp_linkonce(Is, Js).
cpp_linkonce([I|Is], [I|Js]) :- cpp_linkonce(Is, Js).
%% a class template at its arguments: registered and desugared like a class written out, once
%% the budget: a program's instantiations and header loads are hundreds; libc++'s closure, pulled in whole, is
%% tens of thousands and took the machine's memory once -- past the budget the compile stops with a diagnostic
cpp_spend(What) :- nb_getval('$cpp_budget', K), K1 is K + 1, nb_setval('$cpp_budget', K1), ( K1 > 3000 -> cpp_refuse(0, instantiation_budget(K1, What)) ; true ),
    ( catch(nb_getval('$cpp_trace', yes), _, fail) -> write(spend(K1, What)), nl, flush_output ; true ).
cpp_deeper(What) :- nb_getval('$cpp_depth', D), D1 is D + 1, nb_setval('$cpp_depth', D1), ( D1 > 120 -> cpp_refuse(0, instantiation_depth(D1, What)) ; true ).
cpp_shallower :- nb_getval('$cpp_depth', D), D1 is D - 1, nb_setval('$cpp_depth', D1).
cpp_instantiate_class(N, Args, Name) :-
    cpp_deeper(N), ( catch(cpp_instantiate_class_(N, Args, Name), E, (cpp_shallower, throw(E))) -> cpp_shallower ; cpp_shallower, fail ).
cpp_instantiate_class_(N, Args, Name) :-
    ( cpp_class_template(N, TPs, Item) -> true ; cpp_refuse(0, template_without_body(N)) ),
    cpp_bind_targs(TPs, Args, B), cpp_constraints_hold(N, TPs, B), cpp_instance_name(N, TPs, B, Name),
    (   cpp_instance_done(Name) -> true
    ;   cpp_spend(instance(Name)), cpp_full_args(TPs, B, FullArgs), cpp_instance_note(Name, inst(N, FullArgs)),
        Self = N-base([], [typedef(Name)]),                                                                        % the injected class name: inside its body, `vector' is this instance
        ( cpp_pick_spec(N, FullArgs, SB, SItem) -> cpp_subst(SItem, [Self|SB], Item1) ; cpp_template_defined(Item) -> cpp_subst(Item, [Self|B], Item1) ; cpp_refuse(0, template_without_body(N)) ),
        cpp_instance_class(Item1, L, K, Bases, Ms),
        cpp_isolated(( cpp_register_class(L, Name, Bases, Ms), cpp_item(declare(L, base([], [class(K, Name, Bases, Ms)])), Items) )),
        cpp_add_instance_items(Items) ).
cpp_instance_class(declare(L, base(_, [class(K, _, Bases, Ms)])), L, K, Bases, Ms).
cpp_instance_class(declare(L, base(_, [struct(_, Ms)])), L, struct, [], Ms).
%% the arguments in the parameters' order, a pack's spliced: what a specialization's pattern is matched against
cpp_full_args([], _, []).
cpp_full_args([requires(_)|TPs], B, As) :- !, cpp_full_args(TPs, B, As).
cpp_full_args([tparam(_, P, _)|TPs], B, As) :- memberchk(P-A, B), ( cpp_pack_list(A, L) -> append(L, As1, As) ; As = [A|As1] ), cpp_full_args(TPs, B, As1).
%% the specialization whose pattern matches, the most specialized of those that do (X is more specialized than Y when
%% X's pattern, taken as arguments, matches Y's)
cpp_pick_spec(N, Args, SB, Item) :-
    findall(m(TPs, Pat, It), '$cpp_spec'(N, TPs, Pat, It), Cands), Cands \== [],
    findall(m(TPs, Pat, It, B), ( member(m(TPs, Pat, It), Cands), cpp_match_pattern(Pat, Args, TPs, [], B) ), Ms), Ms \== [],
    cpp_most_special(Ms, Ms, m(_, _, Item, SB)).
cpp_most_special([M|_], All, M) :- \+ ( member(Y, All), Y \== M, cpp_more_special(Y, M), \+ cpp_more_special(M, Y) ), !.
cpp_most_special([_|Ms], All, M) :- cpp_most_special(Ms, All, M).
cpp_more_special(m(TPsX, PatX, _, _), m(TPsY, PatY, _, _)) :- cpp_pattern_as_args(PatX, TPsX, ArgsX), cpp_match_pattern(PatY, ArgsX, TPsY, [], _).
cpp_pattern_as_args([], _, []).
cpp_pattern_as_args([pack(_)|Ps], TPs, As) :- !, cpp_pattern_as_args(Ps, TPs, As).
cpp_pattern_as_args([P|Ps], TPs, [P|As]) :- cpp_pattern_as_args(Ps, TPs, As).
cpp_match_pattern([], [], _, B, B).
cpp_match_pattern([pack(base(_, [typedef(P)]))], Args, TPs, B0, [P-pack(Args)|B0]) :- memberchk(tparam(pack, P, _), TPs), !.
cpp_match_pattern([pack(id(P))], Args, TPs, B0, [P-pack(Args)|B0]) :- memberchk(tparam(vpack(_), P, _), TPs), !.
cpp_match_pattern([P|Ps], [A|As], TPs, B0, B) :- cpp_match_one(P, A, TPs, B0, B1), cpp_match_pattern(Ps, As, TPs, B1, B).
cpp_match_one(base(_, [typedef(P)]), A, TPs, B0, B) :- memberchk(tparam(type, P, _), TPs), !, ( memberchk(P-A0, B0) -> cpp_same_type(A0, A), B = B0 ; B = [P-A|B0] ).
cpp_match_one(id(P), A, TPs, B0, B) :- memberchk(tparam(K, P, _), TPs), \+ memberchk(K, [type, pack, template]), !, ( memberchk(P-A0, B0) -> cpp_same_value(A0, A), B = B0 ; B = [P-A|B0] ).
cpp_match_one(base(_, [typedef(tmpl(N, Sub))]), A, TPs, B0, B) :- !, cpp_instance_of(A, N, SubArgs), cpp_match_pattern(Sub, SubArgs, TPs, B0, B).
cpp_match_one(base(_, [typedef(scoped(_, tmpl(N, Sub)))]), A, TPs, B0, B) :- !, cpp_instance_of(A, N, SubArgs), cpp_match_pattern(Sub, SubArgs, TPs, B0, B).
cpp_match_one(ptr(_, X), A, TPs, B0, B) :- !, ccl_resolve_type(A, A1), A1 = ptr(_, Y), cpp_match_one(X, Y, TPs, B0, B).
cpp_match_one(ref(_, X), A, TPs, B0, B) :- !, A = ref(_, Y), cpp_match_one(X, Y, TPs, B0, B).
cpp_match_one(rref(_, X), A, TPs, B0, B) :- !, A = rref(_, Y), cpp_match_one(X, Y, TPs, B0, B).
cpp_match_one(arr(_, X), A, TPs, B0, B) :- !, ccl_resolve_type(A, A1), A1 = arr(_, Y), cpp_match_one(X, Y, TPs, B0, B).
cpp_match_one(P, A, _, B, B) :- cpp_is_type(P), !, cpp_same_type(P, A).
cpp_match_one(P, A, _, B, B) :- cpp_same_value(P, A).
%% an argument that is an instance of N: its arguments as they were bound
cpp_instance_of(base(_, [typedef(Name)]), N, Args) :- atom(Name), '$cpp_inst'(Name, inst(N, Args)), !.
cpp_instance_of(base(_, [typedef(X)]), N, Args) :- cpp_template_id(X, N, Args0), cpp_targ_values(Args0, Args).
cpp_same_type(A, B) :- cpp_type(A, A1), cpp_type(B, B1), ccl_resolve_type(A1, A2), ccl_resolve_type(B1, B2), A2 == B2.
cpp_same_value(A, B) :- ( ccl_const_eval(A, VA) -> true ; A = bool(X) -> ( X == true -> VA = 1 ; VA = 0 ) ), ( ccl_const_eval(B, VB) -> true ; B = bool(Y) -> ( Y == true -> VB = 1 ; VB = 0 ) ), VA =:= VB.
%% a variable template's instance: the initializer under the bindings, a constant where it folds
cpp_instantiate_variable(N, Args, E) :-
    ( cpp_class_template(N, TPs, declaration(_, _, _, [var(_, _, Init)])) -> true ; cpp_refuse(0, template_without_body(N)) ),
    cpp_bind_targs(TPs, Args, B), cpp_full_args(TPs, B, FullArgs),
    ( cpp_pick_spec(N, FullArgs, SB, declaration(_, _, _, [var(_, _, SInit)])) -> cpp_subst(SInit, SB, I1) ; cpp_subst(Init, B, I1) ),
    cpp_expr(none, I1, I2), ( I2 = bool(_) -> E = I2 ; ccl_const_eval(I2, V) -> E = int(V) ; cpp_refuse(0, variable_template_not_constant(N)) ).
%% a function template at a call: its type arguments explicit, then deduced from the arguments' types, then defaulted
cpp_instantiate_function(F, Explicit, As, Name) :-
    findall(TPs-Item, ( cpp_template(F, TPs, Item), Item = function(_, _, _, _, _, _, _) ), Cands0), reverse(Cands0, Cands),   % declaration order
    length(Cands, NC), nb_setval('$cpp_first_refusal', none), cpp_try_candidates(Cands, 1, NC, F, Explicit, As, Name).
cpp_try_candidates([], _, _, F, _, _, _) :- nb_getval('$cpp_first_refusal', W), ( W == none -> cpp_refuse(0, no_matching_template(F)) ; cpp_refuse(0, W) ).   % none fit: the first one's reason
cpp_try_candidates([TPs-function(L, Sto, Ret, _, Ps, V, Body)|Cs], K, NC, F, Explicit, As, Name) :-
    (   catch(cpp_signature_holds(F, TPs, Ps, Explicit, As, B), error(not_lowered(W), _), cpp_note_refusal(W))   % SFINAE: a signature that does not hold is no candidate
    ->  ( NC =:= 1 -> FN = F ; atomic_list_concat([F, '.c', K], FN) ), cpp_instance_name(FN, TPs, B, Name),
        cpp_instantiate_function_(F, TPs, B, L, Sto, Ret, Ps, V, Body, Name)
    ;   K1 is K + 1, cpp_try_candidates(Cs, K1, NC, F, Explicit, As, Name) ).
cpp_note_refusal(W) :- nb_getval('$cpp_first_refusal', W0), ( W0 == none -> nb_setval('$cpp_first_refusal', W) ; true ), fail.
cpp_signature_holds(F, TPs, Ps, Explicit, As, B) :-
    cpp_bind_explicit(TPs, Explicit, B0), cpp_deduce_args(Ps, As, TPs, B0, B1), cpp_bind_defaults(TPs, B1, B), cpp_constraints_hold(F, TPs, B).
cpp_instantiate_function_(F, _, B, L, Sto, Ret, Ps, V, Body, Name) :-
    (   cpp_instance_done(Name) -> true
    ;   cpp_instance_note(Name, F),
        cpp_subst(fn(Ret, Ps, Body), B, fn(Ret1, Ps1, Body1)),
        cpp_isolated(( cpp_plain_params(Ps1, Ps2), ( Ret1 = base(_, [auto]) -> cpp_lambda_ret(Ps2, Body1, Ret2) ; cpp_type(Ret1, Ret2) ),
                       ccl_declare(Name, fn(Ret2, Ps2, V)), cpp_note_defaults(Name, Ps1),
                       cpp_item(function(L, Sto, Ret2, Name, Ps1, V, Body1), Items) )),
        cpp_add_instance_items(Items) ).
cpp_bind_targs(TPs, Args, B) :- cpp_bind_targs_(TPs, Args, [], B).
cpp_bind_targs_([], _, B, B).
cpp_bind_targs_([requires(_)|TPs], Args, Acc, B) :- !, cpp_bind_targs_(TPs, Args, Acc, B).
cpp_bind_targs_([tparam(K, P, _)|_], Args, Acc, [P-pack(Args)|Acc]) :- cpp_pack_kind(K), !.     % a pack takes what is left
cpp_bind_targs_([tparam(_, P, D)|TPs], Args, Acc, B) :-
    ( Args = [A0|Rest] -> A = A0 ; D \== none -> cpp_subst(D, Acc, D1), cpp_type_or_value(D1, A), Rest = [] ; cpp_refuse(0, template_argument_missing(P)) ),
    cpp_bind_targs_(TPs, Rest, [P-A|Acc], B).
cpp_pack_kind(pack).
cpp_pack_kind(vpack(_)).
%% C++20: the head's requires-clause, under the bindings, must hold
cpp_constraints_hold(N, TPs, B) :- ( memberchk(requires(R), TPs) -> cpp_subst(R, B, R1), ( cpp_satisfied(R1) -> true ; cpp_refuse(0, constraint_not_satisfied(N)) ) ; true ).
cpp_bind_explicit([], _, []) :- !.
cpp_bind_explicit(_, [], []) :- !.
cpp_bind_explicit([requires(_)|TPs], As, B) :- !, cpp_bind_explicit(TPs, As, B).
cpp_bind_explicit([tparam(K, P, _)|_], As, [P-pack(As)]) :- cpp_pack_kind(K), !.
cpp_bind_explicit([tparam(_, P, _)|TPs], [A|As], [P-A|B]) :- cpp_bind_explicit(TPs, As, B).
%% what deduction left unbound: a pack is empty, a default stands (under the bindings so far), and a value
%% parameter's TYPE must resolve -- `enable_if<c, int>::type = 0' has no type when c is false (SFINAE)
cpp_bind_defaults([], B, B).
cpp_bind_defaults([requires(_)|TPs], B0, B) :- !, cpp_bind_defaults(TPs, B0, B).
cpp_bind_defaults([tparam(K, P, D)|TPs], B0, B) :-
    (   memberchk(P-_, B0) -> B1 = B0
    ;   cpp_pack_kind(K) -> B1 = [P-pack([])|B0]
    ;   D \== none -> cpp_subst(D, B0, D1), cpp_type_or_value(D1, A), B1 = [P-A|B0]
    ;   cpp_refuse(0, cannot_deduce(P)) ),
    ( cpp_value_param_type(K, T0) -> cpp_subst(T0, B1, T1), cpp_type(T1, T2), cpp_type_resolved(T2) ; true ),
    cpp_bind_defaults(TPs, B1, B).
cpp_value_param_type(K, K) :- compound(K), K \= vpack(_), cpp_is_type(K).
cpp_type_resolved(T) :- \+ cpp_has_scoped(T).
cpp_has_scoped(T) :- compound(T), ( T = typedef(scoped(_, _)) -> true ; T =.. [_|As], member(A, As), cpp_has_scoped(A) ).
cpp_deduce_args([param(pack(T), _)], As, TPs, B0, B) :- !,                                       % a trailing pack: one element deduced per argument left
    findall(AT, ( member(A, As), ( ccl_type_of(A, AT0), AT0 \== unknown -> cpp_decayed(AT0, AT) ; AT = unknown ) ), ATs),
    cpp_deduce_pack(T, ATs, TPs, B0, B).
cpp_deduce_args([], _, _, B, B) :- !.
cpp_deduce_args(_, [], _, B, B) :- !.
cpp_deduce_args([P|Ps], [A|As], TPs, B0, B) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, cpp_deduce_one(PT, A, TPs, B0, B1), cpp_deduce_args(Ps, As, TPs, B1, B).
cpp_deduce_pack(T, ATs, TPs, B0, [P-pack(Es)|B0]) :-
    cpp_pack_param_in(T, TPs, P), !,
    findall(E, ( member(AT, ATs), ( AT == unknown -> E = unknown ; cpp_match(T, AT, [tparam(type, P, none)], [], Bk), memberchk(P-E, Bk) ) ), Es).
cpp_deduce_pack(_, _, _, B, B).
cpp_pack_param_in(T, TPs, P) :- member(tparam(pack, P, _), TPs), cpp_names_in(T, P), !.
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
cpp_type_key(pack([]), e) :- !.
cpp_type_key(pack(L), K) :- !, findall(K1, ( member(A, L), cpp_type_key(A, K1) ), Ks), atomic_list_concat(Ks, '_', K).
cpp_type_key(vpack(L), K) :- !, cpp_type_key(pack(L), K).
cpp_type_key(base(_, S), K) :- !, findall(W, ( member(X, S), cpp_spec_key(X, W) ), Ws), atomic_list_concat(Ws, '_', K).
cpp_type_key(ptr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_p', K).
cpp_type_key(ref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_r', K).
cpp_type_key(rref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_rr', K).
cpp_type_key(arr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_a', K).
cpp_type_key(int(N), N) :- !.
cpp_type_key(uint(N), K) :- !, atom_concat(N, u, K).
cpp_type_key(long(N), K) :- !, atom_concat(N, l, K).
cpp_type_key(ulong(N), K) :- !, atom_concat(N, ul, K).
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
cpp_subst([], _, []) :- !.
cpp_subst([X|Xs], B, Ys) :- !, cpp_subst_elems([X|Xs], B, Ys).
cpp_subst(sizeof_pack(P), B, int(N)) :- memberchk(P-Pk, B), cpp_pack_list(Pk, L), !, length(L, N).                  % a pack not bound yet (a member template's) stays
cpp_subst(fold(Op, dots, E), B, R) :- cpp_pack_names(E, B, [_|_]), !, cpp_expand_pack(E, B, Es), cpp_fold_left(Op, Es, R).      % (... op E)
cpp_subst(fold(Op, E, dots), B, R) :- cpp_pack_names(E, B, [_|_]), !, cpp_expand_pack(E, B, Es), cpp_fold_right(Op, Es, R).     % (E op ...)
cpp_subst(fold(Op, A, dots, Z), B, R) :- cpp_pack_names(fold(A, Z), B, [_|_]), !,                                              % (E op ... op I), (I op ... op E)
    (   cpp_pack_names(A, B, [_|_]) -> cpp_expand_pack(A, B, Es), cpp_subst(Z, B, Z1), append(Es, [Z1], All), cpp_fold_right(Op, All, R)
    ;   cpp_expand_pack(Z, B, Es), cpp_subst(A, B, A1), cpp_fold_left(Op, [A1|Es], R) ).
cpp_subst(function(L, S, R, N, Ps, V, Body), B, function(L, S, R1, N1, Ps1, V, Body1)) :- !,
    cpp_param_packs(Ps, B, B1), cpp_subst(R, B1, R1), cpp_subst(N, B1, N1), cpp_subst(Ps, B1, Ps1), cpp_subst(Body, B1, Body1).
cpp_subst(method(L, Qs, R, M, Ps, V, Body), B, method(L, Qs, R1, M, Ps1, V, Body1)) :- !,
    cpp_param_packs(Ps, B, B1), cpp_subst(R, B1, R1), cpp_subst(Ps, B1, Ps1), cpp_subst(Body, B1, Body1).
cpp_subst(ctor(L, Qs, Ps, Inits, Body), B, ctor(L, Qs, Ps1, Inits1, Body1)) :- !,
    cpp_param_packs(Ps, B, B1), cpp_subst(Ps, B1, Ps1), cpp_subst(Inits, B1, Inits1), cpp_subst(Body, B1, Body1).
cpp_subst(fn(R, Ps, X), B, fn(R1, Ps1, X1)) :- !, cpp_param_packs(Ps, B, B1), cpp_subst(R, B1, R1), cpp_subst(Ps, B1, Ps1), cpp_subst(X, B1, X1).
cpp_subst(template(L, TPs, M), B, template(L, TPs, M1)) :- !, cpp_shadow(TPs, B, B1), cpp_subst(M, B1, M1).        % a member template's own parameters shadow
cpp_subst(base(Q, [typedef(P)]), B, T) :- memberchk(P-A, B), !, ( cpp_pack_list(A, _) -> cpp_refuse(0, pack_unexpanded(P)) ; cpp_merge_quals(Q, A, T) ).
cpp_subst(sizeof(id(P)), B, sizeof_type(A)) :- memberchk(P-A, B), cpp_is_type(A), !.          % sizeof(T), read as an expression while T was a name
cpp_subst(call(id(P), [X0]), B, ccast(functional, A, X)) :- memberchk(P-A, B), cpp_is_type(A), !, cpp_subst(X0, B, X).   % T(x)
cpp_subst(id(P), B, V) :- memberchk(P-V0, B), !, ( cpp_pack_list(V0, _) -> cpp_refuse(0, pack_unexpanded(P)) ; V = V0 ).
cpp_subst(scoped(Path, N0), B, scoped(Path1, N)) :- !, cpp_subst_path(Path, B, Path1), ( atom(N0) -> N = N0 ; cpp_subst(N0, B, N) ).   % C::value_type with C a parameter: the class it is bound to; std::vector<T> under T
cpp_subst_path([], _, []).
cpp_subst_path([P|Ps], B, [P1|Qs]) :- ( atom(P), memberchk(P-A, B), A = base(_, [typedef(X)]) -> P1 = X ; cpp_subst(P, B, P1) ), cpp_subst_path(Ps, B, Qs).
cpp_subst(str(S), _, str(S)) :- !.
cpp_subst(T0, B, T) :- T0 =.. [F|As], cpp_subst_list(As, B, Bs), T =.. [F|Bs].
cpp_subst_list([], _, []).
cpp_subst_list([X|Xs], B, [Y|Ys]) :- cpp_subst(X, B, Y), cpp_subst_list(Xs, B, Ys).
%% the elements of a list: a pack expansion `X...' becomes one X per element of the packs it names,
%% wherever the reader left pack/1 -- an argument, a template argument, a base, a parameter, an item, an initializer
cpp_subst_elems([], _, []).
cpp_subst_elems([pack(X)|Xs], B, Ys) :- cpp_pack_names(X, B, [_|_]), !, cpp_expand_pack(X, B, Es), cpp_subst_elems(Xs, B, Ys1), append(Es, Ys1, Ys).
cpp_subst_elems([base(A, pack(Q))|Xs], B, Ys) :- cpp_pack_names(Q, B, [_|_]), !, cpp_expand_pack(Q, B, Qs), findall(base(A, Q1), member(Q1, Qs), Bs), cpp_subst_elems(Xs, B, Ys1), append(Bs, Ys1, Ys).
cpp_subst_elems([item(D, pack(V))|Xs], B, Ys) :- cpp_pack_names(V, B, [_|_]), !, cpp_expand_pack(V, B, Vs), findall(item(D, V1), member(V1, Vs), Is), cpp_subst_elems(Xs, B, Ys1), append(Is, Ys1, Ys).
cpp_subst_elems([param(pack(T), N)|Xs], B, Ys) :- cpp_pack_names(T, B, [_|_]), !, cpp_expand_pack(T, B, Ts), cpp_number_params(Ts, N, 1, Ps), cpp_subst_elems(Xs, B, Ys1), append(Ps, Ys1, Ys).
cpp_subst_elems([X|Xs], B, [Y|Ys]) :- cpp_subst(X, B, Y), cpp_subst_elems(Xs, B, Ys).
cpp_number_params([], _, _, []).
cpp_number_params([T|Ts], N, K, [param(T, Nk)|Ps]) :- atomic_list_concat([N, '$', K], Nk), K1 is K + 1, cpp_number_params(Ts, N, K1, Ps).
%% a parameter pack `Ts... args' under the bindings: the names args$1 .. args$k, a pack of values, for the body
cpp_param_packs([], B, B).
cpp_param_packs([param(pack(T), N)|Ps], B0, B) :- atom(N), cpp_pack_names(T, B0, [P|_]), !, memberchk(P-Pk, B0), cpp_pack_list(Pk, L), length(L, K),
    findall(id(Nk), ( between(1, K, I), atomic_list_concat([N, '$', I], Nk) ), Ids), cpp_param_packs(Ps, [N-vpack(Ids)|B0], B).
cpp_param_packs([_|Ps], B0, B) :- cpp_param_packs(Ps, B0, B).
cpp_pack_list(pack(L), L).
cpp_pack_list(vpack(L), L).
%% the packs a term names, among the bindings
cpp_pack_names(X, B, Ns) :- findall(P, ( member(P-Pk, B), cpp_pack_list(Pk, _), cpp_names_in(X, P) ), Ns0), cpp_dedupe(Ns0, Ns).
cpp_names_in(id(P), P) :- !.
cpp_names_in(typedef(P), P) :- !.
cpp_names_in(T, P) :- compound(T), T =.. [_|As], member(A, As), cpp_names_in(A, P), !.
cpp_dedupe([], []).
cpp_dedupe([X|Xs], [X|Ys]) :- \+ memberchk(X, Xs), !, cpp_dedupe(Xs, Ys).
cpp_dedupe([_|Xs], Ys) :- cpp_dedupe(Xs, Ys).
cpp_expand_pack(X, B, Xs) :-
    cpp_pack_names(X, B, Ns), ( Ns == [] -> cpp_refuse(0, pack_expansion_without_pack) ; true ),
    Ns = [N1|_], memberchk(N1-Pk1, B), cpp_pack_list(Pk1, L1), length(L1, K),
    forall(member(N, Ns), ( memberchk(N-Pk, B), cpp_pack_list(Pk, L), length(L, K) )),
    findall(Xk, ( between(1, K, I), cpp_pack_select(B, Ns, I, Bk), cpp_subst(X, Bk, Xk) ), Xs).
cpp_pack_select([], _, _, []).
cpp_pack_select([P-Pk|B], Ns, I, [P-E|B1]) :- memberchk(P, Ns), cpp_pack_list(Pk, L), !, nth1(I, L, E), cpp_pack_select(B, Ns, I, B1).
cpp_pack_select([X|B], Ns, I, [X|B1]) :- cpp_pack_select(B, Ns, I, B1).
cpp_shadow([], B, B).
cpp_shadow([tparam(_, P, _)|TPs], B0, B) :- !, findall(X, ( member(X, B0), X \= P-_ ), B1), cpp_shadow(TPs, B1, B).
cpp_shadow([_|TPs], B0, B) :- cpp_shadow(TPs, B0, B).
%% a fold: right, E1 op (E2 op (... op En)); left, ((E1 op E2) op ...) op En; empty: what the standard gives && || and ,
cpp_fold_right(Op, [], R) :- !, cpp_fold_empty(Op, R).
cpp_fold_right(_, [E], E) :- !.
cpp_fold_right(Op, [E|Es], R) :- cpp_fold_right(Op, Es, R1), cpp_fold_op(Op, E, R1, R).
cpp_fold_left(Op, [], R) :- !, cpp_fold_empty(Op, R).
cpp_fold_left(Op, [E|Es], R) :- cpp_fold_left_(Op, Es, E, R).
cpp_fold_left_(_, [], R, R).
cpp_fold_left_(Op, [E|Es], Acc, R) :- cpp_fold_op(Op, Acc, E, Acc1), cpp_fold_left_(Op, Es, Acc1, R).
cpp_fold_op(',', A, B, comma(A, B)) :- !.
cpp_fold_op(Op, A, B, assign(Op, A, B)) :- memberchk(Op, ['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=']), !.
cpp_fold_op(Op, A, B, bin(Op, A, B)).
cpp_fold_empty('&&', bool(true)) :- !.
cpp_fold_empty('||', bool(false)) :- !.
cpp_fold_empty(',', int(0)) :- !.
cpp_fold_empty(Op, _) :- cpp_refuse(0, empty_fold(Op)).
%% ---- member templates, instantiated at a call --------------------------------------------------
cpp_member_template_call(C, M, Explicit, As, Name) :-
    findall(TPs-Mem, '$cpp_mt'(C, M, TPs, Mem), Cands), Cands \== [],
    cpp_try_member(Cands, C, Explicit, As, Name).
cpp_try_member([], _, _, _, _) :- fail.
cpp_try_member([TPs-method(L, Qs, Ret, M, Ps, V, Body)|Cs], C, Explicit, As, Name) :-
    (   catch(cpp_signature_holds(M, TPs, Ps, Explicit, As, B), error(not_lowered(_), _), fail)
    ->  cpp_instance_name(M, TPs, B, MName), cpp_subst(method(L, Qs, Ret, M, Ps, V, Body), B, method(_, _, Ret1, _, Ps1, _, Body1)),
        cpp_mangle(C, MName, Ps1, Name),
        (   cpp_instance_done(Name) -> true
        ;   cpp_instance_note(Name, C), cpp_class(C, cls(Base, _, _, _, Defaults, _)),
            cpp_isolated(cpp_in_class(C, ( cpp_declare_members([method(L, Qs, Ret1, MName, Ps1, V, Body1)], C), cpp_member_fns([method(L, Qs, Ret1, MName, Ps1, V, Body1)], C, Base, Defaults, Fns) ))),
            cpp_add_instance_items(Fns) )
    ;   cpp_try_member(Cs, C, Explicit, As, Name) ).
cpp_member_template_ctor(C, As, Name) :-
    findall(TPs-Mem, '$cpp_mt'(C, ctor, TPs, Mem), Cands), Cands \== [],
    cpp_try_ctor(Cands, C, As, Name).
cpp_try_ctor([TPs-ctor(L, Qs, Ps, Inits, Body)|Cs], C, As, Name) :-
    (   catch(cpp_signature_holds(C, TPs, Ps, [], As, B), error(not_lowered(_), _), fail)
    ->  cpp_subst(ctor(L, Qs, Ps, Inits, Body), B, ctor(_, _, Ps1, Inits1, Body1)), cpp_mangle(C, C, Ps1, Name),
        (   cpp_instance_done(Name) -> true
        ;   cpp_instance_note(Name, C), cpp_class(C, cls(Base, _, _, _, Defaults, _)),
            cpp_isolated(cpp_in_class(C, ( cpp_declare_members([ctor(L, Qs, Ps1, Inits1, Body1)], C), cpp_member_fns([ctor(L, Qs, Ps1, Inits1, Body1)], C, Base, Defaults, Fns) ))),
            cpp_add_instance_items(Fns) )
    ;   cpp_try_ctor(Cs, C, As, Name) ).
%% ---- the compiler's traits, decided here ----------------------------------------------------
cpp_trait('__is_same', [A, B], bool(V)) :- !, cpp_trait_type(A, TA), cpp_trait_type(B, TB), ( cpp_same_type(TA, TB) -> V = true ; V = false ).
cpp_trait(N, [A], bool(V)) :- cpp_trait_type(A, T), ccl_resolve_type(T, R), cpp_trait_of(N, R, V), !.
cpp_trait(N, _, _) :- cpp_refuse(0, trait_unknown(N)).
cpp_trait_type(type(T0), T) :- !, cpp_type(T0, T).
cpp_trait_type(id(N), T) :- cpp_type(base([], [typedef(N)]), T), !.
cpp_trait_type(T0, T) :- cpp_type(T0, T).
cpp_trait_of('__is_integral', R, V) :- ( R = base(_, S), ccl_is_arith(R), \+ memberchk(float, S), \+ memberchk(double, S) -> V = true ; V = false ).
cpp_trait_of('__is_floating_point', R, V) :- ( R = base(_, S), ( memberchk(float, S) ; memberchk(double, S) ) -> V = true ; V = false ).
cpp_trait_of('__is_arithmetic', R, V) :- ( ccl_is_arith(R) -> V = true ; V = false ).
cpp_trait_of('__is_pointer', R, V) :- ( R = ptr(_, _) -> V = true ; V = false ).
cpp_trait_of('__is_reference', R, V) :- ( ( R = ref(_, _) ; R = rref(_, _) ) -> V = true ; V = false ).
cpp_trait_of('__is_lvalue_reference', R, V) :- ( R = ref(_, _) -> V = true ; V = false ).
cpp_trait_of('__is_rvalue_reference', R, V) :- ( R = rref(_, _) -> V = true ; V = false ).
cpp_trait_of('__is_const', R, V) :- ( R = base(Q, _), memberchk(const, Q) -> V = true ; V = false ).
cpp_trait_of('__is_void', R, V) :- ( R = base(_, [void]) -> V = true ; V = false ).
cpp_trait_of('__is_array', R, V) :- ( R = arr(_, _) -> V = true ; V = false ).
cpp_trait_of('__is_class', R, V) :- ( ( R = base(_, [struct(_, _)]) ; R = base(_, [class(_, _, _, _)]) ; R = base(_, [union(_, _)]) ) -> V = true ; V = false ).
cpp_trait_of('__is_enum', R, V) :- ( ( R = base(_, [enum(_, _)]) ; R = base(_, [enum_class(_, _)]) ) -> V = true ; V = false ).
cpp_trait_of('__is_signed', R, V) :- ( ccl_is_arith(R), R = base(_, S), \+ memberchk(unsigned, S), \+ memberchk(bool, S) -> V = true ; V = false ).
cpp_trait_of('__is_unsigned', R, V) :- ( R = base(_, S), ( memberchk(unsigned, S) ; memberchk(bool, S) ) -> V = true ; V = false ).
%% the traits that name a type
cpp_builtin_type('__remove_cv', [A], base([], S)) :- !, cpp_trait_type(A, T), ccl_resolve_type(T, base(_, S)).
cpp_builtin_type('__remove_const', [A], base(Q1, S)) :- !, cpp_trait_type(A, T), ccl_resolve_type(T, base(Q, S)), ccl_delete_one(Q, const, Q1).
cpp_builtin_type('__remove_reference_t', [A], T1) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__remove_cvref', [A], base([], S)) :- !, cpp_trait_type(A, T), ccl_unref(T, T0), ccl_resolve_type(T0, base(_, S)).
cpp_builtin_type('__decay', [A], T1) :- !, cpp_trait_type(A, T), ccl_unref(T, T0), cpp_decayed(T0, T1).
cpp_builtin_type('__add_lvalue_reference', [A], ref([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__add_rvalue_reference', [A], rref([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__add_pointer', [A], ptr([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__remove_pointer', [A], T1) :- !, cpp_trait_type(A, T), ( ccl_resolve_type(T, ptr(_, T1)) -> true ; T1 = T ).
cpp_builtin_type(N, _, _) :- cpp_refuse(0, trait_unknown(N)).
cpp_is_type(T) :- ( T = base(_, _) ; T = ptr(_, _) ; T = ref(_, _) ; T = rref(_, _) ; T = arr(_, _) ; T = fn(_, _, _) ), !.
cpp_merge_quals(Q, base(Q2, S), base(Q3, S)) :- !, append(Q, Q2, Q3).
cpp_merge_quals(_, A, A).

%% ---- lambdas: a class of the captures, operator() the body ----------------------------------
cpp_lambda(Ctx, Caps, Ps0, Ret0, Body, compound_lit(T, init(Items))) :-
    ( memberchk(cap(this), Caps) -> cpp_refuse(0, capture_this) ; true ),
    ( Ps0 = [param(this(ST0), SN)|Ps1] -> true ; Ps1 = Ps0, SN = none ),                                         % C++23: an explicit object parameter: the closure itself, `this auto self'
    ( ( memberchk(tparams(_), Caps) ; member(P, Ps1), ( P = param(PT, _) ; P = param(PT, _, _) ), cpp_auto_in(PT, 0, _, _) ) -> cpp_refuse(0, generic_lambda) ; true ),   % C++20: a template lambda, a member template of the closure
    cpp_plain_params(Ps1, Ps),
    nb_getval('$cpp_lambdas', K0), K is K0 + 1, nb_setval('$cpp_lambdas', K), atomic_list_concat(['lambda.', K], Name),
    T = base([], [typedef(Name)]),
    ( SN == none -> Self = [], SelfPs = Ps ; cpp_self_type(ST0, Name, ST), Self = [param(this(ST), SN)], SelfPs = [param(ST, SN)|Ps] ),
    cpp_captures(Caps, SelfPs, Body, Captures),
    ( Ret0 == none -> cpp_lambda_ret(SelfPs, Body, Ret) ; cpp_type(Ret0, Ret) ),
    findall(member(MT, N, none), ( member(N-How, Captures), ( How = val(CT) -> MT = CT ; How = ref(CT), MT = ref([], CT) ) ), Ms0),
    findall(item([], V), ( member(N-How, Captures), ( How = val(_) -> V0 = id(N) ; V0 = addr(id(N)) ), cpp_expr(Ctx, V0, V) ), Items),
    append(Self, Ps, MPs), append(Ms0, [method(0, [closure], Ret, operator('()'), MPs, false, Body)], Ms),
    cpp_isolated(( cpp_register_class(0, Name, [], Ms), cpp_item(declare(0, base([], [class(struct, Name, [], Ms)])), Its) )),
    cpp_add_instance_items(Its).
%% the closure's own type for `this auto self': by value, by reference (an rvalue reference read as one), or as named
cpp_self_type(base(Q, [auto]), Name, base(Q, [typedef(Name)])) :- !.
cpp_self_type(ref(Q, T0), Name, ref(Q, T)) :- !, cpp_self_type(T0, Name, T).
cpp_self_type(rref(Q, T0), Name, ref(Q, T)) :- !, cpp_self_type(T0, Name, T).
cpp_self_type(T, _, T).
%% the captures, Name-val(Type) | Name-ref(Type): the ones named, then, under a default, every enclosing local the body names
cpp_captures(Caps, Ps, Body, Captures) :-
    findall(N-How, ( member(cap(K, N), Caps), K \== default, ccl_type_of(id(N), CT), CT \== unknown, cpp_decayed(CT, CT1), ( K == val -> How = val(CT1) ; How = ref(CT1) ) ), Explicit),
    (   memberchk(cap(default, D), Caps)
    ->  cpp_lambda_free(Ps, Body, Names),
        findall(N-How, ( member(N, Names), \+ memberchk(N-_, Explicit), cpp_local(N), ccl_type_of(id(N), CT), CT \== unknown, cpp_decayed(CT, CT1), ( D == '=' -> How = val(CT1) ; How = ref(CT1) ) ), Implicit)
    ;   Implicit = [] ),
    append(Explicit, Implicit, Captures).
cpp_lambda_free(Ps, Body, Names) :-
    cpp_ids(Body, Ids0), sort(Ids0, Ids), findall(N, member(param(_, N), Ps), PNs), cpp_bound(Body, Bs0), append(PNs, Bs0, Bound),
    findall(N, ( member(N, Ids), \+ memberchk(N, Bound) ), Names).
cpp_ids(id(N), [N]) :- atom(N), !.
cpp_ids(T, Ns) :- compound(T), !, T =.. [_|As], cpp_ids_list(As, Ns).
cpp_ids(_, []).
cpp_ids_list([], []).
cpp_ids_list([A|As], Ns) :- cpp_ids(A, N1), cpp_ids_list(As, N2), append(N1, N2, Ns).
cpp_bound(var(N, _, _), [N]) :- atom(N), !.
cpp_bound(T, Ns) :- compound(T), !, T =.. [_|As], cpp_bound_list(As, Ns).
cpp_bound(_, []).
cpp_bound_list([], []).
cpp_bound_list([A|As], Ns) :- cpp_bound(A, N1), cpp_bound_list(As, N2), append(N1, N2, Ns).
%% the result type when not written: the first return's, typed under the parameters
cpp_lambda_ret(Ps, Body, Ret) :-
    (   cpp_first_return(Body, E)
    ->  ccl_scope_push, ccl_declare_params(Ps), ( ccl_type_of(E, T), T \== unknown -> Ret = T ; Ret = none ), ccl_scope_pop,
        ( Ret == none -> cpp_refuse(0, lambda_result_type) ; true )
    ;   Ret = base([], [void]) ).
cpp_first_return(return(_, E), E) :- !.
cpp_first_return(T, E) :- compound(T), T =.. [_|As], member(A, As), cpp_first_return(A, E), !.

%% ---- C++20 concepts: satisfaction ----------------------------------------------------------
%% a constraint holds when its concept's expression holds under the arguments: `&&', `||', `!',
%% a requires-expression whose requirements type-check under its parameters (an expression has a
%% type, a type resolves, a compound's type satisfies its concept, a nested one holds), else a
%% constant expression that is not 0; a trait of libc++'s has no body here and is refused
cpp_satisfied(bin('&&', A, B)) :- !, cpp_satisfied(A), cpp_satisfied(B).
cpp_satisfied(bin('||', A, B)) :- !, ( cpp_satisfied(A) -> true ; cpp_satisfied(B) ).
cpp_satisfied(not(E)) :- !, \+ cpp_satisfied(E).
cpp_satisfied(bool(true)) :- !.
cpp_satisfied(bool(false)) :- !, fail.
cpp_satisfied(tmpl(C, Args)) :- !, cpp_concept_holds(C, Args).
cpp_satisfied(id(C)) :- nb_getval('$cpp_concepts', Cs), memberchk(C-_, Cs), !, cpp_concept_holds(C, []).
cpp_satisfied(requires_expr(Ps0, Reqs)) :- !,
    cpp_plain_params(Ps0, Ps), ccl_scope_push, ccl_declare_params(Ps),
    ( cpp_requirements_hold(Reqs) -> ccl_scope_pop ; ccl_scope_pop, fail ).
cpp_satisfied(E) :- ( ccl_const_eval(E, V) -> V =\= 0 ; cpp_refuse(0, constraint_unknown(E)) ).
cpp_concept_holds(C, Args) :-
    ( nb_getval('$cpp_concepts', Cs), memberchk(C-concept(TPs, E), Cs) -> true ; cpp_refuse(0, concept_without_body(C)) ),
    cpp_types(Args, Args1), cpp_bind_targs(TPs, Args1, B), cpp_subst(E, B, E1), cpp_satisfied(E1).
cpp_requirements_hold([]).
cpp_requirements_hold([R|Rs]) :- cpp_requirement_holds(R), cpp_requirements_hold(Rs).
cpp_requirement_holds(expr(E)) :- cpp_expr(none, E, E1), ccl_type_of(E1, T), T \== unknown.
cpp_requirement_holds(type(T0)) :- cpp_type(T0, T), ccl_resolve_type(T, R), \+ R = base(_, [typedef(_)]).
cpp_requirement_holds(compound(E, C)) :- cpp_expr(none, E, E1), ccl_type_of(E1, T), T \== unknown, ( C == none -> true ; cpp_concept_of(C, T) ).
cpp_requirement_holds(nested(E)) :- cpp_satisfied(E).
cpp_concept_of(id(C), T) :- cpp_concept_holds(C, [T]).
cpp_concept_of(tmpl(C, Args), T) :- cpp_concept_holds(C, [T|Args]).

%% a constant condition: a constant expression, or a constraint
cpp_const_bool(E, V) :- ccl_const_eval(E, N), !, ( N =\= 0 -> V = true ; V = false ).
cpp_const_bool(bool(B), B) :- !.
cpp_const_bool(tmpl(C, Args), V) :- nb_getval('$cpp_concepts', Cs), memberchk(C-_, Cs), !, ( cpp_concept_holds(C, Args) -> V = true ; V = false ).
