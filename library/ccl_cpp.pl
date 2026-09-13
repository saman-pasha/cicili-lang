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
    cpp_reset('$cpp_cls'/2), cpp_reset('$cpp_tmpl'/3), cpp_reset('$cpp_spec'/4), cpp_reset('$cpp_mt'/4), cpp_reset('$cpp_inst'/2), cpp_reset('$cpp_out'/1), cpp_reset('$cpp_mdef'/5), cpp_reset('$cpp_extra'/2), cpp_reset('$cpp_vbase'/1),
    nb_setval('$cpp_defaults', []), nb_setval('$cpp_free_ops', []), nb_setval('$cpp_dtor_defs', []), nb_setval('$cpp_lambdas', 0), nb_setval('$cpp_closure_this', []), nb_setval('$cpp_temps', none), nb_setval('$cpp_making', []),
    nb_setval('$cpp_nontrivial', []),
    nb_setval('$cpp_concepts', []),
    nb_setval('$cpp_class_types', []), nb_setval('$cpp_static_inits', []), nb_setval('$cpp_enclosing', []),
    nb_setval('$cpp_lazy', []), nb_setval('$cpp_hdr_loaded', []), nb_setval('$cpp_budget', 0), nb_setval('$cpp_depth', 0), nb_setval('$cpp_class_ctx', none), ( catch(abolish('$cpp_hdr'/2), _, true) -> true ; true ), dynamic('$cpp_hdr'/2), dynamic('$cpp_hdr_ast'/2),
    cpp_reset('$cpp_lib'/1), cpp_reset('$cpp_libfn'/1), nb_setval('$cpp_in_lib', no),
    cpp_reset('$cpp_fn'/5), cpp_reset('$cpp_nested'/5), cpp_reset('$cpp_nested_out'/1), cpp_reset('$cpp_union'/1), cpp_reset('$cpp_default_ctor'/1), cpp_reset('$cpp_iname'/3), nb_setval('$cpp_nesting', []), cpp_reset('$cpp_hdr_ns'/2), dynamic('$cpp_hdr_ast_ns'/2), nb_setval('$cpp_cnames', []), nb_setval('$cpp_gvar', []), nb_setval('$cpp_fn_refusal', none),
    ( catch(nb_getval('$cpp_trace', _), _, fail) -> true ; nb_setval('$cpp_trace', no) ),
    forall(member(unit(Is), Units), cpp_note_fns(Is)),                                 % the free functions FIRST: a name is overloaded or not before any call to it is read
    forall(member(unit(Is), Units), cpp_register_(Is)).

%% ---- FREE FUNCTION OVERLOADS ----------------------------------------------------------------------
%% C++ tells `int f(int)' from `double f(double)' by the arguments and gives each its own symbol; C has one
%% name one function, which is what this compiler emitted -- so of libc++'s ten `__convert_to_integral'
%% overloads only the first got a body and every call went to it, whatever it passed. Each DEFINITION of an
%% overloaded name is mangled by its parameters' type keys, `F.int', `F.unsigned_long', as a method already
%% was; a name with ONE definition keeps it, so every C function, every `main' and everything a linker must
%% find by name is untouched, and so is a DECLARATION of an overload (we may name only what we define).
%% The key is taken from the parameters AS WRITTEN, at the registration, the emission and the call alike.
cpp_note_fns([]).
cpp_note_fns([namespace(_, _, Js)|Is]) :- !, cpp_note_fns(Js), cpp_note_fns(Is).
cpp_note_fns([extern_c(_, Js)|Is]) :- !, cpp_c_names(Js), cpp_note_fns(Js), cpp_note_fns(Is).      % extern "C": C linkage, never a mangled name
cpp_note_fns([function(_, _, Ret, N, Ps, V, Body)|Is]) :- atom(N), !, cpp_fn_origin(Ret, V, Body, O), cpp_fn_put(N, Ps, Body, O), cpp_note_fns(Is).
cpp_note_fns([declaration(_, _, _, Vs)|Is]) :- !, forall(member(var(N, fn(Ret, Ps, V), _), Vs), ( atom(N) -> cpp_fn_put(N, Ps, none, decl(Ret, V)) ; true )), cpp_note_fns(Is).
cpp_fn_origin(Ret, V, none, decl(Ret, V)) :- !.                                          % what a DECLARATION alone can say: the result and the ellipsis a mangled name needs
cpp_fn_origin(_, _, _, own).
cpp_note_fns([_|Is]) :- cpp_note_fns(Is).
%% a LIBRARY header's items of one name, before any of them is registered: its definitions kept whole, to emit on use
cpp_note_hdr_fns([]).
cpp_note_hdr_fns([function(L, Sto, Ret, N, Ps, V, Body)|Is]) :- atom(N), Body \== none, !,
    cpp_fn_put(N, Ps, Body, lazy(function(L, Sto, Ret, N, Ps, V, Body))), cpp_note_hdr_fns(Is).
cpp_note_hdr_fns([I|Is]) :- cpp_note_fns([I]), cpp_note_hdr_fns(Is).
cpp_fn_put(N, Ps, Body, Origin) :- ( Body == none -> D = no ; D = yes ), cpp_params_key(Ps, K),
    ( '$cpp_fn'(N, K, _, D, _) -> true ; assertz('$cpp_fn'(N, K, Ps, D, Origin)) ).
cpp_c_names([]).
cpp_c_names([I|Is]) :- ( cpp_item_name(I, N) -> nb_getval('$cpp_cnames', Ns), nb_setval('$cpp_cnames', [N|Ns]) ; true ), cpp_c_names(Is).
cpp_item_name(function(_, _, _, N, _, _, _), N) :- atom(N).
cpp_item_name(declaration(_, _, _, [var(N, fn(_, _, _), _)|_]), N) :- atom(N).
cpp_c_name(N) :- nb_getval('$cpp_cnames', Ns), memberchk(N, Ns).
%% the name a free function is emitted and called under: its own, unless the name has two definitions of
%% different parameters and this item is one of them
cpp_fn_name(F, _, _, F) :- cpp_c_name(F), !.
cpp_fn_name(F, Ps, no, Name) :- cpp_mangled_name(F, Ps, Name), !.                        % declared here and DEFINED in the shipped library: its own C++ symbol
cpp_fn_name(F, Ps, yes, Name) :- cpp_fn_overloaded(F), !, cpp_params_key(Ps, K), atomic_list_concat([F, '.', K], Name).
cpp_fn_name(F, _, _, F).
%% ---- ITANIUM NAME MANGLING, for what a library header only DECLARES --------------------------
%% libc++ declares `std::__libcpp_verbose_abort(const char *, ...)' and ships its definition in
%% libc++.dylib as `_ZNSt3__122__libcpp_verbose_abortEPKcz'. This compiler emits every name it DEFINES
%% unmangled -- its own C-shaped symbols, and nothing else knows them -- but a name it only CALLS must be
%% the one the library exports. So a function that a library header declares and never defines, and that
%% is not `extern "C"', is called by its Itanium name: _ZN, the namespace path (St for std), the name
%% length-prefixed, E, then the parameters.
%% WHAT IS NOT MANGLED, and stays its plain name so the linker says so rather than a wrong symbol: a
%% class-typed parameter (this compiler's class names are its own mangling, not C++'s), a type no code
%% below encodes, and ANY signature whose substitutable components repeat -- Itanium writes the second
%% occurrence of a component as S_, S0_ ... and a straight re-encoding would be a different symbol.
cpp_mangled_name(F, Ps, Name) :-
    atom(F), \+ cpp_c_name(F), '$cpp_fn'(F, _, Ps, no, decl(_, V)),
    cpp_hdr_ns(F, Path), Path = [_|_],
    cpp_ita_function(Path, [], F, [], Ps, V, Name).
%% ---- THE ITANIUM MANGLER, ITS SECOND HALF (0.73): substitutions, nested names, template instances ----------
%% What 0.61 spelled -- a free function's `_ZN' + namespace + name + `E' + builtin parameters, refusing any
%% repeat -- is spelled here with the ABI's SUBSTITUTION TABLE threaded through: every prefix, every nested name
%% and every non-builtin type is a candidate in the order it is met, and its second occurrence is `S_', `S0_',
%% `S1_' ... (base 36 past the first). A class is a NESTED NAME, `N <prefix> <len>name E' (`St' for std, never a
%% candidate itself; `St3__1' is one); a template instance a `<len>name I <args> E' whose template-name prefix and
%% whose template-id are candidates in turn; a member's own nested name is the class chain as a PREFIX, its levels
%% candidates, then the member. libc++'s own symbols are the test: `_ZNSt3__114__num_put_base18__identify_paddingE
%% PcS1_RKNS_8ios_baseE' (the second `Pc' is `S1_', the class-typed parameter `RKNS_8ios_baseE') and
%% `_ZNKSt3__15ctypeIcE9do_narrowEcc' (`K' for a const method, the specialization as a prefix). What this compiler
%% has no spelling for -- a function pointer, a non-type template argument, an operator, an array -- FAILS, and the
%% member keeps its own name for the linker to name.
cpp_ita_function([std], [], F, _, Ps, V, Name) :- !,                                       % a function directly in std is UNSCOPED: `_ZSt19uncaught_exceptionsv', no N...E
    cpp_ita_member_name(F, MText), cpp_ita_params(Ps, V, [], ParamText, _), atomic_list_concat(['_ZSt', MText, ParamText], Name).
cpp_ita_function(Path, Chain, F, Qs, Ps, V, Name) :-
    ( memberchk(const, Qs) -> CV = 'K' ; CV = '' ),
    cpp_ita_prefix(Path, Chain, [], PText, Subs1),
    cpp_ita_member_name(F, MText),
    cpp_ita_params(Ps, V, Subs1, ParamText, _),
    atomic_list_concat(['_ZN', CV, PText, MText, 'E', ParamText], Name).
cpp_ita_member_name('$ctor', 'C1') :- !.
cpp_ita_member_name('$dtor', 'D1') :- !.
cpp_ita_member_name(F, T) :- atom(F), atom_length(F, L), atomic_list_concat([L, F], T).
%% the prefix: the namespace path, then the class chain (plain(Name) or inst(Name, Args) per level), each level a
%% candidate once complete; a level already in the table replaces everything spelled so far by its code
cpp_ita_prefix(Path, Chain, Subs0, Text, Subs) :-
    cpp_ita_ns(Path, '', '', Subs0, C0, T0, Subs1),
    cpp_ita_chain(Chain, C0, T0, Subs1, _, Text, Subs).
cpp_ita_ns([], C, T, Subs, C, T, Subs).
cpp_ita_ns([std|Ns], '', '', Subs0, C, T, Subs) :- !, cpp_ita_ns(Ns, 'St', 'St', Subs0, C, T, Subs).   % `St' abbreviates std, and is no candidate
cpp_ita_ns([N|Ns], C0, T0, Subs0, C, T, Subs) :- atom(N), atom_length(N, L), atomic_list_concat([C0, L, N], C1), cpp_ita_level(C1, T0, L, N, Subs0, T1, Subs1), cpp_ita_ns(Ns, C1, T1, Subs1, C, T, Subs).
%% one level of a prefix: its canonical text C1 is the key; known, its code stands for the whole prefix so far
cpp_ita_level(C1, T0, L, N, Subs0, T1, Subs1) :-
    (   cpp_ita_sub(C1, Subs0, Code) -> T1 = Code, Subs1 = Subs0
    ;   atomic_list_concat([T0, L, N], T1), cpp_ita_note(C1, Subs0, Subs1) ).
cpp_ita_chain([], C, T, Subs, C, T, Subs).
cpp_ita_chain([plain(N)|Ls], C0, T0, Subs0, C, T, Subs) :- atom_length(N, L), atomic_list_concat([C0, L, N], C1), cpp_ita_level(C1, T0, L, N, Subs0, T1, Subs1), cpp_ita_chain(Ls, C1, T1, Subs1, C, T, Subs).
cpp_ita_chain([inst(N, Args)|Ls], C0, T0, Subs0, C, T, Subs) :-
    atom_length(N, L), atomic_list_concat([C0, L, N], C1), cpp_ita_level(C1, T0, L, N, Subs0, T1, Subs1),   % the template-name prefix, a candidate
    cpp_ita_targs(Args, Subs1, ACanon, AText, Subs2),
    atomic_list_concat([C1, 'I', ACanon, 'E'], C2),
    (   cpp_ita_sub(C2, Subs2, Code) -> T2 = Code, Subs3 = Subs2
    ;   atomic_list_concat([T1, 'I', AText, 'E'], T2), cpp_ita_note(C2, Subs2, Subs3) ),                 % the template-id, a candidate
    cpp_ita_chain(Ls, C2, T2, Subs3, C, T, Subs).
cpp_ita_targs([], Subs, '', '', Subs).
cpp_ita_targs([A|As], Subs0, Canon, Text, Subs) :- cpp_ita_type(A, Subs0, C1, T1, Subs1), cpp_ita_targs(As, Subs1, C2, T2, Subs), atom_concat(C1, C2, Canon), atom_concat(T1, T2, Text).
%% the parameters: `v' for none, `z' for the ellipsis
cpp_ita_params([], false, Subs, v, Subs) :- !.
cpp_ita_params(Ps, V, Subs0, Text, Subs) :- cpp_ita_ptypes(Ps, Subs0, T0, Subs), ( V == true -> atom_concat(T0, z, Text) ; Text = T0 ).
cpp_ita_ptypes([], Subs, '', Subs).
cpp_ita_ptypes([P|Ps], Subs0, Text, Subs) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, cpp_ita_type(PT, Subs0, _, T1, Subs1), cpp_ita_ptypes(Ps, Subs1, T2, Subs), atom_concat(T1, T2, Text).
cpp_ita_ptypes([_|Ps], Subs0, Text, Subs) :- cpp_ita_ptypes(Ps, Subs0, Text, Subs).
%% a type: its canonical spelling (the key) and its spelling with substitutions; a builtin is no candidate, and
%% each layer over one -- pointer, reference, const -- is a candidate of its own, the inner first
cpp_ita_type(T0, Subs0, Canon, Text, Subs) :- ccl_resolve_type(T0, T), cpp_ita_type_(T, Subs0, Canon, Text, Subs).
cpp_ita_type_(base(Q, S), Subs0, Canon, Text, Subs) :- cpp_mangle_basic(S, B), !,
    ( memberchk(const, Q) -> atom_concat('K', B, Canon), cpp_ita_wrap(Canon, B, Subs0, Text, Subs) ; Canon = B, Text = B, Subs = Subs0 ).
cpp_ita_type_(base(Q, [typedef(N)]), Subs0, Canon, Text, Subs) :- atom(N), cpp_ita_class(N, Subs0, C0, T0, Subs1), !,
    ( memberchk(const, Q) -> atom_concat('K', C0, Canon), cpp_ita_wrap(Canon, T0, Subs1, Text, Subs) ; Canon = C0, Text = T0, Subs = Subs1 ).
cpp_ita_type_(base(Q, [struct(N, _)]), Subs0, Canon, Text, Subs) :- atom(N), cpp_ita_type_(base(Q, [typedef(N)]), Subs0, Canon, Text, Subs).
cpp_ita_type_(base(Q, [class(_, N, _, _)]), Subs0, Canon, Text, Subs) :- atom(N), cpp_ita_type_(base(Q, [typedef(N)]), Subs0, Canon, Text, Subs).
cpp_ita_type_(ptr(Q, T), Subs0, Canon, Text, Subs) :- cpp_ita_type(T, Subs0, C0, T0, Subs1), atom_concat('P', C0, C1), cpp_ita_wrap(C1, T0, Subs1, T1, Subs2),
    ( memberchk(const, Q) -> atom_concat('K', C1, Canon), cpp_ita_wrap(Canon, T1, Subs2, Text, Subs) ; Canon = C1, Text = T1, Subs = Subs2 ).
cpp_ita_type_(ref(_, T), Subs0, Canon, Text, Subs) :- cpp_ita_type(T, Subs0, C0, T0, Subs1), atom_concat('R', C0, Canon), cpp_ita_wrap(Canon, T0, Subs1, Text, Subs).
cpp_ita_type_(rref(_, T), Subs0, Canon, Text, Subs) :- cpp_ita_type(T, Subs0, C0, T0, Subs1), atom_concat('O', C0, Canon), cpp_ita_wrap(Canon, T0, Subs1, Text, Subs).
%% a layer's spelling: the whole known -> its code; else the layer's letter over the inner spelling, and noted
cpp_ita_wrap(Canon, Inner, Subs0, Text, Subs) :-
    (   cpp_ita_sub(Canon, Subs0, Code) -> Text = Code, Subs = Subs0
    ;   sub_atom(Canon, 0, 1, _, Letter), atom_concat(Letter, Inner, Text), cpp_ita_note(Canon, Subs0, Subs) ).
%% a class as a TYPE: its nested name `N <prefix> <chain> E' (`St<len>name' for a name directly in std), the whole a
%% candidate; the class must be a library's, with a namespace path (cpp_class_scope)
cpp_ita_class(N, Subs0, Canon, Text, Subs) :-
    cpp_class_scope(N, Path, Chain),
    cpp_ita_ns(Path, '', '', Subs0, C0, T0, Subs1),
    (   Path == [std], Chain = [plain(Last)]
    ->  atom_length(Last, L), atomic_list_concat(['St', L, Last], Canon), ( cpp_ita_sub(Canon, Subs1, Code) -> Text = Code, Subs = Subs1 ; Text = Canon, cpp_ita_note(Canon, Subs1, Subs) )
    ;   cpp_ita_chain_type(Chain, C0, T0, Subs1, C1, T1, Subs2),
        atomic_list_concat(['N', C1, 'E'], Canon),
        ( cpp_ita_sub(Canon, Subs2, Code) -> Text = Code, Subs = Subs2 ; atomic_list_concat(['N', T1, 'E'], Text), cpp_ita_note(Canon, Subs2, Subs) ) ).
%% the chain of a TYPE: every level but the last is a prefix candidate; the last is the type's own (noted whole above)
cpp_ita_chain_type([L], C0, T0, Subs0, C, T, Subs) :- !, cpp_ita_last_level(L, C0, T0, Subs0, C, T, Subs).
cpp_ita_chain_type([L|Ls], C0, T0, Subs0, C, T, Subs) :- cpp_ita_chain([L], C0, T0, Subs0, C1, T1, Subs1), cpp_ita_chain_type(Ls, C1, T1, Subs1, C, T, Subs).
cpp_ita_last_level(plain(N), C0, T0, Subs, C, T, Subs) :- atom_length(N, L), atomic_list_concat([C0, L, N], C), atomic_list_concat([T0, L, N], T).
cpp_ita_last_level(inst(N, Args), C0, T0, Subs0, C, T, Subs) :-
    atom_length(N, L), atomic_list_concat([C0, L, N], C1), cpp_ita_level(C1, T0, L, N, Subs0, T1, Subs1),   % the template-name prefix IS a candidate
    cpp_ita_targs(Args, Subs1, ACanon, AText, Subs), atomic_list_concat([C1, 'I', ACanon, 'E'], C), atomic_list_concat([T1, 'I', AText, 'E'], T).
%% the substitution table: a key's code by its position, S_ then S0_ S1_ ... in base 36
cpp_ita_sub(Key, Subs, Code) :- cpp_ita_index(Subs, Key, 0, I), cpp_ita_code(I, Code).
cpp_ita_index([K|_], K, I, I) :- !.
cpp_ita_index([_|Ks], K, I0, I) :- I1 is I0 + 1, cpp_ita_index(Ks, K, I1, I).
cpp_ita_code(0, 'S_') :- !.
cpp_ita_code(I, Code) :- I1 is I - 1, cpp_base36(I1, D), atomic_list_concat(['S', D, '_'], Code).
cpp_base36(N, D) :- N < 36, !, cpp_digit36(N, D).
cpp_base36(N, D) :- Q is N // 36, R is N mod 36, cpp_base36(Q, D1), cpp_digit36(R, D2), atom_concat(D1, D2, D).
cpp_digit36(N, D) :- ( N < 10 -> C is 48 + N ; C is 55 + N ), atom_codes(D, [C]).
cpp_ita_note(Key, Subs0, Subs) :- ( memberchk(Key, Subs0) -> Subs = Subs0 ; append(Subs0, [Key], Subs) ).
%% WHERE A LIBRARY CLASS LIVES: its namespace path and its chain of classes from the outermost -- a plain class, a
%% nested one (through '$cpp_enclosing'), a template's instance or specialization by its template and arguments
cpp_class_scope(C, Path, Chain) :- atom(C), cpp_class_scope_(C, Path, Chain).
cpp_class_scope_(C, Path, Chain) :- nb_getval('$cpp_enclosing', L), memberchk(C-Enc, L), !, cpp_class_scope_(Enc, Path, Chain0), cpp_last_segment(C, Last), append(Chain0, [plain(Last)], Chain).
cpp_class_scope_(C, Path, [inst(N, Args)]) :- '$cpp_inst'(C, inst(N, Args)), !, cpp_hdr_ns(N, Path), Path = [_|_].
cpp_class_scope_(C, Path, [plain(C)]) :- cpp_hdr_ns(C, Path), Path = [_|_].
cpp_last_segment(C, Last) :- atomic_list_concat(Segs, '.', C), ccl_last(Segs, Last).
cpp_mangle_ns([std|Rest], T) :- !, cpp_mangle_ns_(Rest, R), atom_concat('St', R, T).     % St is std's own abbreviation
cpp_mangle_ns(Path, T) :- cpp_mangle_ns_(Path, T).
cpp_mangle_ns_([], '').
cpp_mangle_ns_([N|Ns], T) :- atom(N), atom_length(N, L), cpp_mangle_ns_(Ns, R), atomic_list_concat([L, N, R], T).
%% the builtin types' codes (the Itanium mangler above spells a class, a pointer, a reference over them)
cpp_mangle_basic(S, v) :- memberchk(void, S), !.
cpp_mangle_basic(S, b) :- ( memberchk(bool, S) ; memberchk('_Bool', S) ), !.
cpp_mangle_basic(S, w) :- memberchk(wchar_t, S), !.
cpp_mangle_basic(S, 'Ds') :- memberchk(char16_t, S), !.
cpp_mangle_basic(S, 'Di') :- memberchk(char32_t, S), !.
cpp_mangle_basic(S, 'Du') :- memberchk(char8_t, S), !.
cpp_mangle_basic(S, C) :- memberchk(char, S), !, ( memberchk(signed, S) -> C = a ; memberchk(unsigned, S) -> C = h ; C = c ).
cpp_mangle_basic(S, C) :- memberchk(short, S), !, ( memberchk(unsigned, S) -> C = t ; C = s ).
cpp_mangle_basic(S, C) :- ccl_count(long, S, 2), !, ( memberchk(unsigned, S) -> C = y ; C = x ).
cpp_mangle_basic(S, C) :- memberchk(long, S), !,
    ( memberchk(double, S) -> C = e ; memberchk(unsigned, S) -> C = m ; C = l ).
cpp_mangle_basic(S, f) :- memberchk(float, S), !.
cpp_mangle_basic(S, d) :- memberchk(double, S), !.
cpp_mangle_basic(S, C) :- ( memberchk(int, S) ; memberchk(signed, S) ; memberchk(unsigned, S) ), !,
    ( memberchk(unsigned, S) -> C = j ; C = i ).
cpp_fn_overloaded(F) :- '$cpp_fn'(F, K1, _, yes, _), '$cpp_fn'(F, K2, _, yes, _), K1 \== K2, !.
%% the overload an argument list names: one whose parameters take it EXACTLY (C++ prefers such a non-template
%% to any template), else the one whose parameters fit best (cpp_pick, the methods')
cpp_fn_exact(F, As, Ps, D) :- cpp_fn_ready(F), length(As, N), '$cpp_fn'(F, _, Ps, _, _), length(Ps, N), cpp_exact_params(Ps, As), !, cpp_fn_defined(F, Ps, D).
cpp_fn_best(F, As, Ps, D) :- cpp_fn_ready(F), length(As, N),
    findall(Ps0, ( '$cpp_fn'(F, _, Ps0, _, O), cpp_fn_arity_fits(Ps0, O, N) ), Cands), Cands \== [],
    cpp_pick(Cands, As, Ps), cpp_fn_defined(F, Ps, D).
%% an ELLIPSIS takes any number past the named parameters: `__libcpp_verbose_abort(const char *, ...)' is
%% called with a format and its arguments, and the plain arity test found no candidate for those calls
cpp_fn_arity_fits(Ps, O, N) :- cpp_fn_variadic(O), !, cpp_required(Ps, Min), N >= Min.
cpp_fn_arity_fits(Ps, _, N) :- cpp_arity_fits(Ps, N).
cpp_fn_variadic(decl(_, true)).
cpp_fn_variadic(lazy(function(_, _, _, _, _, true, _))).
cpp_fn_ready(F) :- atom(F), '$cpp_fn'(F, _, _, _, _), !.
cpp_fn_ready(F) :- atom(F), cpp_hdr_item(F, _), cpp_hdr_load(F), '$cpp_fn'(F, _, _, _, _), !.   % a LIBRARY header's functions of the name, registered on the first ask: `std::__throw_length_error'
%% is defined inline in the header and emitted where it is called, so the name must be loaded here. A load that
%% REFUSES throws through (it marks the name loaded before it registers it, so a refusal swallowed here would
%% leave the name marked and its templates unregistered ever after -- std::swap linked to nothing for a turn).
cpp_fn_defined(F, Ps, D) :- ( '$cpp_fn'(F, _, Ps, yes, _) -> D = yes ; D = no ).
cpp_exact_params([], []).
cpp_exact_params([P|Ps], [A|As]) :- ( P = param(T, _) ; P = param(T, _, _) ), cpp_arg_exact(T, A), cpp_exact_params(Ps, As).
cpp_arg_exact(PT, A) :- ccl_type_of(A, AT), AT \== unknown,
    ccl_unref(PT, PT1), ccl_unref(AT, AT1), ccl_resolve_type(PT1, R1), ccl_resolve_type(AT1, R2),
    cpp_bare_type(R1, B1), cpp_bare_type(R2, B2), B1 == B2.
cpp_bare_type(base(_, S), base([], S)) :- !.
cpp_bare_type(T, T).
cpp_free_call(F, Ps, D, As, call(id(Name), As2)) :-
    cpp_fn_name(F, Ps, D, Name), cpp_use_fn(F, Ps, Name), cpp_use_mangled(F, Ps, Name),
    cpp_fill_defaults(Name, As, As1), cpp_ref_args(Name, As1, As2).
%% a mangled name is nothing this compiler defines, so the unit needs its PROTOTYPE: the item the lowering
%% takes a `declare' line from, emitted once, and the symbol table's entry so the call has a type
cpp_use_mangled(F, _, Name) :- Name == F, !.
cpp_use_mangled(F, Ps, Name) :-
    (   '$cpp_fn'(F, _, Ps, no, decl(Ret, V)), \+ cpp_instance_done(Name)
    ->  cpp_instance_note(Name, mangled), ccl_declare(Name, fn(Ret, Ps, V)),
        cpp_as_lib(yes, cpp_add_instance_items([function(0, extern, Ret, Name, Ps, V, none)]))
    ;   true ).
%% A LIBRARY HEADER'S FREE FUNCTION IS EMITTED WHERE IT IS CALLED, as its classes and its templates already are:
%% libc++ writes ten `__convert_to_integral' overloads, one per integer type, and a program calls one -- the others
%% would drag in what this compiler cannot lower (`__int128_t') for nothing.
cpp_use_fn(F, Ps, Name) :-
    (   '$cpp_fn'(F, _, Ps, yes, lazy(function(L, Sto, Ret, N, Ps2, V, Body))), \+ cpp_instance_done(Name), \+ cpp_making(Name)
    ->  nb_getval('$cpp_making', M0), nb_setval('$cpp_making', [Name|M0]),                % IN PROGRESS while it emits, NOTED after (0.69's rule, in its fourth place): noted first, an emission a candidate's check abandoned left the name behind, and the real call to `__convert_to_integral' had no declaration and no type
        (   catch(cpp_as_lib(yes, ( cpp_isolated(cpp_item(function(L, Sto, Ret, N, Ps2, V, Body), Items)), cpp_add_instance_items(Items) )), E, ( nb_setval('$cpp_making', M0), throw(E) ))
        ->  nb_setval('$cpp_making', M0), cpp_instance_note(Name, hdr)
        ;   nb_setval('$cpp_making', M0), cpp_refuse(0, function_not_emitted(Name)) )   % never silently: the call would be emitted and the definition not, and the linker would say so
    ;   true ).
cpp_register_([template(_, TPs, concept(_, N, E))|Is]) :- !, nb_getval('$cpp_concepts', Cs), nb_setval('$cpp_concepts', [N-concept(TPs, E)|Cs]), cpp_register_(Is).   % C++20
cpp_register_([concept(_, N, E)|Is]) :- !, nb_getval('$cpp_concepts', Cs), nb_setval('$cpp_concepts', [N-concept([], E)|Cs]), cpp_register_(Is).
cpp_register_([template(_, TPs, Item)|Is]) :- !,
    (   cpp_mdef_item(Item, C, Pattern, Member) -> cpp_mdef_put(C, TPs, Pattern, Member)                                           % a member DEFINED out of its class, by the class's name
    ;   cpp_spec_name(Item, N, Pattern) -> cpp_spec_put(N, TPs, Pattern, Item)                                                     % a partial or full specialization, by its pattern
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
cpp_register_([include(_, _, file(_, summary, summary(F)))|Is]) :- !, cpp_load_ast(F), cpp_register_(Is).              % served from its summary: its items from the AST file beside it (ccl_ast_write)
cpp_load_ast(F) :- ccl_ast_file(F, A), ( exists_file(A) -> ensure_loaded(A) ; true ).
cpp_hdr_item(N, I) :- '$cpp_hdr'(N, I).
cpp_hdr_item(N, I) :- '$cpp_hdr_ast'(N, I).
cpp_register_([include(_, _, file(_, _, unit(Js)))|Is]) :- !, cpp_register_header(Js), cpp_register_(Is).   % a header read whole (the program's own): its classes and templates
%% '$cpp_hdr'(Name, Item): facts (found by name in microseconds; a global would copy the header at every read)
cpp_index_header(Js) :- cpp_index_items([], Js).
%% the NAMESPACE PATH is kept beside each indexed name ('$cpp_hdr_ns'), since a function a header only
%% DECLARES must be called by the symbol the shipped library exports, which is its qualified name mangled
%% (cpp_mangled_name/3); `extern "C"' is the path `c', which never mangles
cpp_index_items(_, []).
cpp_index_items(Path, [namespace(_, N, Js)|Is]) :- !, ( atom(N), N \== anon -> append(Path, [N], P1) ; P1 = Path ), cpp_index_items(P1, Js), cpp_index_items(Path, Is).
cpp_index_items(Path, [extern_c(_, Js)|Is]) :- !, cpp_index_items(c, Js), cpp_index_items(Path, Is).
cpp_index_items(Path, [I|Is]) :- ( cpp_index_name(I, N) -> assertz('$cpp_hdr'(N, I)), cpp_note_hdr_ns(N, Path) ; true ), cpp_index_items(Path, Is).
cpp_note_hdr_ns(N, Path) :- ( '$cpp_hdr_ns'(N, _) -> true ; assertz('$cpp_hdr_ns'(N, Path)) ).
cpp_hdr_ns(N, P) :- '$cpp_hdr_ns'(N, P), !.
cpp_hdr_ns(N, P) :- '$cpp_hdr_ast_ns'(N, P), !.
cpp_index_name(template(_, _, I), N) :- !, ( cpp_mdef_item(I, N, _, _) -> true ; cpp_spec_name(I, N, _) -> true ; cpp_template_name(I, N) ).
cpp_index_name(declare(_, base(_, [class(_, N0, _, Ms)])), N) :- Ms \== none, cpp_class_item_name(N0, N).   % a forward declaration declares nothing to register: the DEFINITION carries the name (the struct clause below always said so)
cpp_index_name(declare(_, base(_, [struct(N, Ms)])), N) :- atom(N), Ms \== none.
cpp_index_name(function(_, _, _, N, _, _, B), N) :- atom(N), B \== none.
cpp_index_name(function(_, _, _, N, _, _, none), N) :- atom(N).                          % a DECLARATION: nothing to register, but its name, its parameters and its namespace are what a call must mangle
cpp_index_name(function(_, _, _, scoped(Path, _), _, _, B), C) :- B \== none, cpp_mdef_class(Path, C, _), atom(C).   % a member DEFINED OUT OF ITS CLASS, by the class's name: `inline ios_base::fmtflags ios_base::flags() const { ... }' -- its body is here, hidden from the ABI, and the class's own list holds only its declaration
cpp_index_name(declaration(_, _, _, [var(N, fn(_, _, _), none)|_]), N) :- atom(N).
cpp_index_name(declaration(_, extern, _, [var(N, T, none)|_]), N) :- atom(N), \+ T = fn(_, _, _).   % an extern GLOBAL the shipped library defines: `extern ostream cout;'
cpp_index_name(declaration(_, Sto, _, [var(N, T, Init)|_]), N) :- atom(N), Sto \== extern, Init \== none, \+ T = fn(_, _, _).   % an INLINE VARIABLE the header defines: `inline constexpr const char __base_2_lut[64] = { ... }', emitted by the program that names it
cpp_index_name(ctor_def(_, C, _, _, _, _), C) :- atom(C).
cpp_index_name(dtor_def(_, C, _, _), C) :- atom(C).
cpp_index_name(ctor_def(_, scoped(Path, _), _, _, _, _), C) :- cpp_mdef_class(Path, C, _), atom(C).   % a NESTED class's, by the enclosing class's name
cpp_index_name(dtor_def(_, scoped(Path, _), _, _), C) :- cpp_mdef_class(Path, C, _), atom(C).
%% a name the registries do not have: the header's items of that name, registered now (a class as a lazy one)
cpp_hdr_load(N) :- atom(N), cpp_hdr_item(N, _), \+ ( nb_getval('$cpp_hdr_loaded', Ls), memberchk(N, Ls) ), !,
    cpp_spend(load(N)), nb_getval('$cpp_hdr_loaded', Ls0), nb_setval('$cpp_hdr_loaded', [N|Ls0]), assertz('$cpp_lib'(N)),
    findall(I, cpp_hdr_item(N, I), Items), cpp_note_hdr_fns(Items), cpp_note_hdr_mdefs(Items),
    cpp_where(load(N), cpp_as_lib(yes, cpp_isolated(cpp_register_lazy(Items)))).   % AT FILE SCOPE: a load met inside a function's body walk declared the header's functions into that function's open frame -- ccl_declare takes the innermost -- and they were gone with it: `__convert_to_integral.unsigned_long' declared in one walk, undeclared at the next call, its type unknown, and `_Size' undeducible
%% the out-of-class definitions of the batch, noted BEFORE any class of it registers (the class item comes first in
%% the header, its members' bodies after it), so the class takes them as its members' bodies (cpp_lazy_class)
cpp_note_hdr_mdefs([]).
cpp_note_hdr_mdefs([I|Is]) :- ( I \= template(_, _, _), cpp_mdef_item(I, C, Pat, Member) -> cpp_mdef_put(C, [], Pat, Member) ; true ), cpp_note_hdr_mdefs(Is).
%% THE LIBRARY'S FUNCTIONS ARE COMPILED AS C++ HAS THEM, NOT CHECKED: libc++'s bodies keep raw pointers by their own
%% discipline (a vector's begin, end and capacity; a swap of two pointers through references), which the safe part
%% would refuse at every line -- so a function that comes from a library header (an inline one, a lazy class's
%% member, an instance of the header's template, whatever such a walk emits) is marked '$cpp_libfn'(Name) and the
%% check skips it, while the program's own functions, its own templates' instances included, wherever they are
%% instantiated from, are checked as always. The lowering lowers both.
cpp_as_lib(Flag, Goal) :- nb_getval('$cpp_in_lib', Was), nb_setval('$cpp_in_lib', Flag), ( catch(Goal, E, ( nb_setval('$cpp_in_lib', Was), throw(E) )) -> nb_setval('$cpp_in_lib', Was) ; nb_setval('$cpp_in_lib', Was), fail ).
cpp_lib_origin(N, Flag) :- ( '$cpp_lib'(N) -> Flag = yes ; Flag = no ).
cpp_lib_class(C) :- ( cpp_is_lazy(C) -> true ; '$cpp_lib'(C) -> true ; '$cpp_inst'(C, inst(N, _)), '$cpp_lib'(N) ).
cpp_library_function(Name) :- catch('$cpp_libfn'(Name), _, fail).
cpp_register_lazy([]).
cpp_register_lazy([declare(L, base(_, [class(K, C0, Bases, Ms)]))|Is]) :- !,
    ( cpp_class_item_name(C0, C) -> cpp_class_encloses(C0, C), cpp_lazy_class(L, K, C, Bases, Ms) ; true ), cpp_register_lazy(Is).
cpp_register_lazy([declare(L, base(_, [struct(C, Ms)]))|Is]) :- !, cpp_lazy_class(L, struct, C, [], Ms), cpp_register_lazy(Is).
cpp_register_lazy([function(_, _, _, scoped(_, _), _, _, Body)|Is]) :- Body \== none, !, cpp_register_lazy(Is).   % a member defined out of its class: noted already (cpp_note_hdr_mdefs)
cpp_register_lazy([ctor_def(_, _, _, _, _, _)|Is]) :- !, cpp_register_lazy(Is).
cpp_register_lazy([dtor_def(_, _, _, _)|Is]) :- !, cpp_register_lazy(Is).
cpp_register_lazy([function(L, Sto, Ret, N, Ps, V, Body)|Is]) :- atom(N), Body \== none, !,      % an inline function of the header: declared now, emitted (linkonce) where it is called
    cpp_register_([function(L, Sto, Ret, N, Ps, V, Body)]), cpp_register_lazy(Is).
cpp_register_lazy([declaration(L, extern, _, Vs)|Is]) :- forall(( member(var(N, T, none), Vs), \+ T = fn(_, _, _) ), cpp_lazy_var(L, N, T)), !, cpp_register_lazy(Is).
cpp_register_lazy([declaration(L, Sto, _, Vs)|Is]) :- Sto \== extern, member(var(_, T, Init), Vs), Init \== none, \+ T = fn(_, _, _), !,
    forall(( member(var(N, T0, Init0), Vs), Init0 \== none ), cpp_lazy_inline_var(L, N, T0, Init0)), cpp_register_lazy(Is).
%% A HEADER'S INLINE VARIABLE -- C++17's, DEFINED in the header with its initializer, which no shipped library
%% exports: libc++'s digit tables, `__digits_base_10', `__pow10_64' -- is emitted by the program that names it, a
%% `linkonce' global as a header's inline function is emitted where it is called, under its own name; the
%% initializer's items desugared (constants, folded). Named through the summary alone it was an `external global'
%% and the link named five of them.
cpp_lazy_inline_var(L, N, T0, Init0) :- \+ cpp_instance_done(N), !, cpp_instance_note(N, inline_var),
    cpp_type(T0, T), cpp_init_expr(Init0, Init), ccl_declare(N, T), nb_getval('$cpp_gvar', G), nb_setval('$cpp_gvar', [N-N|G]),
    cpp_as_lib(yes, cpp_add_instance_items([declaration(L, linkonce, T, [var(N, T, Init)])])).
cpp_lazy_inline_var(_, _, _, _).
cpp_init_expr(init(Items), init(Items1)) :- !, findall(item(D, V1), ( member(item(D, V0), Items), cpp_init_expr(V0, V1) ), Items1).
cpp_init_expr(E0, E) :- cpp_expr(none, E0, E).
cpp_register_lazy([I|Is]) :- cpp_register_(I), cpp_register_lazy(Is).
%% A LIBRARY HEADER'S EXTERN GLOBAL is DEFINED IN THE SHIPPED BINARY and reached by the symbol that binary
%% exports, as a declared-only function has been since 0.61: `extern ostream cout;' inside `std::__1' is
%% `_ZNSt3__14coutE' -- `_ZN', the namespace path, the length-prefixed name, `E', and no parameters. Its name HERE
%% is that symbol, so nothing has to rewrite the call; the declaration is emitted once and the linker finds it.
cpp_lazy_var(L, N, T0) :- cpp_mangled_var(N, Name), \+ cpp_instance_done(Name), !,
    cpp_instance_note(Name, mangled),
    ( catch(cpp_type(T0, T), _, fail) -> true ; T = T0 ),
    ccl_declare(Name, T), nb_getval('$cpp_gvar', G), nb_setval('$cpp_gvar', [N-Name|G]),
    cpp_as_lib(yes, cpp_add_instance_items([declaration(L, extern, T, [var(Name, T, none)])])).
cpp_lazy_var(_, _, _).
cpp_mangled_var(N, Name) :- atom(N), \+ cpp_c_name(N), cpp_hdr_ns(N, Path), Path = [_|_],
    cpp_mangle_ns(Path, NsText), atom_length(N, NL), atomic_list_concat(['_ZN', NsText, NL, N, 'E'], Name).
%% ... and the name a program writes is that symbol, the header's items loaded on the first ask as a function's are
cpp_global_var(N, Name) :- nb_getval('$cpp_gvar', G), memberchk(N-Name, G), !.
cpp_global_var(N, Name) :- atom(N), cpp_hdr_item(N, _), cpp_hdr_load(N), nb_getval('$cpp_gvar', G), memberchk(N-Name, G), !.
cpp_register_(I) :- \+ ( I == [] ; I = [_|_] ), !, cpp_register_([I]).
%% a lazy class: registered, its struct emitted, its members emitted as they are first used (the standard's rule for a
%% template's members; a library class's methods are hundreds, a program uses three)
cpp_lazy_class(_, _, _, _, none) :- !.                                                   % `class bad_alloc;': nothing to register or emit
cpp_lazy_class(L, K, C, Bases, Ms0) :-
    ( cpp_class(C, _) -> true
    ; nb_getval('$cpp_lazy', Lz), nb_setval('$cpp_lazy', [C|Lz]),
      cpp_member_defs(C, C, [], Ms0, Ms),                                                 % the members DEFINED out of the class: their bodies, as an instance takes them
      ( cpp_isolated(( cpp_register_class(L, C, Bases, Ms), cpp_item(declare(L, base([], [class(K, C, Bases, Ms)])), Items) )) -> true ; cpp_refuse(L, class_not_emitted(C)) ),
      cpp_add_instance_items(Items) ).
cpp_is_lazy(C) :- nb_getval('$cpp_lazy', Lz), memberchk(C, Lz).
%% A LIBRARY TEMPLATE'S INSTANCE IS LAZY. A class instance used to emit every member function it has, so
%% `std::vector<int> v; v.push_back(1);' compiled vector's hundred members and stopped at the first one this compiler
%% could not take -- `__swap_allocator', reached through a `swap' the program never calls. A library header's plain
%% class already emitted members only as they were named (cpp_use_member); an instance of a library template does so
%% too now, which is what the standard says a template instantiates. The program's OWN templates stay eager: their
%% instances are the program's code and the safe part must see all of it.
cpp_lazy_instance(yes, Name) :- \+ cpp_is_lazy(Name), !, nb_getval('$cpp_lazy', Lz), nb_setval('$cpp_lazy', [Name|Lz]).
cpp_lazy_instance(_, _).
%% a member of a lazy class, first used: its function emitted now
cpp_use_member(C, Name) :-
    (   cpp_is_lazy(C), \+ cpp_instance_done(Name), \+ cpp_making(Name),
        cpp_class(C, cls(Base, _, Ms, _, Defaults, _)), member(M, Ms), cpp_member_mangled(C, M, Name)
    ->  cpp_make_lazy(Name, C, Base, Defaults, M)                                                       % lazy: a header's
    ;   true ).
%% ... and NOTED only once it is EMITTED, as a member template's instance is (cpp_make_member): the emission can
%% run inside another candidate's signature check, whose catch rejects that candidate and leaves the note behind.
%% `std::vector<std::string>' lost `basic_string''s move constructor exactly so.
cpp_make_lazy(Name, C, Base, Defaults, M) :-
    cpp_trace(make_lazy(Name)),                                                                             % which member, for the loop: what a program pulls in is read off these
    nb_getval('$cpp_making', M0), nb_setval('$cpp_making', [Name|M0]),
    (   catch(cpp_as_lib(yes, ( cpp_isolated(cpp_in_class(C, cpp_member_fns([M], C, Base, Defaults, Fns))), cpp_add_instance_items(Fns) )),
              E, ( nb_setval('$cpp_making', M0), throw(E) ))
    ->  nb_setval('$cpp_making', M0), cpp_instance_note(Name, C)
    ;   nb_setval('$cpp_making', M0), cpp_refuse(0, member_not_emitted(Name)) ).
cpp_member_mangled(C, method(_, _, _, M, Ps, _, _), Name) :- cpp_mangle(C, M, Ps, Name).
cpp_member_mangled(C, ctor(_, _, Ps, _, _), Name) :- cpp_mangle(C, C, Ps, Name).
cpp_member_mangled(C, dtor(_, _, Body), Name) :- cpp_dtor_name(C, Body, Name).
%% A DESTRUCTOR A LIBRARY HEADER DECLARES AND THE SHIPPED LIBRARY DEFINES -- `virtual ~ios_base();', `~locale();' --
%% is called by its Itanium name, as a declared-only function is (0.61): `_ZN', the namespace path, the class's
%% nested name (a nested class by its segments, locale::facet), `D1Ev' -- the complete-object destructor, the one a
%% delete calls before its free, and the same code as the base-object one for a class without virtual bases. A
%% template instance's keeps its own name: its body is in the header and compiled here. Two symbols short of a
%% running `std::cout << "hello"', the link named exactly these.
cpp_dtor_name(C, none, Name) :- atom(C), cpp_lib_class(C), cpp_class_scope(C, Path, Chain), catch(cpp_ita_function(Path, Chain, '$dtor', [], [], false, Name), _, fail), !.
cpp_dtor_name(C, _, Name) :- atomic_list_concat([C, '.dtor.0'], Name).
%% a plain class of the library's: no template instance, and nested in none (basic_ostream<char>::sentry is an
%% instance's, its body in the header, its own name kept)
cpp_plain_lib_class(C) :- \+ '$cpp_inst'(C, _), ( nb_getval('$cpp_enclosing', L), memberchk(C-Enc, L) -> cpp_plain_lib_class(Enc) ; true ).
%% a header's items: its templates registered, its classes registered AND emitted into the unit (once), as an instance is
%% (a library header's summary carries names, not bodies: libc++'s templates do not instantiate yet)
cpp_register_header([]).
cpp_register_header([declare(L, base(_, [class(K, C0, Bases, Ms)]))|Is]) :- cpp_class_item_name(C0, C), !,
    (   cpp_class(C, _) -> true
    ;   cpp_class_encloses(C0, C),
        cpp_isolated(( cpp_register_class(L, C, Bases, Ms), cpp_item(declare(L, base([], [class(K, C, Bases, Ms)])), Items) )), cpp_add_instance_items(Items) ),
    cpp_register_header(Is).
cpp_register_header([namespace(_, _, Js)|Is]) :- !, cpp_register_header(Js), cpp_register_header(Is).
cpp_register_header([I|Is]) :- cpp_note_fns([I]), cpp_register_([I]), cpp_register_header(Is).
cpp_register_([]).
cpp_register_([declare(L, base(_, [class(_, C0, Bases, Ms)]))|Is]) :- !,
    ( cpp_class_item_name(C0, C) -> cpp_class_encloses(C0, C), cpp_register_class(L, C, Bases, Ms) ; true ), cpp_register_(Is).
%% A NESTED CLASS DEFINED OUT OF ITS ENCLOSING CLASS -- `class locale::facet : public __shared_count { ... };',
%% which is how libc++ writes its facets, its holder declaring only `class facet;' -- is the class `Enclosing.Nested'
%% under the name the forward declaration already gave the type (cpp_nested_names), and the holder's own types are
%% in scope inside it (cpp_encloses). The path is the classes it is written under; a namespace's segment in it
%% would be taken for one, which the flattened headers never write.
cpp_class_item_name(N, N) :- atom(N), !.
cpp_class_item_name(scoped(Path, N), Name) :- atom(N), atomic_list_concat(Path, '.', P), atomic_list_concat([P, '.', N], Name).
cpp_class_encloses(scoped(Path, _), Name) :- !, atomic_list_concat(Path, '.', Enc), cpp_encloses(Name, Enc).
cpp_class_encloses(_, _).
cpp_register_([function(_, _, Ret, operator(Op), Ps, V, _)|Is]) :- !,
    cpp_free_operator(Op, Ps, Name), cpp_plain_params(Ps, Ps1), ccl_declare(Name, fn(Ret, Ps1, V)), cpp_note_defaults(Name, Ps),
    nb_getval('$cpp_free_ops', Os), nb_setval('$cpp_free_ops', [Name|Os]), cpp_register_(Is).
cpp_register_([function(_, _, Ret, N, Ps, V, Body)|Is]) :- atom(N), !,
    cpp_fn_body_mark(Body, D), cpp_fn_name(N, Ps, D, Name), cpp_note_defaults(Name, Ps),
    ( Name == N -> true ; ccl_declare(Name, fn(Ret, Ps, V)) ),                                     % an overload's own name is not in the table the reader built
    cpp_register_(Is).
cpp_fn_body_mark(none, no) :- !.
cpp_fn_body_mark(_, yes).
cpp_register_([dtor_def(_, C, _, _)|Is]) :- !, nb_getval('$cpp_dtor_defs', Ds), nb_setval('$cpp_dtor_defs', [C|Ds]), cpp_register_(Is).
cpp_register_([namespace(_, _, Js)|Is]) :- !, cpp_register_(Js), cpp_register_(Is).
cpp_register_([extern_c(_, Js)|Is]) :- !, cpp_register_(Js), cpp_register_(Is).
cpp_register_([_|Is]) :- cpp_register_(Is).
cpp_register_class(L, C, Bases, Ms0) :-                                                     % the traces fire only under '$cpp_trace'
    ( cpp_norm_members(Ms0, Ms) -> true ; cpp_refuse(L, members_not_normalized(C)) ),
    %% `C() = default;' IS the implicit default constructor, and declaring it keeps the class default-constructible
    %% where its other constructors would have suppressed it -- libc++'s `union __rep' writes it beside three others,
    %% and a member of that type had nothing to construct with (member_not_constructed).
    ( memberchk(ctor(_, _, [], _, default), Ms0), \+ '$cpp_default_ctor'(C) -> assertz('$cpp_default_ctor'(C)) ; true ),
    cpp_nested_names(L, C, Ms),                                                                  % the NAMES first: a member of a nested type resolves before the nested class exists
    ( cpp_register_class_extras(C, Ms) -> true ; cpp_refuse(L, class_extras(C)) ),
    ( cpp_in_class(C, cpp_register_class_(L, C, Bases, Ms)) -> true ; cpp_refuse(L, class_not_registered(C)) ),   % its own typedefs resolve its members' types
    cpp_nested_classes(L, C, Ms).                                                                % then the nested classes themselves, the enclosing one registered so its own name resolves inside them
%% A NESTED CLASS is a type of the class that holds it (`Plain::Nested' outside, `Nested' within) and a class of its
%% own under the mangled name `Enclosing.Nested'; the enclosing class's typedefs are in scope inside it, as C++ has it
cpp_nested_name(nested(base(_, [class(_, N, _, Ms)])), N, Ms) :- atom(N), Ms \== none.
cpp_nested_name(nested(base(_, [class(N, none)])), N, none) :- atom(N).     % `class facet;' inside its holder: the NAME of a class defined out of it, a type of the holder all the same
cpp_nested_name(nested(base(_, [struct(N, Ms)])), N, Ms) :- atom(N), Ms \== none.
cpp_nested_name(nested(base(_, [union(N, Ms)])), N, Ms) :- atom(N), Ms \== none.     % a nested UNION: a type of the class, no class of its own
%% the TYPE a nested name has: a union's is a union's, or its layout would be a struct's -- libc++'s `__rep' holds
%% the short and the long representation of a string in the same bytes, and as a struct it was their sum
cpp_nested_spec(M, Name, base([], [union(Name, none)])) :- M = nested(base(_, [union(_, _)])), \+ cpp_nested_union_class(M), !.
cpp_nested_spec(_, Name, base([], [typedef(Name)])).       % a union-CLASS is named as any class is; its tag carries the union marker
cpp_nested_names(L, C, Ms) :-
    forall( ( member(M, Ms), cpp_nested_name(M, N, _) ),
            ( atomic_list_concat([C, '.', N], Name), cpp_nested_spec(M, Name, Spec), nb_getval('$cpp_class_types', L0), nb_setval('$cpp_class_types', [C-N-Spec|L0]),
              ( '$cpp_nested'(Name, _, _, _, _) -> true ; assertz('$cpp_nested'(Name, L, C, N, M)) ) ) ),
    forall( ( member(M, Ms), cpp_nested_enum(C, M, N, Name, Spec) ),
            ( nb_getval('$cpp_class_types', E0), nb_setval('$cpp_class_types', [C-N-base([], [typedef(Name)])|E0]),
              cpp_enum_members(Spec, Es), ccl_note_tag(Name, Es) ) ).                            % in the tag table AT ONCE: a member's type names it while the class is being declared
cpp_nested_classes(L, C, Ms) :- forall( ( member(M, Ms), cpp_nested_name(M, N, NMs), NMs \== none ), cpp_nested_class(L, C, N, NMs, M) ),
    forall( ( member(M, Ms), cpp_nested_enum(C, M, _, Name, Spec) ), cpp_nested_enum_item(L, Name, Spec) ).
%% A NESTED ENUM is a type of the class that holds it, as a nested class is: `ios_base::seekdir', which libc++'s
%% basic_streambuf writes in three of its methods and which refused as no_member_type -- only a typedef, a nested
%% class and a nested union were class-scope types. The enum is ONE TAG at file scope under the mangled name
%% `Enclosing.Name' and no class of its own; its enumerators keep their own names, as every enum's do here.
cpp_nested_enum(C, nested(base(_, [enum(N, Es)])), N, Name, enum(Name, Es)) :- atom(N), is_list(Es), atomic_list_concat([C, '.', N], Name).
cpp_nested_enum(C, nested(base(_, [enum_class(N, Es)])), N, Name, enum_class(Name, Es)) :- atom(N), is_list(Es), atomic_list_concat([C, '.', N], Name).
cpp_enum_members(enum(_, Es), Es).
cpp_enum_members(enum_class(_, Es), Es).
cpp_nested_enum_item(_, Name, _) :- '$cpp_nested_out'(Name), !.
cpp_nested_enum_item(L, Name, Spec) :- assertz('$cpp_nested_out'(Name)), cpp_trace(nested_enum(Name)),
    cpp_add_instance_items([declare(L, base([], [Spec]))]).
%% THE ENCLOSING CLASS'S OWN REGISTRATION CAN ASK FOR A NESTED CLASS: declaring vector's members resolves types that
%% instantiate templates, whose bodies call vector's members, whose bodies name `_ConstructTransaction' -- all before
%% cpp_nested_classes, which comes last so a nested class's own members see the enclosing one registered. So the name
%% is recorded when the TYPE is (cpp_nested_names) and the class is registered on the first ask, once ('$cpp_nesting').
cpp_nested_ready(Name) :- '$cpp_nested'(Name, L, C, N, M), \+ ( nb_getval('$cpp_nesting', Ns), memberchk(Name, Ns) ), !,
    nb_getval('$cpp_nesting', Ns0), nb_setval('$cpp_nesting', [Name|Ns0]),
    cpp_nested_name(M, N, NMs), NMs \== none,
    (   catch(cpp_nested_class(L, C, N, NMs, M), E, ( nb_setval('$cpp_nesting', Ns0), throw(E) ))   % IN PROGRESS while it registers, and no longer after: a registration a candidate's check abandons must not leave the name marked, or every later ask fails silently (0.69's rule)
    ->  nb_setval('$cpp_nesting', Ns0)
    ;   nb_setval('$cpp_nesting', Ns0), fail ).
%% A NESTED UNION is a nested TYPE and no class of its own: it has no methods and no constructors, and its LAYOUT
%% must stay a union's. Its name resolves inside the enclosing class as a nested class's does (cpp_nested_names),
%% and the union itself is emitted once at file scope under the mangled name. libc++'s `basic_string' keeps its
%% short and its long representation in one -- `union __rep' -- and hands it to a template as an argument, where
%% the name did not resolve and the instance came out with no members at all.
%% A NESTED UNION THAT DECLARES A CONSTRUCTOR OR A METHOD is a CLASS whose members share storage -- libc++'s
%% `basic_string::__rep' has four constructors and is how a string is short or long -- so it goes the class's whole
%% road ('$cpp_union' spells its tag and its declaration a union's; ccl_is_union_tag is the one test). One with
%% only data members is a plain union: a type of the enclosing class and nothing more, emitted once.
cpp_nested_union_class(nested(base(_, [union(_, Ms)]))) :- member(M, Ms), ( M = ctor(_, _, _, _, _) ; M = method(_, _, _, _, _, _, _) ), !.
cpp_nested_class(L, C, N, NMs, M) :- M = nested(base(_, [union(_, _)])), \+ cpp_nested_union_class(M), !,
    atomic_list_concat([C, '.', N], Name),
    (   '$cpp_nested_out'(Name) -> true
    ;   assertz('$cpp_nested_out'(Name)), cpp_trace(nested_union(Name)), cpp_encloses(Name, C),
        cpp_isolated(cpp_in_class(C, ( cpp_member_types(NMs, NMs1), ccl_note_tag(Name, NMs1),   % in the tag table AT ONCE: a template argument names it before the unit's items are noted
                       cpp_item(declare(L, base([], [union(Name, NMs1)])), Items) ))),
        cpp_add_instance_items(Items) ).
cpp_nested_class(L, C, N, NMs, M) :- M = nested(base(_, [union(_, _)])), !, atomic_list_concat([C, '.', N], Name),
    (   cpp_class(Name, _) -> true
    ;   ( '$cpp_union'(Name) -> true ; assertz('$cpp_union'(Name)) ), cpp_encloses(Name, C), cpp_trace(nested_union_class(Name)),
        cpp_isolated(( cpp_register_class(L, Name, [], NMs), cpp_item(declare(L, base([], [class(union, Name, [], NMs)])), Items) )),
        cpp_add_instance_items(Items) ).
cpp_nested_class(L, C, N, NMs, M) :-
    atomic_list_concat([C, '.', N], Name), cpp_trace(nested(Name)),
    (   cpp_class(Name, _) -> true
    ;   ( M = nested(base(_, [class(K0, _, Bs0, _)])) -> K = K0, Bases = Bs0 ; K = struct, Bases = [] ),
        cpp_encloses(Name, C),
        ( cpp_is_lazy(C) -> cpp_lazy_instance(yes, Name) ; true ),   % A NESTED CLASS OF A LAZY CLASS IS LAZY: its members come as they are used. Registered eagerly, basic_ostream's `sentry' walked its constructor, which calls flush(), whose body declares a sentry -- the class still mid-registration, so the ask failed and the local was initialized as a plain value
        cpp_isolated(( cpp_register_class(L, Name, Bases, NMs), cpp_item(declare(L, base([], [class(K, Name, Bases, NMs)])), Items) )),
        cpp_add_instance_items(Items) ).
%% which class holds a nested one: its typedefs are in scope inside, INCLUDING the ones it inherits, so the lookup
%% goes to the enclosing class itself (which walks its own bases) rather than a copy of its direct entries
cpp_encloses(Nested, C) :- nb_getval('$cpp_enclosing', L), ( memberchk(Nested-_, L) -> true ; nb_setval('$cpp_enclosing', [Nested-C|L]) ).
cpp_register_class_(L, C, Bases, Ms) :-
    ( Bases = [base(virtual(_), _)|_] -> ( '$cpp_vbase'(C) -> true ; assertz('$cpp_vbase'(C)) ) ; true ),
    (   Bases = [] -> Base = none
    ;   Bases = [base(_, B0)] -> cpp_base_name(B0, Base)
    ;   cpp_extra_bases(L, C, Bases, Base) ),

    ( cpp_split_members(Ms, Data00, Statics, Defaults) -> true ; cpp_refuse(L, members_not_split(C)) ),
    ( cpp_member_types(Data00, Data0) -> true ; cpp_refuse(L, member_types(C)) ),   % each member's type resolved under the class's own typedefs (`pointer __begin_;')
    ( '$cpp_vbase'(C) -> cpp_slots(none, Ms, C, Slots0), cpp_vbase_dtor_slots(Base, Slots0, Slots) ; cpp_slots(Base, Ms, C, Slots) ),   % over a VIRTUAL base the table is the class's own: the shared base keeps its own pointer inside its sub-object
    (   Slots \== [], ( '$cpp_vbase'(C) ; \+ cpp_polymorphic(Base) )      % the class introduces the table: its pointer is a member of its own
    ->  cpp_vt_tag(C, VT), Data = [member(ptr([], base([], [struct(VT, none)])), '$vptr', none)|Data0]
    ;   Data = Data0 ),
    cpp_class_put(C, cls(Base, Data, Ms, Statics, Defaults, Slots)),
    cpp_note_nontrivial(C, Base, Data, Ms, Slots),
    cpp_base_layout(C, Base, Data, Data1),
    ( '$cpp_union'(C) -> Tagged = [union_tag|Data1] ; Tagged = Data1 ), ccl_note_tag(C, Tagged),   % the struct (or UNION) it becomes, in the table at once: its members have types while its methods are walked
    cpp_in_class(C, ( cpp_declare_members(Ms, C), cpp_declare_statics(Statics, C) )).
%% a data member's type as the struct will hold it: the class's typedef resolved (`pointer' is `int *'), a template-id
%% its instance -- so the inference, asked the member's type by a method's body, answers what a call deduces from; a
%% type that does not resolve here stays as written and is refused where it is used
cpp_member_types([], []).
cpp_member_types([member(base(Q, [union(anon, Us0)]), N, I)|Ms], [member(base(Q, [union(anon, Us)]), N, I)|Ns]) :- !, cpp_member_types(Us0, Us), cpp_member_types(Ms, Ns).
cpp_member_types([member(T0, N, I)|Ms], [member(T, N, I)|Ns]) :- !,
    ( catch(cpp_type(T0, T1), error(not_lowered(W), _), ( cpp_trace(member_type_unresolved(N, W)), fail )) -> T = T1 ; T = T0 ), cpp_member_types(Ms, Ns).
cpp_member_types([M|Ms], [M|Ns]) :- cpp_member_types(Ms, Ns).
%% what else a class carries: its member templates (by name; a constructor under `ctor'), its typedefs
%% (`typedef T value_type;', `using x = T;': what a dependent name `C::value_type' resolves to), and the
%% constant initializers of its static members (`static const bool value = true;': what `C::value' folds to)
cpp_register_class_extras(C, Ms) :-
    forall(( member(template(_, TPs, M), Ms), cpp_member_key(M, K) ), cpp_mt_put(C, K, TPs, M)),
    forall(( member(typedef(_, Vs), Ms), member(var(N, T, _), Vs) ), ( nb_getval('$cpp_class_types', L2), nb_setval('$cpp_class_types', [C-N-T|L2]) )),
    forall(( member(member(base(Q, _), N, _), Ms), memberchk(static, Q), member(default_init(N, E), Ms) ), ( nb_getval('$cpp_static_inits', L3), nb_setval('$cpp_static_inits', [C-N-E|L3]) )),
    cpp_class_enums(C, Ms).
%% A CLASS-SCOPE ENUMERATOR is a constant OF THE CLASS, as a static const is -- libc++'s `basic_string' writes its
%% short-string capacity as `enum { __min_cap = (sizeof(__long) - 1) / sizeof(value_type) > 2 ? ... : 2 }' and names
%% it bare in its members and in an array's bound. The value stays RAW, since it is written in the class's own words,
%% and folds where it is used (cpp_fold_static); an implicit one is the previous plus one, an expression like any other.
cpp_class_enums(C, Ms) :- forall(member(nested(base(_, [enum(_, Es)])), Ms), cpp_class_enums_(C, Es, int(0))).
cpp_class_enums_(_, [], _).
cpp_class_enums_(C, [enum_base(_)|Es], Next) :- !, cpp_class_enums_(C, Es, Next).
cpp_class_enums_(C, [enumerator(N, E)|Es], Next) :- !,
    ( E == none -> V = Next ; V = E ),
    nb_getval('$cpp_static_inits', L), nb_setval('$cpp_static_inits', [C-N-V|L]),
    cpp_class_enums_(C, Es, bin('+', V, int(1))).
cpp_class_enums_(C, [_|Es], Next) :- cpp_class_enums_(C, Es, Next).
cpp_member_key(method(_, _, _, M, _, _, _), M).
cpp_member_key(ctor(_, _, _, _, _), ctor).
cpp_member_key(typedef(_, [var(N, _, _)|_]), N).      % a member ALIAS template: `template <class A, class B> using _Select = ...' inside its class
%% the class whose members are being declared, walked or emitted: a bare name in them may be its typedef
cpp_in_class(C, Goal) :- nb_getval('$cpp_class_ctx', C0), nb_setval('$cpp_class_ctx', C), ( catch(Goal, E, (nb_setval('$cpp_class_ctx', C0), throw(E))) -> nb_setval('$cpp_class_ctx', C0) ; nb_setval('$cpp_class_ctx', C0), fail ).
cpp_class_ctx(C) :- nb_getval('$cpp_class_ctx', C), C \== none.
cpp_class_typedef(C, N, T) :- cpp_class_typedef(C, N, T, _).
%% ... and the class that DEFINES it, whose own typedefs its text is written in: allocator_traits's `pointer' is
%% its base's `__pointer<value_type, allocator_type>', value_type and allocator_type the base's
cpp_class_typedef(C, N, T, C) :- nb_getval('$cpp_class_types', L), memberchk(C-N-T, L), !.
cpp_class_typedef(C, N, T, Def) :- cpp_base_scope(C, B), cpp_class_typedef(B, N, T, Def).
cpp_class_typedef(C, N, T, Def) :- nb_getval('$cpp_enclosing', L), memberchk(C-Enc, L), cpp_class_typedef(Enc, N, T, Def).   % a nested class sees the enclosing one's types, its inherited ones with them
cpp_static_const(C, N, V) :- nb_getval('$cpp_static_inits', L), memberchk(C-N-E, L), !, cpp_fold_static(C, N, E, V).
%% a static const's initializer: a constant as it stands, else DESUGARED in the class's own words -- a detection
%% idiom reads `decltype(__test<_Tp>(nullptr, ...))::value', which is a constant only after the overload is picked.
%% A guard per name, since folding it may ask for it again.
cpp_fold_static(_, _, E, E) :- E = bool(_), !.
cpp_fold_static(_, _, E, int(K)) :- cpp_const_value(E, K), !.
cpp_fold_static(C, N, E, V) :-
    atomic_list_concat(['$cpp_folding:', C, '.', N], K), \+ catch(nb_getval(K, yes), _, fail), nb_setval(K, yes),
    ( catch(cpp_in_class(C, cpp_expr(C, E, E1)), error(not_lowered(_), _), fail) -> true ; E1 = '$none' ),
    nb_setval(K, no), E1 \== '$none',
    ( E1 = bool(_) -> V = E1 ; cpp_const_value(E1, K2) -> V = int(K2) ; fail ).   % a constexpr function's call among them (cpp_const_value)
cpp_static_const(C, N, V) :- cpp_base_scope(C, B), cpp_static_const(B, N, V).       % inherited: is_move_constructible<T>::value is integral_constant's
cpp_static_const(C, N, V) :- nb_getval('$cpp_enclosing', L), memberchk(C-Enc, L), cpp_static_const(Enc, N, V).   % a NESTED class sees the enclosing one's statics, as it sees its types: libc++'s `basic_string::__long' divides by its holder's `__endian_factor'
%% MULTIPLE INHERITANCE where every base after the first is EMPTY -- no data of its own, no slots, nothing to
%% construct or destroy. C++'s empty base optimization puts such a base at offset 0 and gives it no bytes, so it
%% is no sub-object here either: it is a SCOPE, and its typedefs, its nested enums, its statics and its methods
%% are looked up as the first base's are (cpp_base_scope/2). libc++'s `ctype<char> : public locale::facet, public
%% ctype_base' is one of these, and so is every facet's tag base. A second base WITH storage or slots is refused
%% as before: two sub-objects need a `this' adjusted at every call, which nothing here does.
cpp_extra_bases(L, C, [base(_, B0)|Rest], Base) :-
    cpp_base_name(B0, Base),
    (   cpp_empty_bases(Rest, Extras) -> assertz('$cpp_extra'(C, Extras)), cpp_trace(extra_bases(C, Extras))
    ;   cpp_refuse(L, multiple_inheritance(C)) ).
cpp_empty_bases([], []).
cpp_empty_bases([base(_, B0)|Bs], [N|Ns]) :- cpp_base_name(B0, N), cpp_empty_class(N), cpp_empty_bases(Bs, Ns).
cpp_empty_class(N) :- cpp_class(N, cls(B, Data, _, _, _, Slots)), Data == [], Slots == [], ( B == none -> true ; cpp_empty_class(B) ).
%% every class a name is looked up in: the base sub-object first, then the empty bases
cpp_base_scope(C, B) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none.
cpp_base_scope(C, B) :- '$cpp_extra'(C, Bs), member(B, Bs).
%% a base named by a template-id is its instance
cpp_base_name(B, B) :- atom(B), cpp_class(B, _), !.                 % a class's own name
%% ... and an ALIAS of an instance names the INSTANCE, as a parameter's type has since 0.58: libc++ derives its
%% traits from `true_type', which is `integral_constant<bool, true>', and the atom was taken for a class's name
%% (base_not_registered). A name that is neither resolves to itself, as it did.
cpp_base_name(B0, B) :- cpp_type(base([], [typedef(B0)]), T), !, ( T = base(_, [typedef(B1)]), atom(B1) -> B = B1 ; cpp_refuse(0, base_shape(T)) ).   % what came back, when it is not a class's name
cpp_base_name(B0, _) :- cpp_template_id(B0, N, Args), !,                                  % say WHICH half failed: the arguments, or the instantiation
    (   \+ cpp_targ_values(Args, _) -> cpp_refuse(0, base_arguments(N))
    ;   cpp_targ_values(Args, As), \+ cpp_instantiate_class(N, As, _) -> cpp_refuse(0, base_instance(N))
    ;   cpp_refuse(0, base_not_a_class(N)) ).
cpp_base_name(B0, _) :- cpp_refuse(0, base_not_a_class(B0)).
%% the class a scope names: `C', `X<T>' (its instance), `A::B<T>'; a namespace is no class
cpp_scope_class(Path, C) :- ccl_last(Path, P), cpp_path_class(P, C), !.
cpp_scope_class(Path, C) :- cpp_scope_walk(Path, none, C).      % a path of two or more CLASS segments, each named inside the one before: allocator_traits<A>::propagate_on_container_swap::value
cpp_scope_walk([], C, C) :- C \== none.
cpp_scope_walk([S|Ss], none, C) :- !, ( cpp_path_class(S, C1) -> cpp_scope_walk(Ss, C1, C) ; cpp_scope_walk(Ss, none, C) ).   % a namespace's segment names no class: skipped
cpp_scope_walk([S|Ss], Cx, C) :- ( cpp_in_class(Cx, cpp_path_class(S, C1)) -> cpp_scope_walk(Ss, C1, C)
    ;   cpp_class_typedef(Cx, S, _, _) -> fail                                          % a TYPE of the class that is no class ENDS the path: `B::strong::two' names a nested enum's enumerator, and skipping the segment made the static member `B.two'
    ;   cpp_scope_walk(Ss, Cx, C) ).
cpp_path_class(P, P) :- atom(P), cpp_class(P, _), !.
cpp_path_class(P, P) :- atom(P), ccl_tag(P, Ms), Ms \== none, \+ ccl_is_enum_tag(Ms), !.   % a plain struct is a scope too: `NoPtr::pointer' is refused (no_member_type), never a namespace's bare name; an enum's name is not (Color::Green is its enumerator)
cpp_path_class(P, C) :- atom(P), cpp_class_ctx(Cx), cpp_class_typedef(Cx, P, T0, Def), !, cpp_in_class(Def, cpp_type(T0, T)), cpp_class_of_type(T, C).   % __alloc_traits::pointer inside its class
cpp_path_class(decltype(E), C) :- !, ( cpp_class_ctx(Cx) -> true ; Cx = none ),   % `decltype(__test<_Tp>(...))::value': the expression's own class is the scope
    cpp_expr(Cx, E, E1), ccl_type_of(E1, T), T \== unknown, cpp_class_of_type(T, C).
cpp_path_class(tmpl(N, Args0), C) :- !, cpp_targ_values(Args0, Args), cpp_instantiate_type(N, Args, T), cpp_class_of_type(T, C).
cpp_path_class(scoped(_, Last), C) :- cpp_path_class(Last, C).
%% C++23: a method's explicit object parameter (`this Self &self', read as param(this(T), N) first among
%% the parameters) becomes the qualifier explicit_this(N, T), so the parameters are the ones a caller passes
cpp_norm_members(Ms, Ms1) :- cpp_norm_members_(Ms, 0, Ms1).
cpp_norm_members_([], _, []).
cpp_norm_members_([nested(base(_, [class(_, anon, _, Ns)]))|Ms], K, Ms1) :- !,             % the same struct in C++'s own shape, which is what it is with default member initializers
    cpp_norm_members_(Ns, 0, Ns1), cpp_norm_members_(Ms, K, Ms2), append(Ns1, Ms2, Ms1).
cpp_norm_members_([nested(base(_, [struct(anon, Ns)]))|Ms], K, Ms1) :- !,                   % an anonymous struct's members are the class's own (libc++'s compressed pair)
    cpp_norm_members_(Ns, 0, Ns1), cpp_norm_members_(Ms, K, Ms2), append(Ns1, Ms2, Ms1).
cpp_norm_members_([nested(base(_, [union(anon, Ns)]))|Ms], K, [member(base([], [union(anon, Ns1)]), A, none)|Ms1]) :- !,   % an anonymous union: one member, its names reached through it (cpp_data_member)
    K1 is K + 1, atomic_list_concat(['$anon', K1], A), cpp_norm_members_(Ns, 0, Ns1), cpp_norm_members_(Ms, K1, Ms1).
cpp_norm_members_([M|Ms], K, Ms1) :- cpp_member_body(M, B), ( B == delete ; B == default ), !, cpp_norm_members_(Ms, K, Ms1).   % `= delete': not there; `= default': the implicit one
cpp_norm_members_([method(L, Qs, Ret, M, Ps, V, pure)|Ms], K, [method(L, [pure|Qs], Ret, M, Ps, V, none)|Ms1]) :- !, cpp_norm_members_(Ms, K, Ms1).
cpp_norm_members_([method(L, Qs, Ret, M, [param(this(T), N)|Ps], V, Body)|Ms], K, [method(L, [explicit_this(N, T)|Qs], Ret, M, Ps, V, Body)|Ms1]) :- !, cpp_norm_members_(Ms, K, Ms1).
cpp_norm_members_([M|Ms], K, [M|Ms1]) :- cpp_norm_members_(Ms, K, Ms1).
cpp_member_body(method(_, _, _, _, _, _, B), B).
cpp_member_body(ctor(_, _, _, _, B), B).
cpp_member_body(dtor(_, _, B), B).
%% the virtual slots of a class: the base's, an own virtual method (or one
%% that overrides a slot) appended when new, `$dtor' for a virtual destructor
cpp_slots(Base, Ms, C, Slots) :-
    ( Base == none -> S0 = [] ; cpp_class(Base, cls(_, _, _, _, _, S0)) -> true ; cpp_refuse(0, base_not_registered(Base, C)) ),   % never a silent failure: a half-registered class corrupts every later lookup
    cpp_own_slots(Ms, C, S0, Slots).
cpp_own_slots([], _, S, S).
cpp_own_slots([method(_, Qs, Ret, M, Ps, V, _)|Ms], C, S0, S) :-
    length(Ps, K),
    (   ( memberchk(virtual, Qs) ; memberchk(slot(M, K, _, _, _), S0) )
    ->  ( memberchk(slot(M, K, _, _, _), S0) -> S1 = S0 ; cpp_plain_params(Ps, Ps1), cpp_slot_ret(Ret, Ret1), append(S0, [slot(M, K, Ret1, Ps1, V)], S1) )
    ;   S1 = S0 ),
    cpp_own_slots(Ms, C, S1, S).
%% a slot's RESULT type resolved in the class, as its parameters are: the table's struct is written from the slots, and
%% `virtual int_type uflow()' -- basic_streambuf's, a class-scope typedef -- reached the lowering raw there; one that
%% does not resolve stays as written, as it always did
cpp_slot_ret(Ret, Ret1) :- ( catch(cpp_type(Ret, Ret1), error(not_lowered(_), _), fail) -> true ; Ret1 = Ret ).
cpp_own_slots([dtor(_, Qs, _)|Ms], C, S0, S) :- ( memberchk(virtual, Qs) ; memberchk(override, Qs) ), \+ memberchk(slot('$dtor', 0, _, _, _), S0), !,   % virtual by the word, or by `override' (libc++'s `~basic_ostream() override')
    append(S0, [slot('$dtor', 0, base([], [void]), [], false), slot('$dtor_del', 0, base([], [void]), [], false)], S1), cpp_own_slots(Ms, C, S1, S).
%% ... TWO entries for it, the complete-object and the deleting destructor, as the Itanium ABI lays a table out --
%% and it must be laid out so, since a virtual call INTO an object the shipped library made (std::cout's streambuf,
%% its `overflow') indexes that object's own table: with one entry every slot past the destructor was off by one.
%% Both hold the one destructor here; a delete is that call and a free (cpp_destroy).
cpp_own_slots([_|Ms], C, S0, S) :- cpp_own_slots(Ms, C, S0, S).
cpp_polymorphic(C) :- C \== none, cpp_class(C, cls(_, _, _, _, _, Slots)), Slots \== [].
cpp_slot(C, M, K, M) :- cpp_class(C, cls(_, _, _, _, _, Slots)), memberchk(slot(M, K, _, _, _), Slots), !.
%% the class whose table a pointer to C dispatches through: the first polymorphic one up the chain
cpp_vt_owner(C, Owner) :- cpp_class(C, cls(B, _, _, _, _, _)), ( \+ '$cpp_vbase'(C), cpp_polymorphic(B) -> cpp_vt_owner(B, Owner) ; Owner = C ).
%% VIRTUAL INHERITANCE, as the Itanium ABI lays a COMPLETE OBJECT out: the class's own pointer to its own table
%% first, its own members, and the shared base LAST -- `basic_ostream : virtual public basic_ios', where std::cout
%% is the basic_ostream's vptr and then the basic_ios at offset 8 (measured with clang++: 160 = 8 + 152), and
%% every field of it we read sat eight bytes off. The base is still `$base' -- its members, its methods, its
%% constructor and destructor are reached as through any base -- only placed after the class's own. A class
%% deriving FURTHER from one keeps that layout inside its own sub-object, where the ABI would move the shared
%% base to the end of the most-derived object: right for every object the library makes and for the program's
%% own, and wrong only where the library's code would look into such a derived object of the program's, which
%% nothing does yet. Two classes sharing one virtual base (basic_iostream) are not laid out here at all: the
%% first base is taken, the second refused as multiple_inheritance unless empty.
%% ... and a destructor is virtual BY INHERITANCE: over a virtual base the shared table is not this class's, so a
%% virtual destructor of the base's makes the class's own slots, first, whether the class declares one or not (an
%% implicit one is emitted then: cpp_implicit_dtor_needed)
cpp_vbase_dtor_slots(Base, S0, S) :-
    (   Base \== none, \+ memberchk(slot('$dtor', 0, _, _, _), S0), cpp_class(Base, cls(_, _, _, _, _, BS)), memberchk(slot('$dtor', 0, _, _, _), BS)
    ->  S = [slot('$dtor', 0, base([], [void]), [], false), slot('$dtor_del', 0, base([], [void]), [], false)|S0]
    ;   S = S0 ).
%% A CLASS THAT IS NOT TRIVIALLY COPYABLE OR DESTRUCTIBLE is marked for the lowering, which passes it by invisible
%% reference and returns it through a hidden pointer as the Itanium ABI has it (ir_abi): a destructor, a copy or
%% move constructor, a virtual function, or a base or a member that is such
cpp_note_nontrivial(C, Base, Data, Ms, Slots) :-
    (   (   Slots \== [] ; memberchk(dtor(_, _, _), Ms) ; nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ; cpp_copy_ctor(C, _)
        ;   Base \== none, cpp_nontrivial(Base)
        ;   member(member(MT, _, _), Data), cpp_class_of_type(MT, MC), cpp_nontrivial(MC) )
    ->  nb_getval('$cpp_nontrivial', L), ( memberchk(C, L) -> true ; nb_setval('$cpp_nontrivial', [C|L]) )
    ;   true ).
cpp_nontrivial(C) :- nb_getval('$cpp_nontrivial', L), memberchk(C, L).
cpp_base_layout(_, none, Data, Data) :- !.
cpp_base_layout(C, Base, Data, Data1) :- '$cpp_vbase'(C), !, append(Data, [member(base([], [typedef(Base)]), '$base', none)], Data1).
cpp_base_layout(_, Base, Data, [member(base([], [typedef(Base)]), '$base', none)|Data]).
cpp_vt_tag(C, VT) :- atomic_list_concat([C, '.vt'], VT).
cpp_vtable_name(C, N) :- atomic_list_concat([C, '.vtable'], N).
%% the implementation a class's table holds for a slot: its own, else the base's
cpp_slot_impl(C, '$dtor', _, Name) :- !, cpp_dtor(C, Name).
cpp_slot_impl(C, '$dtor_del', _, Name) :- !, cpp_dtor(C, Name).
cpp_slot_impl(C, M, K, Name) :- cpp_class(C, cls(B, _, Ms, _, _, _)), ( member(method(_, _, _, M, Ps, _, _), Ms), length(Ps, K) -> cpp_mangle(C, M, Ps, Name) ; B \== none, cpp_slot_impl(B, M, K, Name) ).
%% ... and whether that implementation is DEFINED: a PURE virtual slot nothing overrides takes a NULL in the table
%% (C++ puts __cxa_pure_virtual there, and there is no runtime here to put), since no object of an abstract class
%% is ever made -- libc++'s `__shared_count::__on_zero_shared() = 0' is one, and the table named a symbol that
%% nothing defines: the link said so, where the emission of a pure member rightly emits nothing.
cpp_slot_def(C, '$dtor', K, Name) :- !, cpp_slot_impl(C, '$dtor', K, Name).
cpp_slot_def(C, '$dtor_del', K, Name) :- !, cpp_slot_impl(C, '$dtor', K, Name).
cpp_slot_def(C, M, K, Name) :- cpp_class(C, cls(B, _, Ms, _, _, _)),
    ( member(method(_, Qs, _, M, Ps, _, _), Ms), length(Ps, K) -> \+ memberchk(pure, Qs), cpp_mangle(C, M, Ps, Name) ; B \== none, cpp_slot_def(B, M, K, Name) ).
cpp_split_members([], [], [], []).
cpp_split_members([member(T0, N, _)|Ms], Data, [N-T|Ss], Ds) :- cpp_static_type(T0, T), !, cpp_split_members(Ms, Data, Ss, Ds).
%% `static' sits in the INNERMOST base's qualifiers, so a static POINTER or ARRAY member -- `static const char
%% __src[33]', libc++'s __num_get_base -- was split as DATA: a class of statics alone was no empty base, and
%% num_get's second base refused multiple_inheritance
cpp_static_type(base(Q, S), base(Q1, S)) :- memberchk(static, Q), !, ccl_delete_one(Q, static, Q1).
cpp_static_type(ptr(Q, T0), ptr(Q, T)) :- !, cpp_static_type(T0, T).
cpp_static_type(arr(N, T0), arr(N, T)) :- !, cpp_static_type(T0, T).
cpp_static_type(ref(Q, T0), ref(Q, T)) :- !, cpp_static_type(T0, T).
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
cpp_class(C, Cls) :- cpp_nested_ready(C), '$cpp_cls'(C, Cls), !.      % a NESTED class asked for while its enclosing one is still being registered
cpp_class(C, Cls) :- cpp_hdr_load(C), '$cpp_cls'(C, Cls), !.
%% the class a type names, and the one a pointer's or an array's element names
cpp_class_of_type(T, C) :- ccl_resolve_type(T, T1), cpp_class_of_type_(T1, C).
cpp_class_of_type_(base(_, [class(_, C, _, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [struct(C, _)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [union(C, _)]), C) :- cpp_class(C, _), !.        % a UNION-CLASS resolves to its union spec, and is its class all the same
cpp_class_of_type_(base(_, [typedef(C)]), C) :- cpp_class(C, _), !.
cpp_class_of_type_(base(_, [typedef(X)]), C) :- cpp_template_id(X, N, Args), !, cpp_targ_values(Args, Args1), cpp_instantiate_type(N, Args1, T), cpp_class_of_type(T, C).   % a template-id the table still holds raw
cpp_class_of_type_(base(_, [typedef(scoped(_, C))]), C) :- cpp_class(C, _), !.
cpp_pointee_class(T, C) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, E) ; T1 = arr(_, E) ), cpp_class_of_type(E, C).
cpp_class_of_type_of(X, C) :- ccl_type_of(X, T), T \== unknown, ccl_unref(T, T1), cpp_class_of_type(T1, C).   % the class an EXPRESSION has: through a reference, since `declval<C &>()' names C's members (the TYPE-level test keeps its reference, where the value category depends on it)
cpp_pointee_class_of(X, C) :- ccl_type_of(X, T), T \== unknown, cpp_pointee_class(T, C).
%% the members: data (own and inherited, with the hops through '$base'), the statics, methods, constructors, the destructor
cpp_data_member(C, N, []) :- cpp_class(C, cls(_, Data, _, _, _, _)), memberchk(member(_, N, _), Data), !.
cpp_data_member(C, N, [A]) :- cpp_class(C, cls(_, Data, _, _, _, _)), member(member(base(_, [union(anon, Ns)]), A, _), Data), memberchk(member(_, N, _), Ns), !.   % in an anonymous union
cpp_data_member(C, N, ['$base'|Hops]) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_data_member(B, N, Hops).
cpp_static_member(C, N, Name) :- cpp_class(C, cls(_, _, _, Ss, _, _)), ( memberchk(N-_, Ss) -> cpp_static_name(C, N, Name) ; cpp_base_scope(C, B), cpp_static_member(B, N, Name) ).
%% A STATIC DATA MEMBER A LIBRARY HEADER DECLARES AND THE SHIPPED LIBRARY DEFINES -- every facet's `static locale::id
%% id', `_ZNSt3__15ctypeIcE2idE' -- is named by its Itanium symbol, where it is declared (extern) and where it is
%% used; one with its initializer in the class is this compiler's own definition, under its own name (0.45)
cpp_static_name(C, N, Name) :- cpp_lib_class(C), \+ cpp_static_const(C, N, _), cpp_class_scope(C, Path, Chain),
    catch(( cpp_ita_prefix(Path, Chain, [], PText, _), cpp_ita_member_name(N, MText), atomic_list_concat(['_ZN', PText, MText, 'E'], Name) ), _, fail), !.
cpp_static_name(C, N, Name) :- atomic_list_concat([C, '.', N], Name).
%% a method by its name and the ARGUMENTS: the overloads whose arity fits, the
%% one whose parameter types fit the arguments' best (cpp_pick/3); the base's
%% when the class has none
%% A CANDIDATE WHOSE ARGUMENT DOES NOT FIT IS TRIED LAST, after every template: libc++ writes
%% `explicit basic_string(const allocator_type &)' beside the constructor TEMPLATE that takes a `const char *', and
%% the plain one -- alone in fitting the ARITY -- won every `std::string s = "abc"', which came out empty. The
%% arity-only set is still the last resort, so nothing that resolved before resolves differently.
cpp_args_fit([], _) :- !.
cpp_args_fit(_, []) :- !.
cpp_args_fit([P|Ps], [A|As]) :- ( ( P = param(PT, _) ; P = param(PT, _, _) ) -> cpp_arg_fit(PT, A, S), S > 0 ; true ), cpp_args_fit(Ps, As).
%% THE ARITY ALONE IS THE LAST RESORT, but never a CLASS-typed parameter for an argument of ANOTHER known class:
%% that is no conversion this compiler makes, and libc++'s copy constructor writes `__rep_(__str.__rep_)', whose
%% `__rep' argument took `__rep(__short)' by arity and stored a union into a byte.
%% ... the parameter read IN ITS OWN CLASS'S WORDS (cpp_param_ref, the door cpp_arg_fit uses since 0.66) and the
%% argument's class through a move and, where the raw form cannot tell, the desugared one. libc++'s union-class
%% writes `__rep(__short __r)' with its holder's nested names, which the INFERENCE cannot resolve, so the clash
%% went unseen and `__rep_(std::move(__str.__rep_))' took `__rep(__short)' by arity -- a union into a byte.
cpp_args_no_clash([], _) :- !.
cpp_args_no_clash(_, []) :- !.
cpp_args_no_clash([P|Ps], [A|As]) :-
    \+ ( ( P = param(PT0, _) ; P = param(PT0, _, _) ), cpp_param_ref(PT0, PT), cpp_class_of_type(PT, C), cpp_init_arg_class(A, AC), AC \== C,
         \+ cpp_converting_ctor(C, A) ),   % ... unless a CONVERTING CONSTRUCTOR bridges it, which cpp_copies_ then builds: `__reset_internal_buffer(__long)' is `__rep(__long)'
    \+ ( ( P = param(PT0, _) ; P = param(PT0, _, _) ), cpp_param_ref(PT0, PT), \+ cpp_class_of_type(PT, _), ccl_resolve_type(PT, RT), ( ccl_is_arith(RT) ; RT = ptr(_, _) ),
         cpp_init_arg_class(A, AC), \+ cpp_method(AC, operator(conv(_)), [], _, _) ),   % and NEVER A SCALAR PARAMETER FOR A CLASS ARGUMENT without a conversion operator: `__s = std::copy(...)' on an ostreambuf_iterator took its `operator=(char)' by arity, and the struct was sign-extended to a byte
    cpp_args_no_clash(Ps, As).
cpp_method(C, M, Args, Name, Hops) :-
    cpp_class(C, cls(B, _, Ms, _, _, _)), length(Args, N),
    findall(Ps, ( member(method(_, _, _, M, Ps, _, _), Ms), cpp_arity_fits(Ps, N) ), Cands0),
    %% IN ITS OWN CLASS: a candidate's parameter type is written in the class's words and read at the CALL SITE,
    %% where the context is the caller's or none at all -- libc++ gives `operator+=' an overload taking
    %% `initializer_list<value_type>', and scoring it outside the class made an instance keyed by the free name
    %% `value_type'. The rule a member template's signature has had since 0.51, for the plain overloads too.
    cpp_in_class(C, ( ( findall(Ps, ( member(Ps, Cands0), cpp_args_fit(Ps, Args) ), [C1|Cs]) -> Cands = [C1|Cs]
                        ; findall(Ps, ( member(Ps, Cands0), cpp_args_no_clash(Ps, Args) ), Cands) ),
                      ( Cands == [] -> true ; cpp_pick(Cands, Args, Ps1) ) )),
    (   Cands \== [] -> Ps = Ps1, cpp_mangle(C, M, Ps, Name), Hops = [], cpp_use_member(C, Name)
    ;   cpp_member_template_call(C, M, [], Args, Name) -> Hops = []                              % a member template, deduced from the arguments
    ;   B \== none, cpp_method(B, M, Args, Name, Hops1), Hops = ['$base'|Hops1]
    ;   cpp_extra_method(C, M, Args, Name, Hops) ).
cpp_extra_method(C, M, Args, Name, Hops) :- '$cpp_extra'(C, Es), member(E, Es), cpp_method(E, M, Args, Name, Hops), !.   % an EMPTY base has no sub-object: the object's own address is the base's
%% an abstract class (a pure virtual method no class of the chain overrides) is declared, never constructed
cpp_not_abstract(C) :- ( cpp_class(C, cls(_, _, _, _, _, Slots)), member(slot(M, K, _, _, _), Slots), \+ cpp_slot_impl(C, M, K, _) -> cpp_refuse(0, pure_virtual(C)) ; true ).
cpp_ctor(C, Args, Name) :-
    cpp_not_abstract(C), cpp_class(C, cls(_, _, Ms, _, _, _)), length(Args, N),
    cpp_in_class(C, findall(Ps, ( member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, N), cpp_args_fit(Ps, Args) ), Cands)), Cands \== [], !,   % in its own class, as above
    cpp_in_class(C, cpp_pick(Cands, Args, Ps)), cpp_mangle(C, C, Ps, Name), cpp_use_member(C, Name).
cpp_ctor(C, Args, Name) :- \+ ( Args = [E], cpp_class_of_type_of(E, C) ), cpp_member_template_ctor(C, Args, Name), !.   % a constructor template, deduced -- never for the class's own value: that is the copy (implicit, or the class's own), as C++ prefers the non-template
cpp_ctor(C, Args, Name) :-                                                                      % nothing fitted, no template held: the arity alone, as it always was
    cpp_not_abstract(C), cpp_class(C, cls(_, _, Ms, _, _, _)), length(Args, N),
    cpp_in_class(C, findall(Ps, ( member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, N), cpp_args_no_clash(Ps, Args) ), Cands)), Cands \== [], !,
    cpp_pick(Cands, Args, Ps), cpp_mangle(C, C, Ps, Name), cpp_use_member(C, Name).
cpp_ctor(C, [], Name) :- cpp_implicit_ctor_needed(C), cpp_mangle(C, C, [], Name).
cpp_pick([Ps], _, Ps) :- !.
cpp_pick(Cands, Args, Ps) :- cpp_best(Cands, Args, none, -1, Ps).
cpp_best([], _, Best, _, Best).
cpp_best([Ps|Cs], Args, B0, S0, Best) :- cpp_score(Ps, Args, S), ( S > S0 -> cpp_best(Cs, Args, Ps, S, Best) ; cpp_best(Cs, Args, B0, S0, Best) ).
cpp_score([], _, 0) :- !.
cpp_score(_, [], 0) :- !.
cpp_score([P|Ps], [A|As], S) :- ( P = param(PT, _) ; P = param(PT, _, _) ), !, cpp_arg_fit(PT, A, S1), cpp_score(Ps, As, S2), S is S1 + S2.
%% how an argument fits a parameter: the same class 3, both pointers 2, both arithmetic 2, unknown 1, else 0
%% THROUGH AN ALIAS TO ITS REFERENCE first: libc++ writes `push_back(const_reference)' beside
%% `push_back(value_type &&)', and no value category can be read off the alias's own name -- the const lvalue
%% overload won a temporary, which then had to be COPIED into it, and a class with an owner had two holders.
cpp_arg_fit(PT0, A, S) :- cpp_param_ref(PT0, PT), cpp_arg_fit_(PT, A, S).
%% ... AND THROUGH THE CLASS'S OWN WORDS: a parameter type is written there (`__rep(__long __r)' names two of
%% `basic_string''s nested classes by their short names), and the fit test resolves with the INFERENCE, which knows
%% typedefs and tags but no class scope. cpp_type/2 is the door that does, and the caller has put us in the class.
cpp_param_ref(T0, T) :- ( catch(cpp_type(T0, T1), _, fail) -> true ; T1 = T0 ), cpp_param_ref_(T1, T).
cpp_param_ref_(T0, T) :- \+ ( T0 = ref(_, _) ; T0 = rref(_, _) ), ccl_resolve_type(T0, R), ( R = ref(_, _) ; R = rref(_, _) ), !, T = R.
cpp_param_ref_(T, T).
cpp_arg_fit_(PT, A, 0) :- cpp_category_mismatch(PT, A), !.                                    % an rvalue reference binds no lvalue, a plain one no rvalue
cpp_arg_fit_(PT, A, S) :-
    (   cpp_arg_type(A, AT)
    ->  ccl_unref(PT, PT1), ccl_unref(AT, AT1),
        (   cpp_class_of_type(PT1, C), cpp_class_of_type(AT1, C) -> ( PT = rref(_, _), \+ cpp_lvalue(A) -> S = 4 ; S = 3 )   % an rvalue takes the move constructor first
        ;   ccl_resolve_type(PT1, RT), ccl_resolve_type(AT1, RT) -> S = 3             % the SAME type, registered class or not: two plain structs alike fit each other
        ;   cpp_pointerish(PT1), cpp_pointerish(AT1) -> ( cpp_pointer_fit(PT1, AT1) -> S = 2 ; S = 0 )
        ;   ccl_is_arith(PT1), ccl_is_arith(AT1) -> S = 2
        ;   S = 0 )
    ;   S = 1 ).
cpp_pointerish(T) :- ccl_resolve_type(T, R), ( R = ptr(_, _) ; R = arr(_, _) ), !.
%% ... BY WHAT THEY POINT TO: `void *' takes any object pointer, a FUNCTION pointer takes only a function, a pointer
%% to a class one to a class; the rest -- the scalars, `char *' to `const char *' -- fit as they always did. Scored
%% as any two pointers, basic_ostream's manipulator inserter, `operator<<(basic_ostream &(*)(basic_ostream &))',
%% took `cout << "hello"' and the literal was CALLED.
cpp_pointer_fit(P, A) :- ccl_resolve_type(P, ptr(_, PE)), ccl_resolve_type(A, AR), ( AR = ptr(_, AE) ; AR = arr(_, AE) ), !, cpp_pointee_fit(PE, AE).
cpp_pointer_fit(_, _).
cpp_pointee_fit(PE, AE) :- ccl_resolve_type(PE, base(_, [void])), !, \+ ccl_resolve_type(AE, fn(_, _, _)).
cpp_pointee_fit(PE, AE) :- ccl_resolve_type(PE, fn(_, _, _)), !, ccl_resolve_type(AE, fn(_, _, _)).
cpp_pointee_fit(PE, AE) :- cpp_class_of_type(PE, _), !, cpp_class_of_type(AE, _).
cpp_pointee_fit(_, _).
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
    ( Defaults \== [] ; B \== none, cpp_has_ctors(B) ; cpp_polymorphic(C) ; member(member(MT, _, _), Data), cpp_class_of_type(MT, MC), cpp_has_ctors(MC) ), !,
    cpp_members_default(Data, Defaults).
%% ... unless C++ DELETES it: a member whose class has no default constructor leaves its holder without one too, and
%% the class stays the AGGREGATE it was written as -- libc++'s `__in_out_result' holds an `ostreambuf_iterator',
%% which takes a stream, and is built `return { a, b }'; making the implicit constructor refused the whole class
%% (member_not_constructed). The test asks no constructor to be emitted: a zero-argument one declared, or none at all.
cpp_members_default([], _).
cpp_members_default([member(MT, N, _)|Ds], Defs) :-
    ( memberchk(N-_, Defs) -> true ; cpp_class_of_type(MT, MC), cpp_has_ctors(MC) -> cpp_default_ctor_exists(MC) ; true ),
    cpp_members_default(Ds, Defs).
cpp_default_ctor_exists(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)),
    ( member(ctor(_, _, Ps, _, _), Ms), cpp_arity_fits(Ps, 0) -> true ; \+ memberchk(ctor(_, _, _, _, _), Ms) ).
%% an implicit destructor: none of its own, a member with one to destroy
cpp_implicit_dtor_needed(C) :- '$cpp_vbase'(C), cpp_class(C, cls(B, _, Ms, _, _, _)), \+ memberchk(dtor(_, _, _), Ms), \+ ( nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ), B \== none, cpp_dtor(B, _), !.   % over a virtual base: the base's destructor runs on the sub-object where it lies, never on `this' as if at offset 0
cpp_implicit_dtor_needed(C) :- cpp_class(C, cls(_, Data, Ms, _, _, _)), \+ memberchk(dtor(_, _, _), Ms), \+ ( nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ),
    member(member(MT, _, _), Data), cpp_class_of_type(MT, MC), cpp_dtor(MC, _), !.
cpp_implicit_dtor(L, C, [function(L, none, base([], [void]), Name, Params, false, Body1)]) :-
    atomic_list_concat([C, '.dtor.0'], Name), cpp_this_type(C, [], [dying], ThisT), Params = [param(ThisT, this)],
    ccl_declare(Name, fn(base([], [void]), Params, false)),
    cpp_dtor_body(L, C, block([]), Body0), cpp_method_body(C, Params, Body0, Body1).
cpp_dtor(C, Name) :- cpp_own_dtor(C, Name), !.
cpp_dtor(C, Name) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none, cpp_dtor(B, Name).      % none of its own: the base's runs on it (the base at offset 0)
cpp_own_dtor(C, Name) :- cpp_class(C, cls(_, _, Ms, _, _, _)), ( memberchk(dtor(_, _, _), Ms) ; nb_getval('$cpp_dtor_defs', Ds), memberchk(C, Ds) ; cpp_implicit_dtor_needed(C) ), !,
    ( memberchk(dtor(_, _, Body), Ms) -> true ; Body = implicit ), cpp_dtor_name(C, Body, Name), cpp_use_member(C, Name).
cpp_arity_fits(Ps, N) :- length(Ps, Max), Max >= N, cpp_required(Ps, Min), Min =< N.
cpp_required([], 0).
cpp_required([param(_, _, _)|_], 0) :- !.
cpp_required([_|Ps], N) :- cpp_required(Ps, N0), N is N0 + 1.

%% ---- names ----------------------------------------------------------------------
cpp_mangle(C, operator(Op), Ps, Name) :- !, cpp_op_word(Op, W), cpp_params_key(Ps, K), atomic_list_concat([C, '.op.', W, '.', K], Name).
%% A MEMBER A LIBRARY HEADER DECLARES AND THE SHIPPED LIBRARY DEFINES is called by its Itanium name, at the one door
%% every member's name comes through -- the emission of its declaration, the call, the table's slot: `__num_put_base::
%% __identify_padding', `ctype<char>::do_narrow'. A constructor is `C1', a destructor `D1' (0.72's cpp_dtor_name,
%% folded in). Where the encoder has no spelling the member keeps its own name, and the link names it.
cpp_mangle(C, M, Ps, Name) :- cpp_shipped_member(C, M, Ps, Qs, Kind), cpp_class_scope(C, Path, Chain),
    catch(( cpp_in_class(C, cpp_plain_params(Ps, Ps1)), cpp_ita_function(Path, Chain, Kind, Qs, Ps1, false, Name) ), _, fail), !.   % the parameters RESOLVED IN THE CLASS first: `do_narrow(char_type, char)' is written in ctype's own words
cpp_mangle(_, M, _, _) :- \+ atom(M), !, cpp_refuse(0, member_name(M)).   % never a raw type_error out of atomic_list_concat: say which name could not be mangled
cpp_mangle(C, M, Ps, Name) :- cpp_params_key(Ps, K), atomic_list_concat([C, '.', M, '.', K], Name).
cpp_shipped_member(C, M, Ps, Qs, Kind) :- atom(M), cpp_lib_class(C), cpp_class(C, cls(_, _, Ms, _, _, _)), cpp_params_key(Ps, K),
    (   M == C -> member(ctor(_, Qs, Ps0, _, none), Ms), cpp_params_key(Ps0, K), Kind = '$ctor'
    ;   member(method(_, Qs, _, M, Ps0, _, none), Ms), \+ memberchk(pure, Qs), cpp_params_key(Ps0, K), Kind = M ),
    \+ cpp_defined_out_of_class(C, Kind, K), !.
%% ... and not DEFINED OUT OF ITS CLASS in the header (`inline ios_base::fmtflags ios_base::flags() const { ... }'),
%% whose body the class's own member list does not hold: that one is compiled here, under its own name
cpp_defined_out_of_class(C, Kind, K) :- '$cpp_mdef'(C, Kind, _, _, Item), cpp_member_shape(Item, Kind, Ps1, B), B \== none, cpp_params_key(Ps1, K), !.
cpp_defined_out_of_class(C, Kind, K) :- cpp_last_segment(C, Last), Last \== C, '$cpp_mdef'(Last, Kind, _, _, Item), cpp_member_shape(Item, Kind, Ps1, B), B \== none, cpp_params_key(Ps1, K), !.   % a nested class's, keyed by its bare name (the reader's spelling of `X<T>::sentry::sentry')
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
cpp_op_word(conv(T), W) :- !, cpp_type_key(T, K), atomic_list_concat([conv, K], '_', W).                 % operator bool(): op.conv_bool
cpp_op_word(Op, W) :- atom_codes(Op, Cs), atomic_list_concat([op|Cs], '_', W).
%% the default arguments of a function, by its (mangled) name: '$cpp_defaults' = [Name-[none | E ...] ...]
cpp_note_defaults(Name, Ps) :- ( member(param(_, _, _), Ps) -> cpp_defaults_of(Ps, Ds), nb_getval('$cpp_defaults', L), nb_setval('$cpp_defaults', [Name-Ds|L]) ; true ).
cpp_defaults_of([], []).
cpp_defaults_of([param(_, _, D)|Ps], [D|Ds]) :- !, cpp_defaults_of(Ps, Ds).
cpp_defaults_of([_|Ps], [none|Ds]) :- cpp_defaults_of(Ps, Ds).
%% A DEFAULT ARGUMENT IS DESUGARED WHERE IT IS FILLED IN, which is where C++ evaluates it: it is kept raw from the
%% declaration, and a default that BUILDS something -- libc++'s `const _Allocator & __a = _Allocator()' on the
%% constructor template every `std::string s = "abc"' goes through -- reached the lowering as a call to a type.
cpp_fill_defaults(Name, As, As1) :- nb_getval('$cpp_defaults', L), memberchk(Name-Ds, L), !, length(As, N), cpp_drop(N, Ds, Rest), cpp_take_defaults(Rest, Tail0),
    ( cpp_exprs(none, Tail0, Tail) -> true ; Tail = Tail0 ), append(As, Tail, As1).
cpp_fill_defaults(_, As, As).
cpp_drop(0, L, L) :- !.
cpp_drop(_, [], []) :- !.   % MORE ARGUMENTS THAN RECORDED DEFAULTS: a method's defaults do not count `this', and a call the desugaring has already built carries it -- `SC(static_cast<long>(r) - 1)' in a derived class's initializer list walked as call(id('SC.SC.long'), [addr(this->$base), ...]), where the drop ran off the end and the whole walk FAILED, silently
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
cpp_refuse(L, What) :- ( nb_getval('$cpp_trace', yes) -> ( catch(nb_getval('$cpp_where', W), _, fail) -> true ; W = top ), cpp_trace(refuse(What, in(W))) ; true ), throw(error(not_lowered(What), where(file, line(L)))).

%% ---- items ----------------------------------------------------------------------
cpp_items([], []).
cpp_items([I|Is], Out) :- cpp_item(I, Js), append(Js, Out1, Out), cpp_items(Is, Out1).
%% a class: the struct, the statics, then its members as functions
cpp_item(declare(L, base(Q, [class(_, C0, _, _)])), Items) :- !, ( cpp_class_item_name(C0, C) -> true ; C = C0 ),
    ( cpp_class(C, cls(Base, Data, Ms, Statics, Defaults, Slots)) -> true ; cpp_trace(item_no_class(C)), fail ),
    cpp_base_layout(C, Base, Data, Data1),
    ( cpp_in_class(C, cpp_static_decls(L, C, Statics, Fns0)) -> true ; cpp_trace(item_statics(C)), fail ),   % IN ITS CLASS: a static's type is written in the class's own words, `static constexpr const type __max'
    ( cpp_is_lazy(C), Slots == [] -> Fns1 = []
    ; cpp_is_lazy(C) -> ( cpp_slot_fns(C, Base, Defaults, Slots, Ms, Fns1) -> true ; cpp_trace(item_member_fns(C)), fail )   % a lazy POLYMORPHIC class emits what its table names -- its own slot implementations -- and nothing else
    ; cpp_in_class(C, cpp_member_fns(Ms, C, Base, Defaults, Fns1)) -> true ; cpp_trace(item_member_fns(C)), fail ),   % a lazy class's members come as they are used
    ( \+ cpp_implicit_ctor_needed(C) -> Fns2 = [] ; cpp_implicit_ctor(L, C, Base, Defaults, Fns2) -> true ; cpp_trace(item_implicit_ctor(C)), fail ),
    ( \+ cpp_implicit_dtor_needed(C) -> Fns3 = [] ; cpp_implicit_dtor(L, C, Fns3) -> true ; cpp_trace(item_implicit_dtor(C)), fail ),
    append(Fns0, Fns1, Fns01), append(Fns01, Fns2, Fns012), append(Fns012, Fns3, Fns),
    ( '$cpp_union'(C) -> Spec = union(C, [union_tag|Data1]) ; Spec = struct(C, Data1) ),   % a union-class shares its members' storage, and its tag says so wherever it is noted from (ccl_is_union_tag)
    (   Slots == [] -> Items = [declare(L, base(Q, [Spec]))|Fns]
    ;   cpp_vt_struct(L, C, Slots, VtDecl), cpp_vtable(L, C, Slots, Table),
        Items = [VtDecl, declare(L, base(Q, [Spec]))|Fns1x], append(Fns, [Table], Fns1x) ).
%% A LAZY POLYMORPHIC CLASS emitted EVERY member, where only the ones its table names need a body: libc++'s
%% basic_ostream, basic_ios, ios_base, basic_streambuf and every facet carry a virtual destructor, and
%% `std::cout << "hello"' walked 234 members -- operator<<(double), swap, basic_istream's whole input side --
%% none of which it uses. Its own virtual methods, the ones filling a slot, are emitted with the class (a base's
%% implementation came with the base; the destructor takes cpp_own_dtor's lazy road) and NOTED, so a use of one
%% does not emit it again; the rest come as they are used, as any lazy class's do.
cpp_slot_members(Slots, Ms, Virt) :-
    findall(M, ( member(M, Ms), M = method(_, Qs, _, N, Ps, _, _), length(Ps, K), memberchk(slot(N, K, _, _, _), Slots), \+ memberchk(pure, Qs) ), Virt).
cpp_note_members(C, Ms) :- forall(( member(M, Ms), cpp_member_mangled(C, M, Name), \+ cpp_instance_done(Name) ), cpp_instance_note(Name, C)).
%% ... and IN PROGRESS while their bodies are walked, as a lazy member is (cpp_make_lazy): a slot's body that calls
%% another slot -- basic_streambuf's uflow calls underflow -- met it not yet noted and emitted it a second time
%% through the lazy road, and LLVM refused the redefinition. Noted once the batch is done; a throw clears them.
cpp_slot_fns(C, Base, Defaults, Slots, Ms, Fns) :-
    cpp_slot_members(Slots, Ms, Virt), findall(N, ( member(M, Virt), cpp_member_mangled(C, M, N) ), Names),
    nb_getval('$cpp_making', M0), append(Names, M0, M1), nb_setval('$cpp_making', M1),
    (   catch(cpp_in_class(C, cpp_member_fns(Virt, C, Base, Defaults, Fns)), E, ( nb_setval('$cpp_making', M0), throw(E) ))
    ->  nb_setval('$cpp_making', M0), cpp_note_members(C, Virt)
    ;   nb_setval('$cpp_making', M0), fail ).
%% the table's struct: a function pointer per slot, over the owner's pointer; the table: the class's implementations
cpp_vt_struct(L, C, Slots, declare(L, base([], [struct(VT, Ms)]))) :-
    cpp_vt_tag(C, VT), cpp_vt_owner(C, Owner), cpp_this_type(Owner, [], ThisT), cpp_this_type(Owner, [], [dying], DyingT),
    findall(member(ptr([], fn(Ret, [param(TT, this)|Ps], V)), M, none), ( member(slot(M, _, Ret, Ps, V), Slots), ( memberchk(M, ['$dtor', '$dtor_del']) -> TT = DyingT ; TT = ThisT ) ), Ms).
cpp_vtable(L, C, Slots, declaration(L, static, base([], [struct(VT, none)]), [var(Name, base([], [struct(VT, none)]), init(Items))])) :-
    cpp_vt_tag(C, VT), cpp_vtable_name(C, Name),
    findall(item([], E), ( member(slot(M, K, _, _, _), Slots), ( cpp_slot_def(C, M, K, Impl) -> E = id(Impl) ; E = nullptr ) ), Items).
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
cpp_item(function(L, Sto, Ret0, N, Ps, V, Body), [function(L, Sto, Ret, Name, Ps1, V, Body1)]) :- !,
    cpp_fn_body_mark(Body, D), cpp_fn_name(N, Ps, D, Name),                                        % an overloaded name's definition carries its parameters' keys
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
%% the static members: declared with the class, defined out of it (Counter::made, above) -- except one initialized in
%% the class (`static constexpr bool value = __v;', integral_constant's), which is its own definition, linkonce as the
%% class's functions are, since every unit that has the class has it
cpp_static_decls(_, _, [], []).
cpp_static_decls(L, C, [N-T0|Ss], [D|Ds]) :- cpp_static_name(C, N, Name), cpp_resolved_type(T0, T),
    ( cpp_static_const(C, N, V) -> D = declaration(L, linkonce, T, [var(Name, T, V)]) ; D = declaration(L, extern, T, [var(Name, T, none)]) ),
    cpp_static_decls(L, C, Ss, Ds).
%% a type resolved where it can be, left as it stands where it cannot: a member's, a static's -- written in the
%% class's own words (`type', `pointer'), which nothing outside the class resolves, the global table's entry of
%% that name being some other class's
cpp_resolved_type(T0, T) :- ( catch(cpp_type(T0, T1), error(not_lowered(_), _), fail) -> T = T1 ; T = T0 ).
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
    ( cpp_method_ret(C, Ret0, Params, Body, Ret) -> true ; cpp_trace(method_ret_failed(C, M)), fail ),
    (   Body == none -> F = declaration(L, none, Ret, [var(Name, fn(Ret, Params, V), none)])
    ;   cpp_method_body(C, Ret, Params, Body, Body1) -> F = function(L, none, Ret, Name, Params, V, Body1)
    ;   cpp_trace(method_body_failed(C, M)), fail ),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([ctor(L, _, Ps, _, none)|Ms], C, B, Ds, [F|Fs]) :- !,                     % DECLARED, not defined: libc++'s bad_alloc() lives in the shipped binary -- a declaration, as a method and a destructor already were
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], [fresh], ThisT), Params = [param(ThisT, this)|Ps1],
    F = declaration(L, none, base([], [void]), [var(Name, fn(base([], [void]), Params, false), none)]),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([ctor(L, _, Ps, Inits, Body)|Ms], C, B, Ds, [F|Fs]) :- !,
    cpp_mangle(C, C, Ps, Name), cpp_plain_params(Ps, Ps1), cpp_this_type(C, [], [fresh], ThisT), Params = [param(ThisT, this)|Ps1],
    ccl_scope_push, ccl_declare_params(Params),                                     % the parameters are in scope while the MEMBER INITIALIZERS are built: `a_(a)' has to type `a' to pick the member's constructor
    ( catch(cpp_ctor_body(L, C, B, Ds, Inits, Body, Body0), E0, (ccl_scope_pop, throw(E0))) -> ccl_scope_pop ; ccl_scope_pop, cpp_trace(ctor_body_failed(C)), fail ),
    ( cpp_method_body(C, Params, Body0, Body1) -> true ; cpp_trace(ctor_walk_failed(C, Body0)), fail ),
    F = function(L, none, base([], [void]), Name, Params, false, Body1),
    cpp_member_fns(Ms, C, B, Ds, Fs).
cpp_member_fns([dtor(L, _, Body)|Ms], C, B, Ds, Fs) :- !,
    cpp_dtor_name(C, Body, Name), cpp_this_type(C, [], [dying], ThisT), Params = [param(ThisT, this)],
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
    cpp_class(C, cls(_, Data0, _, _, _, _)),
    ( '$cpp_union'(C) -> cpp_union_inits(Data0, Inits, Defaults, Data) ; Data = Data0 ),
    cpp_member_inits(Data, Inits, Defaults, L, Pre2, Body).
%% A UNION'S CONSTRUCTOR initializes AT MOST ONE member and leaves every other alone: they share the storage, and
%% default-constructing the rest would both overwrite it and demand a constructor none of them need. libc++'s
%% `__rep(__short __r) : __s(__r) {}' names one of two.
cpp_union_inits(Ds, Inits, Defaults, Ds1) :-
    findall(member(T, N, I), ( member(member(T, N, I), Ds), ( memberchk(init(N, _), Inits) ; memberchk(N-_, Defaults) ) ), Ds1).
%% an initializer naming a base by its template-id names the instance
cpp_norm_inits([], []).
cpp_norm_inits([init(N0, As)|Is], [init(N, As)|Js]) :- ( atom(N0) -> N = N0 ; cpp_base_name(N0, N) ), cpp_norm_inits(Is, Js).
cpp_norm_inits([I|Is], [I|Js]) :- cpp_norm_inits(Is, Js).
%% the class an initializer's argument has, on the RAW expression a constructor's initializer list carries (it is
%% desugared later, with the body): through a `std::move', which is how a guard takes its rollback
%% THE TYPE AN ARGUMENT HAS, wherever the raw form cannot say it: through a `move' in either spelling, and else
%% through the DESUGARED form. A member initializer and a call's arguments are both raw when they are scored, and
%% libc++ writes `__rep_(std::move(__str.__rep_))' -- whose type the inference cannot tell, so every candidate
%% scored the 1 that an unknown type earns and the FIRST constructor won, `__rep(__short)' for a `__rep'.
cpp_arg_type(move(X), T) :- !, cpp_arg_type(X, T).                       % THE MOVE FORMS FIRST: <utility> comes in with
cpp_arg_type(call(scoped(_, move), [X]), T) :- !, cpp_arg_type(X, T).   % every container, so `std::move' is a declared template whose RAW result type would otherwise win
cpp_arg_type(A, T) :- ccl_type_of(A, T0), T0 \== unknown, !, T = T0.
cpp_arg_type(A, T) :- catch(cpp_expr(none, A, A1), _, fail), A1 \== A, ccl_type_of(A1, T0), T0 \== unknown, T = T0.
cpp_init_arg_class(E, C) :- cpp_arg_type(E, T), ccl_unref(T, T1), cpp_class_of_type(T1, C), !.
cpp_init_arg_class(E, C) :- catch(cpp_expr(none, E, E1), _, fail), E1 \== E, cpp_class_of_type_of(E1, C).   % a type that is KNOWN but names no class -- a library template's raw result -- still leaves the DESUGARED form to ask
%% ... and where the RAW form cannot tell, the desugared one can: libc++'s copy constructor writes
%% `__alloc_(__alloc_traits::select_on_container_copy_construction(__str.__alloc_))', a static member call whose
%% result is the member's own class, and unasked it read as a member with no constructor to take it. Only the
%% CLASS is wanted here; the initializer itself is walked with the body, once, as it always was.
cpp_member_inits([], _, _, _, Body, Body).
cpp_member_inits([member(_, '$vptr', _)|Ds], Inits, Defaults, L, Pre, Body) :- !, cpp_member_inits(Ds, Inits, Defaults, L, Pre, Body).
%% A REFERENCE MEMBER IS BOUND, never constructed and never assigned: its slot takes the object's ADDRESS, and
%% every later use reads through it (ir_ref_member). libc++'s `__destroy_vector' holds a `vector &' and binds it
%% in its constructor -- taken as a member of a class with constructors, that became `operator=' into an
%% uninitialized reference, which ran and crashed. With no initializer the member is left alone, as a closure's
%% captures are (an aggregate fills them item by item).
cpp_member_inits([member(MT, N, _)|Ds], Inits, Defaults, L, Pre, Body) :- ( MT = ref(_, _) ; MT = rref(_, _) ), !,
    (   memberchk(init(N, [E]), Inits) -> Pre = [expr(L, bind_ref(arrow(this, N), E))|Pre1]
    ;   memberchk(N-E, Defaults) -> Pre = [expr(L, bind_ref(arrow(this, N), E))|Pre1]
    ;   cpp_trace(reference_member_unbound(N)), Pre = Pre1 ),
    cpp_member_inits(Ds, Inits, Defaults, L, Pre1, Body).
cpp_member_inits([member(MT, N, _)|Ds], Inits, Defaults, L, Pre, Body) :- cpp_class_of_type(MT, MC), cpp_has_ctors(MC), !,   % a member of a class with constructors: constructed
    ( memberchk(init(N, Args), Inits) -> true ; memberchk(N-E, Defaults) -> Args = [E] ; Args = [] ),
    length(Args, NA),
    (   cpp_ctor(MC, Args, CName) -> cpp_fill_defaults(CName, Args, Args1), Pre = [expr(L, call(id(CName), [addr(arrow(this, N))|Args1]))|Pre1]
    ;   Args == [], cpp_trivial_default(MC) -> Pre = Pre1                                          % nothing to construct: libc++'s allocator, `allocator() = default' and a converting template
    ;   Args = [E], cpp_init_arg_class(E, MC)                                                      % the implicit copy or move: bitwise, as a struct copies; a class with a destructor keeps the rule
    ->  ( cpp_dtor(MC, _) -> cpp_refuse(L, copy_of_a_class_with_destructor(MC)) ; Pre = [expr(L, assign('=', arrow(this, N), E))|Pre1] )
    ;   cpp_refuse(L, member_not_constructed(N, MC, NA)) ),
    cpp_member_inits(Ds, Inits, Defaults, L, Pre1, Body).
%% a class default-initialized with nothing to do: no constructor of its own written out (a `= default' one is dropped
%% as the implicit one; a constructor TEMPLATE counts the class as constructible but takes arguments), and no implicit
%% constructor needed -- no defaults, no base or member that constructs, no vtable
cpp_trivial_default(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), \+ memberchk(ctor(_, _, _, _, _), Ms), \+ cpp_implicit_ctor_needed(C).
cpp_trivial_default(C) :- '$cpp_default_ctor'(C), \+ cpp_implicit_ctor_needed(C).     % `C() = default' beside other constructors: the implicit one, with nothing to do
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
cpp_method_body(Ctx, Ret, Params, Body, Body1) :- cpp_where(body(Ctx), cpp_method_body_(Ctx, Ret, Params, Body, Body1)).
cpp_method_body_(Ctx, Ret, Params, Body, Body1) :-
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
%% A TEMPORARY DIES AT THE END OF ITS FULL EXPRESSION (C++'s rule), and the full expression here is the STATEMENT.
%% A temporary of a class with a DESTRUCTOR is declared in a block wrapped around the statement and destroyed by a
%% call after it -- `v.push_back(Tag(1))' constructed the temporary and left it alive for good, and a class holding
%% an owner leaked one buffer per call.
cpp_stmt(Ctx, S, Out) :-
    ccl_global('$cpp_temps', Outer, none), nb_setval('$cpp_temps', []),
    (   catch(cpp_stmt_(Ctx, S, S1), E, (nb_setval('$cpp_temps', Outer), throw(E)))
    ->  nb_getval('$cpp_temps', Ts), nb_setval('$cpp_temps', Outer)
    ;   nb_setval('$cpp_temps', Outer), fail ),
    ( Ts == [] -> Out = S1 ; cpp_temp_scope(S, Ts, S1, Out) ).
%% AN EXPRESSION OR A DECLARATION ends where its full expression ends, and the destructors are plain calls after
%% it: C++'s point of destruction, exactly. ANY OTHER statement holds statements of its own, past which an early
%% exit would walk, so its temporaries are destroyed by a DEFER at the end of a block wrapped around it -- which a
%% `return' needs in any case, the defers running after its value is computed. The temporaries are newest first:
%% declared in construction order, destroyed in the reverse, as C++ has it.
cpp_temp_scope(S0, Ts, S, '$splice'(Js)) :- ( S0 = expr(_, _) ; S0 = declaration(_, _, _, _) ), !,
    reverse(Ts, Order), cpp_temp_decls(Order, Ds), findall(C, (member(X, Ts), cpp_temp_dtor(X, C)), Cs),
    ( S = '$splice'(Is) -> true ; Is = [S] ), append(Ds, Is, Js0), append(Js0, Cs, Js).
cpp_temp_scope(_, Ts, S, block(Js)) :- reverse(Ts, Order), cpp_temp_decls(Order, Ds),
    findall(defer(0, [], block([C])), (member(X, Order), cpp_temp_dtor(X, C)), Fs), append(Ds, Fs, Pre), append(Pre, [S], Js).
cpp_temp_decls(Ts, Ds) :- findall(declaration(0, none, T, [var(N, T, none)]), member(tmp(N, T, _), Ts), Ds).
%% A TEMPORARY WHOSE VALUE INITIALIZES ANOTHER OBJECT of its own class is ELIDED, as C++17 guarantees: the object
%% it builds IS the by-value parameter or the result, and whoever holds it destroys it. Its declaration goes back
%% inside its own block and the statement lets it be -- destroyed at both ends, `v.push(Name("gamma"))' freed one
%% buffer twice and `return Counter(n)' counted a destruction that never happened.
cpp_temp_elide(E0, E) :- E0 = stmt_expr(block(Is)), append(_, [expr(_, id(N))], Is),
    nb_getval('$cpp_temps', Ts), cpp_temp_take(N, Ts, T, Ts1), !,
    nb_setval('$cpp_temps', Ts1), E = stmt_expr(block([declaration(0, none, T, [var(N, T, none)])|Is])).
cpp_temp_elide(E, E).
cpp_temp_take(N, [tmp(N, T, _)|Ts], T, Ts) :- !.
cpp_temp_take(N, [X|Ts], T, [X|Rs]) :- cpp_temp_take(N, Ts, T, Rs).
cpp_temp_dtor(tmp(N, _, D), expr(0, call(id(D), [addr(id(N))]))).
%% a loop's condition and step are evaluated at EVERY iteration, and one slot cannot hold a temporary per turn:
%% refused by name rather than constructed over a live object
cpp_opt_expr_once(_, _, none, none) :- !.
cpp_opt_expr_once(Ctx, L, E, E1) :- cpp_expr_once(Ctx, L, E, E1).
cpp_expr_once(Ctx, L, E, E1) :- nb_getval('$cpp_temps', B), cpp_expr(Ctx, E, E1),
    nb_getval('$cpp_temps', A), ( A == B -> true ; cpp_refuse(L, temporary_in_a_loop_condition) ).
cpp_stmt_(Ctx, block(Is), block(Js)) :- !, ccl_scope_push, cpp_stmts(Ctx, Is, Js), ccl_scope_pop.
cpp_stmt_(Ctx, '$splice'(Is), '$splice'(Js)) :- !, cpp_stmts(Ctx, Is, Js).
cpp_stmt_(Ctx, declaration(L, Sto, B, Vs), S) :- !, cpp_decl_stmt(Ctx, L, Sto, B, Vs, S).
cpp_stmt_(Ctx, expr(L, E), expr(L, E1)) :- !, cpp_expr(Ctx, E, E1).
cpp_stmt_(_, using(_, enum(_)), empty) :- !.                                                    % C++20: the enumerators are in scope already (a namespace flattens)
cpp_stmt_(Ctx, defer(L, Vs, Body), defer(L, Vs, Body1)) :- !, cpp_stmt(Ctx, Body, Body1).
cpp_stmt_(Ctx, if_constexpr(L, C, T, E), Out) :- !,                                          % C++17: decided here when the condition is a constant, else a plain if
    cpp_expr(Ctx, C, C1),
    (   cpp_const_bool(C1, V) -> ( V == true -> cpp_stmt(Ctx, T, Out) ; E == none -> Out = empty ; cpp_stmt(Ctx, E, Out) )
    ;   cpp_stmt(Ctx, T, T1), ( E == none -> E1 = none ; cpp_stmt(Ctx, E, E1) ), Out = if(L, C1, T1, E1) ).
cpp_stmt_(Ctx, if_consteval(_, Neg, T, E), Out) :- !,                                          % C++23: nothing runs at compile time here, so the run-time branch is kept
    ( Neg == yes -> Keep = T ; Keep = E ), ( Keep == none -> Out = empty ; cpp_stmt(Ctx, Keep, Out) ).
cpp_stmt_(_, co_return(L, _), _) :- !, cpp_refuse(L, coroutine).                               % C++20 coroutines: no runtime to suspend into
cpp_stmt_(Ctx, if(L, C, T, E), if(L, C2, T1, E1)) :- !, cpp_expr(Ctx, C, C1), cpp_to_bool(C1, C2), cpp_stmt(Ctx, T, T1), ( E == none -> E1 = none ; cpp_stmt(Ctx, E, E1) ).
cpp_stmt_(Ctx, while(L, C, S), while(L, C2, S1)) :- !, cpp_expr_once(Ctx, L, C, C1), cpp_to_bool(C1, C2), cpp_stmt(Ctx, S, S1).
cpp_stmt_(Ctx, do(L, S, C), do(L, S1, C2)) :- !, cpp_stmt(Ctx, S, S1), cpp_expr_once(Ctx, L, C, C1), cpp_to_bool(C1, C2).
%% A CLASS VALUE WHERE A BOOL IS WANTED -- an if, a loop's test, `!x', the operands of && and || -- converts through its
%% `operator bool' (explicit or not: these are the contextual conversions C++ allows it), which is how a stream's
%% sentry says whether the stream is good: `if (__s)'. Compared with zero as a struct, LLVM refused the icmp.
cpp_to_bool(E, call(id(Name), [Obj])) :- cpp_class_of_type_of(E, C), cpp_method(C, operator(conv(base(_, [bool]))), [], Name, Hops), !, cpp_hops(E, Hops, B), cpp_object_arg(Name, addr(B), Obj).
cpp_to_bool(E, E).
cpp_stmt_(Ctx, for(L, Init, C, Step, S), for(L, Init1, C1, Step1, S1)) :- !,
    ccl_scope_push,
    ( Init = decl(B, Vs) -> cpp_vars(Ctx, Vs, Vs1), ccl_declare_vars(Vs1), Init1 = decl(B, Vs1) ; cpp_opt_expr(Ctx, Init, Init1) ),
    cpp_opt_expr_once(Ctx, L, C, C0), cpp_to_bool(C0, C1), cpp_opt_expr_once(Ctx, L, Step, Step1), cpp_stmt(Ctx, S, S1), ccl_scope_pop.
cpp_stmt_(Ctx, for_each(L, var(N, T0, I), R, S), Out) :- !,
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
%% `return { a, b }': the RESULT TYPE's object, built from the items -- through its constructor where it has one
%% (libc++'s __copy returns `{ __last, __result }', a pair), else the aggregate literal -- and the result it is, elided
cpp_stmt_(Ctx, return(L, init(Items)), return(L, E2)) :- nb_getval('$cpp_ret', Ret), Ret \== none, !,
    findall(V, member(item(_, V), Items), Vs0), cpp_exprs(Ctx, Vs0, Vs),
    (   cpp_class_of_type(Ret, C), cpp_has_ctors(C) -> cpp_temporary(Ret, C, Vs, E0)
    ;   findall(item([], V), member(V, Vs), Items1), E0 = compound_lit(Ret, init(Items1)) ),
    cpp_temp_elide(E0, E2).
cpp_stmt_(Ctx, return(L, E), return(L, E2)) :- !, cpp_expr(Ctx, E, E0), cpp_temp_elide(E0, E1),
    (   nb_getval('$cpp_ret', Ret), Ret \== none, cpp_class_of_type(Ret, C), cpp_dtor(C, _), cpp_lvalue(E1)   % by value, of a class with a destructor, an object that is destroyed here
    ->  (   ( cpp_copy_ctor(C, rref), Arg = move(E1) ; cpp_copy_ctor(C, ref), Arg = E1 )                     % C++'s implicit move out of a local, else its copy
        ->  T = base([], [typedef(C)]), cpp_ctor(C, [Arg], CName), ccl_gensym('$ret', Tmp),
            E2 = stmt_expr(block([declaration(L, none, T, [var(Tmp, T, none)]), expr(L, call(id(CName), [addr(id(Tmp)), E1])), expr(L, id(Tmp))]))
        ;   cpp_refuse(L, return_of_a_class_with_destructor(C)) )
    ;   E2 = E1 ).
cpp_stmt_(Ctx, label(L, N, S), label(L, N, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt_(Ctx, switch(L, E, S), switch(L, E1, S1)) :- !, cpp_expr(Ctx, E, E1), cpp_stmt(Ctx, S, S1).
cpp_stmt_(Ctx, case(L, E, S), case(L, E, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt_(Ctx, default(L, S), default(L, S1)) :- !, cpp_stmt(Ctx, S, S1).
cpp_stmt_(_, S, S).
cpp_stmts(_, [], []).
%% A TYPEDEF IN A BLOCK IS SUBSTITUTED INTO THE STATEMENTS THAT FOLLOW IT, as a template's parameter already is.
%% libc++ writes `using _ValueType = typename iterator_traits<_ContiguousIterator>::value_type;' inside
%% __uninitialized_allocator_relocate and names _ValueType in the lines below -- and the typedef TABLE is one per
%% unit, so half a dozen functions each declaring their own `_ValueType' leave one entry, another function's, whose
%% own parameter is free: `__libcpp_is_trivially_relocatable<_ValueType>' was then keyed by the unresolved NAME.
%% Substituted away, the name is gone and every later use is the concrete type this instance resolved it to.
cpp_stmts(Ctx, [typedef(L, Vs)|Ss], Ts) :- !,
    cpp_where(stmt(typedef, L), cpp_vars(none, Vs, Vs1)), ccl_note_typedefs(Vs1),
    cpp_block_typedefs(Vs1, B), ( B == [] -> Ss1 = Ss ; cpp_subst(Ss, B, Ss1) ),
    cpp_stmts(Ctx, Ss1, Ts).
cpp_block_typedefs([], []).
cpp_block_typedefs([var(N, T, _)|Vs], [N-T|B]) :- atom(N), !, cpp_block_typedefs(Vs, B).
cpp_block_typedefs([_|Vs], B) :- cpp_block_typedefs(Vs, B).
cpp_stmts(Ctx, [S|Ss], [S1|Ts]) :- ( S =.. [F, L|_], integer(L) -> W = stmt(F, L) ; W = stmt ), cpp_where(W, cpp_stmt(Ctx, S, S1)), cpp_stmts(Ctx, Ss, Ts).
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
    cpp_where(auto(N), cpp_expr(Ctx, I0, I)), ( ccl_type_of(I, T0), T0 \== unknown -> cpp_trace(auto_type(N, I, T0)), cpp_decayed(T0, T1), ccl_add_quals(Q, T1, T) ; cpp_refuse(L, auto(N)) ),   % ANY deduced type, not only a plain one: `auto p = q - n' is a pointer, and required a base before
    cpp_decl_pieces(Ctx, L, Sto, B, [var(N, T, '$cpp_walked'(I))|Vs], Pieces).
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
    ->  length(Args, NA), ccl_declare(N, T),
        %% C++17: A PRVALUE OF THE CLASS IS THE OBJECT, elided -- no constructor runs and none is looked for.
        %% `auto __guard = std::__make_scope_guard(f);' hands a `__scope_guard' to the only constructor
        %% `__scope_guard(_Func)' has, which takes the closure, and LLVM refused the store; the temporary that
        %% built it is the object too, so the statement must not destroy it (cpp_temp_elide, as a by-value
        %% parameter and a return already do).
        (   Args = [E0], cpp_class_of_type_of(E0, C), \+ cpp_lvalue(E0)
        ->  cpp_temp_elide(E0, E1), Pieces = [declaration(L, Sto, B, [var(N, T, E1)])|P1]
        ;   cpp_ctor(C, Args, CName)
        ->  cpp_fill_defaults(CName, Args, Args0), cpp_ref_args_of(CName, Args0, Args1),
            Pieces = [declaration(L, Sto, B, [var(N, T, none)]), expr(L, call(id(CName), [addr(id(N))|Args1]))|P1]
        ;   Args == [], cpp_trivial_default(C) -> Pieces = [declaration(L, Sto, B, [var(N, T, none)])|P1]        % nothing to construct
        ;   Args = [E], cpp_class_of_type_of(E, C), \+ cpp_dtor(C, _) -> Pieces = [declaration(L, Sto, B, [var(N, T, E)])|P1]   % the implicit copy, bitwise
        ;   cpp_refuse(L, no_constructor(C, NA)) )
    ;   cpp_trace(plain_init(N, T, I)), cpp_plain_init(I, T, I0), cpp_expr(Ctx, I0, I1), ccl_declare(N, T), cpp_note_const(N, T, I1),
        ( cpp_class_of_type(T, C0), cpp_dtor(C0, _), cpp_lvalue(I1) -> cpp_refuse(L, copy_of_a_class_with_destructor(C0)) ; true ),   % two owners of one buffer
        Pieces = [declaration(L, Sto, B, [var(N, T, I1)])|P1] ),
    ( Sto \== static, Sto \== extern, cpp_class_of_type(T, C2), cpp_dtor(C2, DName) -> P1 = [defer(L, [], block([expr(L, call(id(DName), [addr(id(N))]))]))|P2] ; P1 = P2 ),
    cpp_decl_pieces(Ctx, L, Sto, B, Vs, P2).
%% a type with no constructor direct-initialized, `_Tp __t(std::move(__x))', `int n{}', `S s(t)': the value itself, or
%% the type's zero for an empty one
%% A `const' LOCAL OF INTEGRAL TYPE WITH A CONSTANT INITIALIZER IS A CONSTANT EXPRESSION, as C++ has had it since
%% C++98 (C gained it at C23, ccl_note_constants): its name may stand where a template argument or an array's bound
%% does. libc++'s `__recommend' writes `const size_type __boundary = ...;' and then `__align_it<__boundary>(...)'.
%% Noted after the initializer is DESUGARED, since the class constants in it fold only then.
cpp_note_const(N, T, I) :- ccl_resolve_type(T, R), R = base(Q, _), memberchk(const, Q), \+ ccl_is_float(R), ( ccl_const_eval(I, V) -> true ; cpp_trace(const_not_folded(N, I)), fail ), !,
    nb_getval('$ccl_enums', L), nb_setval('$ccl_enums', [N-V|L]).
cpp_note_const(_, _, _).
cpp_plain_init('$cpp_walked'(X), _, '$cpp_walked'(X)) :- !.
cpp_plain_init(ctor([X]), _, X) :- !.
cpp_plain_init(ctor([]), T, Z) :- !, cpp_zero_of(T, Z).
cpp_plain_init(init([item(_, X)]), T, X) :- \+ cpp_class_of_type(T, _), \+ ccl_resolve_type(T, arr(_, _)), !.
cpp_plain_init(init([]), T, Z) :- \+ cpp_class_of_type(T, _), \+ ccl_resolve_type(T, arr(_, _)), !, cpp_zero_of(T, Z).
cpp_plain_init(I, _, I).
cpp_zero_of(T, Z) :- ( ccl_resolve_type(T, ptr(_, _)) -> Z = nullptr ; ccl_is_float(T) -> Z = float(0.0) ; Z = int(0) ).
cpp_aggregate_inits([], _, _, _, []).
cpp_aggregate_inits(_, [], _, _, []) :- !.
cpp_aggregate_inits([member(_, '$vptr', _)|Ds], Es, Obj, L, Inits) :- !, cpp_aggregate_inits(Ds, Es, Obj, L, Inits).
cpp_aggregate_inits([member(MT, M, _)|Ds], [E|Es], Obj, L, [S|Inits]) :-
    (   cpp_class_of_type(MT, MC), cpp_has_ctors(MC)
    ->  ( cpp_ctor(MC, [E], CName) -> true ; cpp_refuse(L, member_not_constructed(M, MC, 1)) ), cpp_fill_defaults(CName, [E], Args), S = expr(L, call(id(CName), [addr(member(Obj, M))|Args]))
    ;   S = expr(L, assign('=', member(Obj, M), E)) ),
    cpp_aggregate_inits(Ds, Es, Obj, L, Inits).
%% AN INITIALIZER ALREADY WALKED, marked by the `auto' clause above: the pieces must not walk it a second time --
%% a statement expression that builds a temporary would have its declaration desugared again and the temporary
%% constructed twice (`no_constructor(C, 0)' where the second walk found it bare), and a lambda would make a
%% second closure class for nothing.
cpp_ctor_args(_, '$cpp_walked'(E), _, [E]) :- !.
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
    (   cpp_param_takes_class(PT, C), ccl_type_of(A, AT), AT \== unknown, \+ cpp_class_of_type_of(A, C), cpp_converting_ctor(C, A)   % the argument's type KNOWN and not the parameter's own class: what cannot be typed is never converted
    ->  cpp_temporary(base([], [typedef(C)]), C, [A], A1)                                     % A CONVERTING CONSTRUCTOR at a call: libc++ hands a `__long' where a `__rep' is wanted, and `__rep(__long)' is how a string becomes long
    ;   cpp_class_of_type(PT, C), cpp_dtor(C, _), cpp_lvalue(A)
    ->  ( cpp_copy_ctor(C, ref) -> cpp_copy_temp(C, A, A1) ; cpp_refuse(0, class_with_destructor_by_value(C)) )
    ;   cpp_class_of_type(PT, _) -> cpp_temp_elide(A, A1)                                     % a prvalue IS the parameter: elided
    ;   A1 = A ),
    cpp_copies_(Ps, As, Bs).
cpp_copies_([_|Ps], [A|As], [A|Bs]) :- cpp_copies_(Ps, As, Bs).
%% a class with a constructor whose ONE parameter takes the argument -- checked in the class, whose words it is
%% written in, and by the fit rather than the arity, since every class with a one-argument constructor would pass
%% THE CLASS A PARAMETER TAKES: by value, or through a reference that may bind a TEMPORARY -- a const lvalue
%% reference or an rvalue one, which C++ materializes one for. `v.push_back("alpha")' on a vector of strings takes
%% `const_reference', and with only the by-value test the `const char *' went straight through as if it were one.
cpp_param_takes_class(PT0, C) :- cpp_param_ref(PT0, PT), cpp_param_takes_(PT, T), cpp_class_of_type(T, C).
cpp_param_takes_(ref(Q, T), T) :- !, ( memberchk(const, Q) -> true ; T = base(Q2, _), memberchk(const, Q2) ).
cpp_param_takes_(rref(_, T), T) :- !.
cpp_param_takes_(T, T).
cpp_converting_ctor(C, A) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(ctor(_, _, Ps, _, _), Ms),
    cpp_arity_fits(Ps, 1), catch(cpp_in_class(C, cpp_args_fit(Ps, [A])), error(not_lowered(_), _), fail), !.   % the fit test resolves types and may REFUSE: a refusal here is no conversion, never the caller's error
cpp_converting_ctor(C, A) :- '$cpp_mt'(C, ctor, _, ctor(_, _, Ps, _, _)), cpp_arity_fits(Ps, 1),
    catch(cpp_in_class(C, cpp_args_fit(Ps, [A])), error(not_lowered(_), _), fail), !.   % ... or a constructor TEMPLATE, which is how libc++ writes `basic_string(const _CharT *, const _Allocator & = _Allocator())' -- the one every `v.push_back("alpha")' needs
cpp_copy_temp(C, A, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, none)]), expr(0, call(id(CName), [addr(id(Tmp)), A])), expr(0, id(Tmp))]))) :-
    T = base([], [typedef(C)]), cpp_ctor(C, [A], CName), ccl_gensym('$copy', Tmp).

%% ---- expressions, bottom up ----------------------------------------------------------
cpp_exprs(_, [], []).
cpp_exprs(Ctx, [E|Es], [E1|Fs]) :- cpp_expr(Ctx, E, E1), cpp_exprs(Ctx, Es, Fs).
cpp_expr(Ctx, this, E) :- cpp_closure_this(Ctx, _), !, cpp_closure_object([], E).      % inside a lambda that captured it, `this' is the enclosing object's address
cpp_expr(_, '$cpp_walked'(E), E) :- !.                                                  % walked already, by the `auto' deduction
cpp_expr(_, this, id(this)) :- !.
cpp_expr(_, E, E) :- \+ compound(E), !.
cpp_expr(Ctx, id(N), E) :- !,
    (   cpp_local(N) -> E = id(N)
    ;   Ctx = self(C, SN), cpp_data_member(C, N, []) -> E = member(id(SN), N)                   % C++23: a capture, through the closure's explicit object parameter
    ;   Ctx \== none, cpp_data_member(Ctx, N, Hops) -> cpp_access(id(this), N, Hops, E)
    ;   Ctx \== none, cpp_static_const(Ctx, N, V) -> E = V                                    % a static const with a constant, named bare inside its class: the constant, as `C::value' already folds
    ;   Ctx \== none, cpp_static_member(Ctx, N, Name) -> E = id(Name)
    ;   cpp_closure_this(Ctx, EC), cpp_data_member(EC, N, Hops) -> cpp_closure_member(N, Hops, E)   % a lambda's captured this: the enclosing object's member
    ;   cpp_closure_this(Ctx, EC), cpp_static_member(EC, N, Name) -> E = id(Name)
    ;   cpp_global_var(N, GName) -> E = id(GName)                                            % a library header's extern global: the symbol the shipped binary exports
    ;   E = id(N) ).
cpp_expr(_, scoped(Path, N), _) :- memberchk(nonclass(A), Path), !, cpp_refuse(0, no_member(A, N)).   % `_Tp::value' with _Tp a scalar: no members (cpp_subst_path)
cpp_expr(_, scoped(_, N), id(GName)) :- atom(N), cpp_global_var(N, GName), !.   % `std::cout': a library header's extern GLOBAL, by the symbol the shipped binary exports (a scoped name is flattened in the lowering, so it must be taken here)
cpp_expr(_, scoped(Path, N), E) :- cpp_scope_class(Path, C), !,
    (   cpp_static_const(C, N, V) -> E = V                                                        % C::value, a static const with a constant: the constant
    ;   cpp_static_member(C, N, Name) -> E = id(Name)
    ;   atomic_list_concat([C, '.', N], Name), E = id(Name) ).
cpp_expr(_, base(_, [typedef(X)]), E) :- cpp_template_id(X, N, Args0), cpp_variable_template(N), !,   % a variable template READ AS A TYPE in an expression: `!__has_max_size_v<const _Ap>' -- the reader cannot tell, and unevaluated it made the negation false
    cpp_targ_values(Args0, Args), cpp_instantiate_variable(N, Args, E).
cpp_expr(_, tmpl(N, Args0), E) :- cpp_template(N, _, declaration(_, _, _, _)), !,               % a variable template: its instance's value
    cpp_targ_values(Args0, Args), cpp_instantiate_variable(N, Args, E).
cpp_expr(Ctx, call(F, As), E) :- !, cpp_where(args(F), cpp_exprs(Ctx, As, As1)), cpp_where(call(F), cpp_call(Ctx, F, As1, E0)), cpp_copies(E0, E).
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
%% a UNARY operator on a class goes to the class's operator, as a binary one already did: `*it', `++it', `it++'
%% (postfix takes the int C++ marks it with), `!x', `-x', `~x'; anything not a class keeps the form it had
cpp_expr(Ctx, deref(A), E)  :- !, cpp_expr(Ctx, A, A1), cpp_operator('*', A1, [], deref(A1), E).
cpp_expr(Ctx, preinc(A), E) :- !, cpp_expr(Ctx, A, A1), cpp_operator('++', A1, [], preinc(A1), E).
cpp_expr(Ctx, predec(A), E) :- !, cpp_expr(Ctx, A, A1), cpp_operator('--', A1, [], predec(A1), E).
cpp_expr(Ctx, postinc(A), E) :- !, cpp_expr(Ctx, A, A1), ( cpp_class_of_type_of(A1, _) -> cpp_operator('++', A1, [int(0)], postinc(A1), E) ; E = postinc(A1) ).
cpp_expr(Ctx, postdec(A), E) :- !, cpp_expr(Ctx, A, A1), ( cpp_class_of_type_of(A1, _) -> cpp_operator('--', A1, [int(0)], postdec(A1), E) ; E = postdec(A1) ).
cpp_expr(Ctx, not(A), E)    :- !, cpp_expr(Ctx, A, A1), cpp_to_bool(A1, A2), cpp_operator('!', A1, [], not(A2), E).
cpp_expr(Ctx, neg(A), E)    :- !, cpp_expr(Ctx, A, A1), cpp_operator('-', A1, [], neg(A1), E).
cpp_expr(Ctx, bitnot(A), E) :- !, cpp_expr(Ctx, A, A1), cpp_operator('~', A1, [], bitnot(A1), E).
cpp_expr(Ctx, bin(Op, A, B), E) :- memberchk(Op, ['&&', '||']), !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_to_bool(A1, A2), cpp_to_bool(B1, B2), cpp_operator(Op, A1, [B1], bin(Op, A2, B2), E).
cpp_expr(Ctx, bin(Op, A, B), E) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1), cpp_operator(Op, A1, [B1], bin(Op, A1, B1), E).
cpp_expr(Ctx, bind_ref(A, B), bind_ref(A1, B1)) :- !, cpp_expr(Ctx, A, A1), cpp_expr(Ctx, B, B1).   % a reference member BOUND in a constructor: the slot takes the address
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
cpp_expr(_, new_array_init(_, _, _), _) :- !, cpp_refuse(0, new_array_initialized).   % `new T[n]()': its elements are value-initialized, which nothing here does yet
cpp_expr(Ctx, new_at(Ps, N0), E) :- !, cpp_exprs(Ctx, Ps, Ps1),
    ( N0 = new(T0, As) -> cpp_type(T0, T), cpp_exprs(Ctx, As, As1), cpp_new_at(Ps1, T, As1, E) ; cpp_refuse(0, placement_new_array) ).
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
cpp_call(Ctx, tmpl(M, TArgs), As, E) :- Ctx \== none, \+ cpp_local(M), cpp_types(TArgs, TArgs1),   % `__test<_Tp>(nullptr, nullptr)' inside its own class: a member template, its this null
    cpp_member_template_call(Ctx, M, TArgs1, As, Name), !, cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, nullptr, Obj), E = call(id(Name), [Obj|As1]).
cpp_call(_, scoped(Path, tmpl(M, TArgs0)), As, E) :- atom(M), cpp_scope_class(Path, C), '$cpp_mt'(C, M, _, _), !,   % `X::template f<U>()', `X<T>::f<U>(args)': a static member TEMPLATE with its arguments given, its this null -- read as a class template-id it refused template_without_body, which is how libc++'s pair lost every two-argument constructor
    cpp_targ_values(TArgs0, TArgs),
    ( cpp_member_template_call(C, M, TArgs, As, Name) -> cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, nullptr, Obj), E = call(id(Name), [Obj|As1]) ; cpp_refuse(0, no_member_template(M)) ).
cpp_call(Ctx, scoped(Path, M), As, E) :- cpp_scope_class(Path, C), cpp_method(C, M, As, Name, _), !,   % X<T>::f(args), C::f(args): a static method (its this null) ...
    cpp_fill_defaults(Name, As, As1),
    (   Ctx \== none, \+ cpp_static_method(C, M, Name), cpp_base_hops(Ctx, C, Hops)              % ... or, INSIDE A CLASS, a qualified call of its own or a base's method: `this', through the base sub-objects, and never virtual -- libc++'s basic_ios forwards `good()' as `return ios_base::good();', which went out with a null this
    ->  ( Hops == [] -> P = id(this) ; cpp_hops(deref(id(this)), Hops, B), P = addr(B) ), cpp_object_arg(Name, P, Obj)
    ;   cpp_object_arg(Name, nullptr, Obj) ),
    E = call(id(Name), [Obj|As1]).
cpp_static_method(C, M, Name) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(method(_, Qs, _, M, Ps, _, _), Ms), memberchk(static, Qs), cpp_mangle(C, M, Ps, Name), !.
cpp_base_hops(C, C, []) :- !.
cpp_base_hops(Ctx, C, ['$base'|Hops]) :- cpp_class(Ctx, cls(B, _, _, _, _, _)), B \== none, cpp_base_hops(B, C, Hops).
cpp_call(_, id(N), Args, V) :- ccl_builtin_trait(N), !, cpp_trait(N, Args, V).                 % __is_same(T, U): the compiler's trait, decided here
cpp_call(_, operator(Op), As, E) :- cpp_operator_new(Op, As, E), !.                           % `::operator new(n)' written out: the allocation the lowering already has
cpp_call(_, scoped(_, operator(Op)), As, E) :- cpp_operator_new(Op, As, E), !.
cpp_operator_new(new, [N|_], call(id(malloc), [N])).
cpp_operator_new('new[]', [N|_], call(id(malloc), [N])).
cpp_operator_new(delete, [P|_], call(id(free), [P])).
cpp_operator_new('delete[]', [P|_], call(id(free), [P])).
cpp_call(_, id(N), As, E) :- cpp_builtin_call(N, As, E), !.                                   % the compiler's own builtins libc++ calls, answered as this compiler can
%% nothing here is evaluated at compile time, so a run-time answer is the true one; `operator new' is the allocation
%% the lowering already has (ir_cpp_prelude declares malloc and free), and an alignment request is dropped
cpp_builtin_call('__builtin_is_constant_evaluated', [], bool(false)).
cpp_builtin_call('__builtin_launder', [P], P).
cpp_builtin_call('__builtin_addressof', [X], addr(X)).
cpp_builtin_call('__builtin_expect', [E, _], E).
cpp_builtin_call('__builtin_assume_aligned', [P|_], P).
cpp_builtin_call('__builtin_operator_new', [N|_], call(id(malloc), [N])).      % a size, and an alignment this compiler does not honour
cpp_builtin_call('__builtin_operator_delete', [P|_], call(id(free), [P])).
%% the memory builtins are the C library's functions, which the lowering declares when the file did not
%% (ir_cpp_prelude): libc++ relocates a vector's elements with __builtin_memcpy
cpp_builtin_call('__builtin_memcpy', As, call(id(memcpy), As)).
cpp_builtin_call('__builtin_memmove', As, call(id(memmove), As)).
cpp_builtin_call('__builtin_memset', As, call(id(memset), As)).
cpp_builtin_call('__builtin_memcmp', As, call(id(memcmp), As)).
cpp_builtin_call('__builtin_strlen', As, call(id(strlen), As)).
%% what this compiler can only answer at run time, or need not answer at all: a constant test is FALSE (nothing
%% here is folded past ccl_const_eval), an assumption and a prefetch are nothing, and an unreachable point is nothing
cpp_builtin_call('__builtin_constant_p', [_], int(0)).
cpp_builtin_call('__builtin_assume', [_], int(0)).
cpp_builtin_call('__builtin_unreachable', [], int(0)).
cpp_builtin_call('__builtin_prefetch', [_|_], int(0)).
%% THE BIT COUNT, folded here where the argument folds: libc++ writes a type's `digits' as
%% `__builtin_popcountg(~__make_unsigned_t<type>(0)) - is_signed', and numeric_limits<ptrdiff_t>::__max is built
%% from it -- a static const that does not fold is emitted `extern' and the link finds nothing. cocolog's integers
%% are 61-bit, so `~0' is -1 and the count is taken from the type's WIDTH: 64 - popcount(\ -1) = 64 - 0.
cpp_builtin_call(N, [X], int(P)) :- cpp_popcount_name(N), cpp_popcount(X, P).
cpp_popcount_name('__builtin_popcountg').
cpp_popcount_name('__builtin_popcount').
cpp_popcount_name('__builtin_popcountl').
cpp_popcount_name('__builtin_popcountll').
cpp_popcount(X, P) :- ccl_const_eval(X, V),
    ( ccl_type_of(X, T), T \== unknown, ccl_size_of(T, S), S > 0 -> W is S * 8 ; W = 64 ),
    ( V >= 0 -> cpp_bits(V, 0, P) ; V1 is \ V, cpp_bits(V1, 0, P0), P is W - P0 ).
cpp_bits(0, P, P) :- !.
cpp_bits(V, P0, P) :- P1 is P0 + (V /\ 1), V1 is V >> 1, cpp_bits(V1, P1, P).
cpp_call(Ctx, member(X0, M), As, E) :- !,
    cpp_expr(Ctx, X0, X),
    (   cpp_class_of_type_of(X, C), length(As, N), cpp_method(C, M, As, Name, Hops)
    ->  cpp_fill_defaults(Name, As, As1),
        (   cpp_slot(C, M, N, Slot), \+ cpp_static_object(X) -> cpp_dispatch(addr(X), C, Slot, As1, E)   % a reference, *p: the dynamic type's
        ;   cpp_hops(X, Hops, B), cpp_object_arg(Name, addr(B), Obj), cpp_ref_args_of(Name, As1, As2), E = call(id(Name), [Obj|As2]) )
    ;   atom(M), ( ccl_type_of(X, XT0) -> ccl_unref(XT0, XT) ; XT = unknown ),
        ( XT \== unknown, ccl_members_of(XT, _) -> cpp_refuse(0, no_member(M, XT)) ; E = call(member(X, M), As) )   % a KNOWN type with no such member: a decltype asking for it must refuse, which is the SFINAE that rejects a detection
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
cpp_call(Ctx, id(M), As, E) :- cpp_closure_this(Ctx, EC), \+ cpp_local(M), length(As, N), cpp_method(EC, M, As, Name, Hops), !,   % a lambda's captured this: the enclosing class's method
    cpp_fill_defaults(Name, As, As1), cpp_closure_object(Hops, P),
    (   cpp_slot(EC, M, N, Slot) -> cpp_dispatch(P, EC, Slot, As1, E)
    ;   cpp_object_arg(Name, P, Obj), E = call(id(Name), [Obj|As1]) ).
%% p->$vptr->slot(p, args), the pointer to the table found through the base sub-objects
%% A DISPATCH READS THE OBJECT'S OWN CLASS'S TABLE: the pointer member is typed by the class that INTRODUCED the
%% table (`__shared_count.vt' under every libc++ facet), whose struct has that class's slots and none of the ones
%% a derived class adds -- ctype<char>::widen dispatching `do_widen' found no such member. The tables are laid out
%% base first, so the derived class's table struct extends the owner's, and the pointer is cast to it; its tag is
%% noted here where the walk meets it first, before the class's items are.
cpp_dispatch(P, C, Slot, As, call(arrow(cast(ptr([], base([], [struct(VT, none)])), Vptr), Slot), [P|As])) :-
    cpp_data_member(C, '$vptr', Hops), cpp_access(P, '$vptr', Hops, Vptr), cpp_vt_tag(C, VT),
    (   ccl_tag(VT, _) -> true
    ;   cpp_class(C, cls(_, _, _, _, _, Slots)), cpp_vt_struct(0, C, Slots, declare(_, base(_, [struct(VT, VMs)]))), ccl_note_tag(VT, VMs) ).
%% a value whose dynamic type is its static one: a named object, or a member of one; not a reference
cpp_static_object(id(N)) :- ccl_declared(N, T), \+ T = ref(_, _), \+ T = rref(_, _).
cpp_static_object(member(X, _)) :- cpp_static_object(X).
cpp_call(Ctx, scoped([std], move), [X], E) :- !, cpp_expr(Ctx, move(X), E).                     % std::move is Cicili's move: the fields go, the source is emptied; of an int, the int
cpp_call(_, scoped(Path, tmpl(F, TArgs)), As, E) :- \+ cpp_scope_class(Path, _), !, cpp_call(none, tmpl(F, TArgs), As, E).        % std::swap<int>(a, b): the namespace flattens
cpp_call(_, scoped(Path, F), As, E) :- atom(F), \+ cpp_scope_class(Path, _), \+ ( cpp_class(F, _), cpp_class_takes(F, As) ), !, cpp_call(none, id(F), As, E).   % std::swap(a, b): as the bare name would, never a member (a qualified name finds no method); a class of that name which cannot take the arguments is another namespace's
cpp_call(_, id(F), As, call(id(Name), [Obj|As1])) :- cpp_local(F), cpp_class_of_type_of(id(F), C), cpp_method(C, operator('()'), As, Name, _), !, cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, addr(id(F)), Obj).   % a lambda, or any object with operator()
%% A DATA MEMBER THAT IS CALLABLE, named bare inside its class, is called through its own class's operator(), as a
%% local of such a class already was: libc++'s scope guard holds the closure it was made with and its destructor
%% writes `__func_()', which is the whole of how `basic_string' unwinds an append. The member is reached the way
%% every bare member name is (this->f_, a base's hops with it), and the closure's call takes its address.
cpp_call(Ctx, id(F), As, call(id(Name), [Obj|As1])) :- Ctx \== none, \+ cpp_local(F), cpp_data_member(Ctx, F, Hops),
    cpp_access(id(this), F, Hops, X), cpp_class_of_type_of(X, C), cpp_method(C, operator('()'), As, Name, _), !,
    cpp_fill_defaults(Name, As, As1), cpp_object_arg(Name, addr(X), Obj).
cpp_call(_, tmpl(F, TArgs), As, call(id(Name), As)) :- cpp_template(F, _, Item), cpp_fn_item(Item, _), !, cpp_types(TArgs, TArgs1), cpp_instantiate_function(F, TArgs1, As, Name).   % a DECLARED-only one too: declval
cpp_call(_, tmpl(N, TArgs), As, E) :- cpp_template(N, _, typedef(_, _)), !,                      % an ALIAS template called by its template-id: the type it names, cast or constructed
    cpp_targ_values(TArgs, TArgs1), cpp_instantiate_type(N, TArgs1, T), cpp_type_call(T, As, E).
cpp_call(_, tmpl(C, TArgs), As, E) :- cpp_targ_values(TArgs, TArgs1), cpp_targs_settled(TArgs1),   % `Guard<A, I>(a, i, j)': a temporary of a class TEMPLATE's instance, as a plain class's already was
    cpp_instantiate_type(C, TArgs1, T), cpp_class_of_type(T, C1), !, cpp_temporary(T, C1, As, E).
%% every argument a type or a constant: an expression that did not fold would name an instance by its spelling
cpp_targs_settled([]).
cpp_targs_settled([A|As]) :- ( cpp_is_type(A) -> true ; A = int(_) -> true ; A = bool(_) -> true ; A = tname(_) ), cpp_targs_settled(As).
cpp_call(_, id(F), As, E) :- \+ cpp_local(F), cpp_fn_exact(F, As, Ps, D), !, cpp_free_call(F, Ps, D, As, E).   % an overload whose parameters take the arguments EXACTLY: C++ prefers such a non-template to any template
cpp_call(_, id(F), As, E) :- \+ cpp_local(F), cpp_template(F, _, Item), cpp_fn_item(Item, _), !,
    nb_setval('$cpp_fn_refusal', none),
    (   catch(cpp_instantiate_function(F, [], As, Name), error(not_lowered(W), _), ( nb_setval('$cpp_fn_refusal', W), fail ))
    ->  E = call(id(Name), As)
    ;   cpp_fn_best(F, As, Ps, D) -> cpp_free_call(F, Ps, D, As, E)                                % no template held: the plain overloads of the name, ONE overload set with them
    ;   nb_getval('$cpp_fn_refusal', W1), ( W1 == none -> cpp_refuse(0, no_matching_template(F)) ; cpp_refuse(0, W1) ) ).
cpp_call(Ctx, id(N), As, E) :- Ctx \== none, \+ cpp_local(N), cpp_class_typedef(Ctx, N, T0),   % a class-scope TYPE named bare inside its class: `__destroy_vector(*this)' a nested class, `size_type(~0)' a cast
    catch(cpp_type(T0, T), error(not_lowered(_), _), fail), !, cpp_type_call(T, As, E).
%% the same for a typedef at FILE scope, which libc++ calls by its own name: `__destruct_at_end(p, false_type())'
%% makes a temporary of integral_constant<bool, false> by its alias, and `size_t(n)' is the cast it looks like
cpp_call(_, id(N), As, E) :- \+ cpp_local(N), \+ ccl_declared(N, fn(_, _, _)), ccl_typedef_of(N, T0),
    catch(cpp_type(T0, T), error(not_lowered(_), _), fail), !, cpp_type_call(T, As, E).
%% A TYPE'S NAME CALLED: a temporary of the class it names, an aggregate of the items, the cast it looks like, or
%% its zero -- written once for the three names a type has here (a class-scope typedef, a file-scope one, and an
%% ALIAS TEMPLATE's template-id, `__make_unsigned_t<type>(0)', which libc++ takes a type's digits through)
cpp_type_call(T, As, E) :-
    (   cpp_class_of_type(T, C1)
    ->  ( cpp_has_ctors(C1) -> cpp_temporary(T, C1, As, E) ; findall(item([], A), member(A, As), Items), E = compound_lit(T, init(Items)) )
    ;   As = [X] -> E = cast(T, X)
    ;   As == [] -> cpp_zero_of(T, E)
    ;   fail ).
cpp_call(_, id(C), As, E) :- cpp_class(C, _), cpp_class_takes(C, As), !, cpp_temporary(base([], [typedef(C)]), C, As, E).
%% A TAG'S OR A CLASS'S NAME CALLED WITH MORE ARGUMENTS THAN IT CAN TAKE IS NO TEMPORARY: namespaces flatten to
%% bare names here, and libc++ has both `_Algorithm::__fill_n', an EMPTY tag struct used as a template argument,
%% and `std::__fill_n(first, n, value)' -- so the call built an aggregate of three items for a type with no
%% members. An empty tag takes a cast or nothing, an enum a cast, an aggregate at most one item per member; a
%% class with constructors chooses among them as before.
cpp_tag_takes(Ms, As) :- ( Ms == [] -> ( As == [] -> true ; As = [_] ) ; ccl_is_enum_tag(Ms) -> As = [_] ; length(As, K), length(Ms, N), K =< N ).
cpp_class_takes(C, As) :- cpp_class(C, cls(_, Data, Ms, _, _, _)),
    ( memberchk(ctor(_, _, _, _, _), Ms) -> true ; length(As, K), length(Data, N), K =< N ).
cpp_call(_, id(T), As, E) :- ccl_tag(T, Ms), cpp_tag_takes(Ms, As), !,
    (   ( Ms == [] ; ccl_is_enum_tag(Ms) ), As = [X] -> E = cast(base([], [typedef(T)]), X)   % an ENUM's name: `__element_count(n)', `Color(2)' -- a cast, never a literal of members
    ;   findall(item([], A), member(A, As), Items), E = compound_lit(base([], [typedef(T)]), init(Items)) ).   % P{3, 4} of a plain struct: C's compound literal
cpp_call(_, scoped(Path, N), As, E) :- atom(N), cpp_scope_class(Path, Enc), cpp_class_typedef(Enc, N, T0),   % `Plain::Nested(7)': a temporary of a NESTED class
    catch(cpp_type(T0, T), error(not_lowered(_), _), fail), cpp_class_of_type(T, C1), !,
    ( cpp_has_ctors(C1) -> cpp_temporary(T, C1, As, E) ; findall(item([], A), member(A, As), Items), E = compound_lit(T, init(Items)) ).
cpp_call(_, scoped(_, C), As, E) :- atom(C), cpp_class(C, _), cpp_class_takes(C, As), !, cpp_temporary(base([], [typedef(C)]), C, As, E).   % std::string("x"): a temporary of the class
%% `X::f(args)' ON A CLASS WITHOUT SUCH A MEMBER REFUSES, as `o.f()' has since 0.51 -- the rejection a detection
%% needs: libc++ chooses `__to_address' by `decltype((void) pointer_traits<_Pointer>::to_address(declval<const
%% _Pointer &>()))', and flattened to a call of the global name `to_address' it was void either way, so every
%% pointer had one and the wrong overload held. A nested class or a class-scope typedef called by that name is a
%% temporary or a cast (above), a static data member a value: only a name the class has NOTHING of refuses.
cpp_call(_, scoped(Path, M), As, _) :- atom(M), cpp_scope_class(Path, C), \+ cpp_has_member(C, M), \+ cpp_class_typedef(C, M, _), !,
    length(As, K), cpp_refuse(0, no_member(C, M, K)).
cpp_call(_, id(F), As, E) :- !, ( cpp_fn_best(F, As, Ps, D) -> cpp_free_call(F, Ps, D, As, E)   % the overload the arguments fit best; a name with one definition keeps it, as C does
    ;   cpp_fill_defaults(F, As, As1), cpp_ref_args(F, As1, As2), E = call(id(F), As2) ).
cpp_call(Ctx, F, As, E) :- cpp_expr(Ctx, F, F1), ( cpp_temp_call(F1, As, E0) -> E = E0 ; E = call(F1, As) ).
%% A TEMPORARY'S operator(), `__destroy_vector(*this)()', which is how libc++'s vector destroys itself: the callee
%% is no function but an object, and the call goes INSIDE the block that built it, where that object has an address.
cpp_temp_call(stmt_expr(block(Ss)), As, stmt_expr(block(Ss1))) :- !,
    cpp_class_of_type_of(stmt_expr(block(Ss)), C), cpp_method(C, operator('()'), As, Name, Hops),
    append(Pre, [expr(L, Last)], Ss), cpp_hops(Last, Hops, B), cpp_object_arg(Name, addr(B), Obj),
    cpp_fill_defaults(Name, As, As1), cpp_ref_args_of(Name, As1, As2),
    append(Pre, [expr(L, call(id(Name), [Obj|As2]))], Ss1).
%% `_Algorithm()(a, b, c)': an AGGREGATE temporary -- a class with no constructor, libc++'s algorithm dispatch
%% tags are such -- is a compound literal with no block of its own, so it gets one: declared, then its operator()
%% over its address, the block's value the call's. A `auto __result = ...' of it had no type at all.
cpp_temp_call(compound_lit(T, init(Items)), As, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, init(Items))]), expr(0, call(id(Name), [Obj|As2]))]))) :-
    cpp_class_of_type(T, C), cpp_method(C, operator('()'), As, Name, Hops), !,
    ccl_gensym('$tmp', Tmp), ccl_declare(Tmp, T), cpp_hops(id(Tmp), Hops, B), cpp_object_arg(Name, addr(B), Obj),
    cpp_fill_defaults(Name, As, As1), cpp_ref_args_of(Name, As1, As2).
cpp_temp_call(X, As, call(id(Name), [Obj|As2])) :- cpp_addressable(X),                         % `(*p)(a)', `fs[i](a)' of an object: its own address, no temporary
    cpp_class_of_type_of(X, C), cpp_method(C, operator('()'), As, Name, Hops),
    cpp_hops(X, Hops, B), cpp_object_arg(Name, addr(B), Obj),
    cpp_fill_defaults(Name, As, As1), cpp_ref_args_of(Name, As1, As2).
cpp_addressable(deref(_)).
cpp_addressable(index(_, _)).
%% a temporary of the class: constructed in a statement expression, its value the last expression
cpp_temporary(T, C, As, compound_lit(T, init(Items))) :- cpp_not_abstract(C), \+ cpp_has_ctors(C), !, findall(item([], A), member(A, As), Items).   % an AGGREGATE, `__allocation_result{p, n}': braced, no constructor
cpp_temporary(T, C, [], compound_lit(T, init([]))) :- cpp_not_abstract(C), cpp_trivial_default(C), !.   % `__less<>()': nothing to construct, as a member and a local already had it
%% A TEMPORARY OF A CLASS WITH A DESTRUCTOR is declared by the STATEMENT that holds it, never here: its slot and
%% its defer belong to the full expression's scope (cpp_stmt), and only the construction stays in place, where the
%% evaluation order puts it. Outside a statement walk ('$cpp_temps' unset) it is declared here as it always was.
cpp_temporary(T, C, As, stmt_expr(block([expr(0, call(id(Name), [addr(id(Tmp))|As1])), expr(0, id(Tmp))]))) :-
    cpp_not_abstract(C), cpp_dtor(C, Dtor), ccl_global('$cpp_temps', Ts, none), is_list(Ts), !,
    length(As, N), ( cpp_ctor(C, As, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As0), cpp_ref_args_of(Name, As0, As1),
    ccl_gensym('$tmp', Tmp), ccl_declare(Tmp, T), nb_setval('$cpp_temps', [tmp(Tmp, T, Dtor)|Ts]).   % DECLARED here as well as by the statement that holds it: its block no longer carries the declaration, so nothing else could type the value the block yields
cpp_temporary(T, C, As, stmt_expr(block([declaration(0, none, T, [var(Tmp, T, none)]), expr(0, call(id(Name), [addr(id(Tmp))|As1])), expr(0, id(Tmp))]))) :-
    cpp_not_abstract(C), length(As, N), ( cpp_ctor(C, As, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As0), cpp_ref_args_of(Name, As0, As1), ccl_gensym('$tmp', Tmp).
%% an operator on a class-typed left operand: the class's member operator, else a free one declared, else the form as it is
cpp_operator(Op, A, Args, Plain, E) :-
    (   cpp_class_of_type_of(A, C), cpp_method(C, operator(Op), Args, Name, Hops)
    ->  (   \+ cpp_member_exact(Name, Args), cpp_free_operator_call(Op, A, Args, E0) -> E = E0   % C++ weighs the members and the free ones TOGETHER: a free operator that fits EXACTLY beats a member that needs a conversion -- `cout << "hello"' is the free template over `const _CharT *', never the member over `const void *'
        ;   cpp_hops(A, Hops, B), cpp_fill_defaults(Name, Args, Args0), cpp_ref_args_of(Name, Args0, Args1), cpp_object_arg(Name, addr(B), Obj), E = call(id(Name), [Obj|Args1]) )
    ;   cpp_class_of_type_of(A, _), length(Args, N0), N1 is N0 + 1, length(Ps, N1), cpp_free_operator(Op, Ps, Name), nb_getval('$cpp_free_ops', Os), memberchk(Name, Os)
    ->  E = call(id(Name), [A|Args])
    ;   cpp_free_operator_call(Op, A, Args, E0)
    ->  E = E0
    ;   E = Plain ).
%% ... AND A LIBRARY HEADER'S OWN, which is a TEMPLATE: `operator==(const basic_string<C, T, A> &, const C *)' is how
%% a string compares, and the registry above holds only the program's written-out operators. The name is the same
%% (`op.eq.2'), so the free-function road takes it from here -- its lazy load, its candidates, its deduction. It
%% must ANSWER a call, or the form stays as it was and the scalar rule applies.
cpp_free_operator_call(Op, A, Args, E) :-
    cpp_class_of_type_of(A, _), length(Args, N2), N3 is N2 + 1, length(Qs, N3), cpp_free_operator(Op, Qs, Name),
    catch(cpp_call(none, id(Name), [A|Args], E0), error(not_lowered(_), _), fail), E0 = call(id(F0), _), ccl_declared(F0, fn(_, _, _)), E = E0.
%% a member operator takes its arguments EXACTLY: every parameter after `this' the argument's own type (cpp_arg_exact)
cpp_member_exact(Name, Args) :- ccl_declared(Name, fn(_, [_|Ps], _)), cpp_args_exact(Ps, Args).
cpp_args_exact([], []).
cpp_args_exact([param(P, _)|Ps], [A|As]) :- cpp_arg_exact(P, A), cpp_args_exact(Ps, As).
%% new C(args): malloc's block constructed; delete p: destroyed, then freed
cpp_new(T, As, stmt_expr(block([declaration(0, none, T, [var(P, PT, new(T, []))]), expr(0, call(id(Name), [id(P)|As1])), expr(0, id(P))]))) :-
    cpp_class_of_type(T, C), cpp_has_ctors(C), !,
    length(As, N), ( cpp_ctor(C, As, Name) -> true ; cpp_refuse(0, no_constructor(C, N)) ), cpp_fill_defaults(Name, As, As1), ccl_gensym('$new', P), PT = ptr([], T).
cpp_new(T, As, new(T, As)).
%% PLACEMENT NEW constructs WHERE IT IS TOLD and allocates nothing: `::new ((void *) p) T(args)', which is what
%% `std::__construct_at' is and what every libc++ container makes its elements with. Read as the allocating new it
%% looks like, it called malloc and dropped the block: a vector's size grew and its elements were never stored.
cpp_new_at([P], T, As, stmt_expr(block([declaration(0, none, PT, [var(N, PT, cast(PT, P))]), expr(0, call(id(CName), [id(N)|As1])), expr(0, id(N))]))) :-
    cpp_class_of_type(T, C), cpp_has_ctors(C), !,
    length(As, K), ( cpp_ctor(C, As, CName) -> true ; cpp_refuse(0, no_constructor(C, K)) ), cpp_fill_defaults(CName, As, As1),
    ccl_gensym('$at', N), PT = ptr([], T).
cpp_new_at([P], T, As, stmt_expr(block([declaration(0, none, PT, [var(N, PT, cast(PT, P))]), expr(0, assign('=', deref(id(N)), V)), expr(0, id(N))]))) :-
    ( As = [V] -> true ; As == [], \+ cpp_class_of_type(T, _), \+ ccl_resolve_type(T, arr(_, _)), cpp_zero_of(T, V) ), !,
    ccl_gensym('$at', N), PT = ptr([], T).
cpp_new_at(Ps, T, As, _) :- length(Ps, NP), length(As, NA), cpp_refuse(0, placement_new(T, NP, NA)).
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
cpp_template_name(function(_, _, _, operator(Op), Ps, _, _), N) :- cpp_free_operator(Op, Ps, N).   % a FREE OPERATOR TEMPLATE: named by its word and arity, as a written-out one is, so a header indexes and registers it
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
    ( cpp_static_const(C, N, _) -> true ; cpp_static_member(C, N, _) -> true ; cpp_refuse(0, no_member_type(C, N)) ),   % ... unless it has no such MEMBER either: `typename _Up::category' on a class without one, which is the SFINAE that rejects the candidate
    cpp_targ_value(scoped(Path, N), A).
cpp_targ_value(base(_, [typedef(X)]), A) :- cpp_template_id(X, N, Args0), cpp_variable_template(N), !,   % `integral_constant<bool, __is_floating_point_impl<T>>': read as a type, it is a VARIABLE template's value
    cpp_targ_values(Args0, Args), cpp_instantiate_variable(N, Args, A).
cpp_variable_template(N) :- atom(N), catch(cpp_template(N, _, declaration(_, _, _, [var(_, _, _)|_])), _, fail),
    \+ ( cpp_template(N, _, I), cpp_template_class_def(I) ), !.
%% `X::template f<U>()' in a template argument reads as a FUNCTION TYPE returning `X::f<U>' and taking nothing --
%% the reader cannot know that f is a member function template, where C++ knows it from the class. The class
%% does know: where it HAS such a member template, the argument is the CALL it means and its VALUE is asked
%% (libc++'s pair, `__enable_if_t<_CheckArgsDep::template __is_pair_constructible<_U1, _U2>(), int> = 0').
cpp_targ_value(fn(base([], [typedef(scoped(Path, tmpl(M, TArgs)))]), [], false), A) :- atom(M), cpp_scope_class(Path, C), '$cpp_mt'(C, M, _, _), !,
    cpp_targ_value(call(scoped(Path, tmpl(M, TArgs)), []), A).
cpp_targ_value(A0, A) :- cpp_is_type(A0), !, cpp_type(A0, A).
cpp_targ_value(pack(X), pack(X)) :- !.
cpp_targ_value(A0, A) :- cpp_expr(none, A0, A1), ( A1 = bool(_) -> A = A1 ; cpp_const_value(A1, V) -> A = int(V) ; A = A1 ).
%% A CONSTANT IS A CONSTANT EXPRESSION, OR A CONSTEXPR FUNCTION OF ONE `return' CALLED ON CONSTANTS -- the one
%% compile-time evaluation this compiler makes, and the shape libc++'s pair chooses its constructors by:
%% `__enable_if_t<_CheckArgsDep::template __is_pair_constructible<_U1, _U2>(), int> = 0', a static constexpr
%% member function template whose body is `return is_constructible<_T1, _U1>::value && ...'. The instance is
%% emitted as any member template's is, at the call; its body is read back from the emitted item ('$cpp_out'),
%% already desugared in its class's words so the traits in it are constants, its parameters bound to the call's
%% arguments (`this' to the null it was passed), and the return's expression folds -- or does not, and the
%% call stays a call. A body of more than one statement, or a loop, is not evaluated: it is a function.
%% The depth is bounded, since a constexpr function may call itself on an argument that never folds.
cpp_const_value(E, V) :- ccl_const_eval(E, V), !.
cpp_const_value(call(id(F), Args), V) :- atom(F), '$cpp_out'(function(_, _, _, F, Params, _, block([return(_, E0)]))), !,
    cpp_fold_depth(D), D < 32, D1 is D + 1, nb_setval('$cpp_fold_depth', D1),
    (   cpp_param_binds(Params, Args, B), cpp_replace_ids(E0, B, E), cpp_const_value(E, V)
    ->  nb_setval('$cpp_fold_depth', D)
    ;   nb_setval('$cpp_fold_depth', D), fail ).
cpp_fold_depth(D) :- ( catch(nb_getval('$cpp_fold_depth', D), _, fail) -> true ; D = 0 ).
cpp_param_binds([], _, []) :- !.
cpp_param_binds(_, [], []) :- !.
cpp_param_binds([param(_, N)|Ps], [A|As], [N-A|B]) :- !, cpp_param_binds(Ps, As, B).
cpp_param_binds([param(_, N, _)|Ps], [A|As], [N-A|B]) :- !, cpp_param_binds(Ps, As, B).
cpp_param_binds([_|Ps], [_|As], B) :- cpp_param_binds(Ps, As, B).
cpp_replace_ids(id(N), B, A) :- memberchk(N-A, B), !.
cpp_replace_ids(T, B, T1) :- compound(T), !, T =.. [F|Xs], cpp_replace_ids_list(Xs, B, Ys), T1 =.. [F|Ys].
cpp_replace_ids(T, _, T).
cpp_replace_ids_list([], _, []).
cpp_replace_ids_list([X|Xs], B, [Y|Ys]) :- cpp_replace_ids(X, B, Y), cpp_replace_ids_list(Xs, B, Ys).
cpp_type_or_value(D, A) :- ( cpp_is_type(D) -> cpp_type(D, A) ; cpp_targ_value(D, A) ).
%% every type the walk meets goes through here: a template-id becomes its instance's name
cpp_type(T0, T) :- \+ compound(T0), !, T = T0.
cpp_type(base(Q, [typedef(scoped(Path, tmpl(N, Args)))]), T) :-                            % C::template _Select<A, B>: the class's member ALIAS template, in the class's own words
    cpp_scope_class(Path, C), '$cpp_mt'(C, N, TPs, typedef(_, [var(_, T0, _)|_])), !,
    cpp_targ_values(Args, Args1), cpp_bind_targs(TPs, Args1, B), cpp_in_class(C, ( cpp_subst(T0, B, T1), cpp_type(T1, T2) )), cpp_merge_quals(Q, T2, T).
cpp_type(base(Q, [typedef(X)]), T) :- cpp_template_id(X, N, Args), !,                       % the traces fire only under '$cpp_trace': a failure here is otherwise silent
    ( cpp_targ_values(Args, Args1) -> true ; cpp_trace(targ_values_failed(N)), fail ),
    ( cpp_instantiate_type(N, Args1, T0) -> true ; cpp_trace(instantiate_failed(N)), fail ),
    cpp_merge_quals(Q, T0, T).
cpp_type(base(Q, [typedef(scoped(Path, N))]), T) :- cpp_scope_class(Path, C), !,           % C::value_type, X<T>::type: the class's typedef (none: no type -- what SFINAE reads)
    ( cpp_class_typedef(C, N, T0, Def) -> cpp_in_class(Def, cpp_type(T0, T1)), cpp_merge_quals(Q, T1, T), cpp_touch_nested(T1) ; cpp_refuse(0, no_member_type(C, N)) ).
cpp_type(base(Q, [decltype(E)]), T) :- !, cpp_expr(none, E, E1), ( ccl_type_of(E1, T0), T0 \== unknown -> cpp_merge_quals(Q, T0, T) ; cpp_refuse(0, decltype_unknown) ).
cpp_type(base(Q, [builtin_type(N, Args)]), T) :- !, cpp_builtin_type(N, Args, T0), cpp_merge_quals(Q, T0, T).
cpp_type(base(_, [typedef(scoped(Path, N))]), _) :- memberchk(nonclass(A), Path), !, cpp_refuse(0, no_member_type(A, N)).   % a type has no member types (cpp_subst_path)
cpp_type(base(Q, [typedef(scoped(Path, N))]), T) :- atom(N), !,
    ( catch(nb_getval('$cpp_where', W), _, fail) -> true ; W = top ), cpp_trace(flatten(Path, N, in(W))),   % std::string: the namespace flattens (a class the resolver missed flattens too -- the trace tells)
    cpp_type(base(Q, [typedef(N)]), T).   % ... AND THE BARE NAME GOES THROUGH THE HOOK AGAIN: `std::string' is an alias of a template-id, and flattened and left there it reached the lowering as `basic_string<char>' itself
%% A NESTED TYPE NAMED AS A TYPE is registered on the first ask, whatever its kind: its tag must be in the table
%% before anything resolves a member of that type or lays its holder out, and a LAZY library instance never runs
%% the enclosing class's nested registrations. libc++'s `basic_string' names its own `__rep' as a template
%% argument, and that union's members name `__short' and `__long', two more of its nested types.
cpp_type(base(Q, [S]), base(Q, [S])) :- cpp_nested_tag(S, N), '$cpp_nested'(N, _, _, _, _), !, ( cpp_nested_ready(N) -> true ; true ).
cpp_nested_tag(typedef(N), N) :- atom(N).
cpp_nested_tag(union(N, _), N) :- atom(N).
%% A TYPEDEF THAT IS ITS OWN DEFINITION IS LEFT ALONE, never followed: an instance keyed by a FREE name gives its
%% class `typedef value_type value_type' (libc++'s `initializer_list<_Ep>' with `_Ep' unresolved), and resolving
%% that name in that class asked for itself without end -- no refusal, no trace, just terms until the machine gave
%% out. cocolog reclaims nothing along the way, so a loop here is the whole memory (the finding below).
cpp_self_typedef(N, base(_, [typedef(N)])).
cpp_type(base(Q, [typedef(N)]), T) :- atom(N), cpp_class_ctx(C), cpp_class_typedef(C, N, T0, Def), \+ cpp_self_typedef(N, T0), !, cpp_in_class(Def, cpp_type(T0, T1)), cpp_merge_quals(Q, T1, T), cpp_touch_nested(T1).
%% A NESTED CLASS KNOWN BY ITS NAME ALONE -- forward-declared in its holder, defined out of it (`class locale::id')
%% -- is LOADED when its name resolves as a type, so its struct exists where the lowering meets the type; the
%% name road never asked for the class, and `locale::id' reached the lowering as a tag nothing had noted
cpp_touch_nested(base(_, [typedef(N)])) :- atom(N), '$cpp_nested'(N, _, _, _, _), \+ '$cpp_cls'(N, _), !, ( catch(cpp_class(N, _), _, fail) -> true ; true ).
cpp_touch_nested(_).   % value_type inside its class: class scope before namespace scope, as C++ looks names up; a base's typedef in the base's words
cpp_type(base(Q, [typedef(N)]), T) :- atom(N), ccl_typedef_of(N, base(_, [typedef(X)])), cpp_template_id(X, _, _), !,   % `typedef integral_constant<bool, false> false_type', a LIBRARY header's alias
    ( catch(cpp_type(base([], [typedef(X)]), T1), error(not_lowered(W), _), ( cpp_trace(alias_refused(N, W)), fail )) -> cpp_merge_quals(Q, T1, T) ; T = base(Q, [typedef(N)]) ).   % of a template-id: the INSTANCE, not the name -- the passes rebuild the table from the summary, where the alias is raw, so a note behind the name does not survive to the lowering (the program's own typedef item is walked and does). Only an alias whose WHOLE definition is a template-id: a name like `type' is a class's, and the global table's entry for it is some other class's
cpp_type(base(Q, S), base(Q, S)) :- !.
cpp_type(ptr(Q, T0), ptr(Q, T)) :- !, cpp_type(T0, T).
cpp_type(ref(Q, T0), ref(Q, T)) :- !, cpp_type(T0, T).
cpp_type(rref(Q, T0), rref(Q, T)) :- !, cpp_type(T0, T).
cpp_type(arr(N0, T0), arr(N, T)) :- !, cpp_type(T0, T), cpp_array_bound(N0, N).      % the BOUND is an expression too: `char pad[sizeof(T) - datasize<T>]' needs its template instantiated and folded
cpp_array_bound(none, N) :- !, N = none.
cpp_array_bound(int(K), int(K)) :- !.
cpp_array_bound(E0, N) :- ( cpp_class_ctx(C) -> true ; C = none ),
    ( catch(cpp_expr(C, E0, E1), error(not_lowered(_), _), fail) -> true ; E1 = E0 ),
    ( ccl_const_eval(E1, V) -> N = int(V) ; N = E1 ).
cpp_type(fn(R0, Ps0, V), fn(R, Ps, V)) :- !, cpp_type(R0, R), cpp_plain_params(Ps0, Ps).
cpp_type(T, T).
cpp_types([], []).
cpp_types([T0|Ts], [T|Us]) :- cpp_type(T0, T), cpp_types(Ts, Us).
cpp_template_id(tmpl(N, Args), N, Args).
cpp_template_id(scoped(_, tmpl(N, Args)), N, Args).                      % a namespace flattens here too
%% the walk of an instance sees no local of the function that met it: the scopes are set aside
%% a breadcrumb for the trace: what the desugaring is working on, so a silent resolution says where it happened.
%% Scoped, so it names the innermost work and not merely the last thing entered.
cpp_where(W, Goal) :- ( catch(nb_getval('$cpp_where', W0), _, fail) -> true ; W0 = top ), nb_setval('$cpp_where', W),
    ( catch(Goal, E, (nb_setval('$cpp_where', W0), throw(E))) -> nb_setval('$cpp_where', W0) ; nb_setval('$cpp_where', W0), fail ).
cpp_isolated(Goal) :- nb_getval('$ccl_scope', S), nb_setval('$ccl_scope', []),
    ( catch(Goal, E, (nb_setval('$ccl_scope', S), throw(E))) -> nb_setval('$ccl_scope', S) ; nb_setval('$ccl_scope', S), fail ).   % ON A THROW TOO: SFINAE throws and catches by design, and a lost scope left the CALLER's own locals untyped
cpp_add_instance_items(Items) :- cpp_linkonce(Items, Items1), forall(member(I, Items1), assertz('$cpp_out'(I))),
    ( nb_getval('$cpp_in_lib', yes) -> forall(member(function(_, _, _, Name, _, _, _), Items1), assertz('$cpp_libfn'(Name))) ; true ).
%% what a header or a template gives every unit alike links once: linkonce_odr
cpp_linkonce([], []).
cpp_linkonce([function(L, none, R, N, Ps, V, B)|Is], [function(L, linkonce, R, N, Ps, V, B)|Js]) :- !, cpp_linkonce(Is, Js).
cpp_linkonce([I|Is], [I|Js]) :- cpp_linkonce(Is, Js).
%% a class template at its arguments: registered and desugared like a class written out, once
%% the budget: a program's instantiations and header loads are hundreds; libc++'s closure, pulled in whole, is
%% tens of thousands and took the machine's memory once -- past the budget the compile stops with a diagnostic
cpp_spend(What) :- nb_getval('$cpp_budget', K), K1 is K + 1, nb_setval('$cpp_budget', K1), ( K1 > 3000 -> cpp_refuse(0, instantiation_budget(K1, What)) ; true ),
    cpp_trace(spend(K1, What)).
cpp_trace(T) :- ( nb_getval('$cpp_trace', yes) -> write(T), nl, flush_output ; true ).
cpp_deeper(What) :- nb_getval('$cpp_depth', D), D1 is D + 1, nb_setval('$cpp_depth', D1), ( D1 > 120 -> cpp_refuse(0, instantiation_depth(D1, What)) ; true ).
cpp_shallower :- nb_getval('$cpp_depth', D), D1 is D - 1, nb_setval('$cpp_depth', D1).
cpp_instantiate_class(N, Args, Name) :- cpp_where(class(N), cpp_instantiate_class__(N, Args, Name)).
cpp_instantiate_class__(N, Args, Name) :-
    cpp_deeper(N), ( catch(cpp_instantiate_class_(N, Args, Name), E, (cpp_shallower, throw(E))) -> cpp_shallower ; cpp_shallower, fail ).
%% AN INSTANCE ASKED FOR AGAIN ANSWERS ITS NAME AND NOTHING ELSE. A clause retrieval COPIES the term it answers
%% (the finding below, for globals; a fact's body is no different), and a template's item is its whole class --
%% hundreds of members for one of libc++'s containers. Every ask fetched that item to compute a name it had
%% computed before: `std::string s; s += "x";' asks for `allocator_traits<allocator<char>>' 267 times and for
%% `__allocator_traits_base' 283, and the desugaring took 2.9 GB where the read took 48 MB. Args are compared with
%% `==', never unified, so an unbound argument matches nothing.
cpp_instantiate_class_(N, Args, Name) :- '$cpp_iname'(N, A, Name0), A == Args, !, Name = Name0.
cpp_instantiate_class_(N, Args, Name) :-
    ( cpp_class_template(N, TPs, Item) -> true ; cpp_refuse(0, template_without_body(N)) ),
    ( cpp_bind_targs(TPs, Args, B) -> true ; cpp_trace(bind_failed(N)), fail ),
    cpp_constraints_hold(N, TPs, B),
    ( cpp_instance_name(N, TPs, B, Name) -> cpp_trace(want(Name)) ; cpp_trace(name_failed(N)), fail ),
    assertz('$cpp_iname'(N, Args, Name)),
    (   cpp_instance_done(Name) -> true
    ;   \+ \+ ( cpp_spend(instance(Name)), cpp_full_args(TPs, B, FullArgs), cpp_instance_note(Name, inst(N, FullArgs)),
                Self = N-base([], [typedef(Name)]),                                                                % the injected class name: inside its body, `vector' is this instance
                (   cpp_pick_spec(N, FullArgs, SB, SItem), cpp_template_defined(SItem) -> cpp_subst(SItem, [Self|SB], Item1), cpp_instance_body(N, Name, FullArgs, Item1)   % a specialization only where it HAS a body: a forward-declared one is not the definition
                ;   cpp_template_defined(Item) -> cpp_subst(Item, [Self|B], Item1), cpp_instance_body(N, Name, FullArgs, Item1)
                ;   cpp_incomplete_instance(N, Name) ) ) ).
%% A CLASS TEMPLATE DECLARED AND NEVER DEFINED is an INCOMPLETE TYPE, which C++ lets a template argument name:
%% libc++ dispatches its algorithms on `__specialized_algorithm<_Algorithm::__fill_n, __single_iterator<_It>>',
%% and `__single_iterator' is declared only -- a tag, never an object. The instance is its NAME and its arguments,
%% which is what a specialization's pattern matches on; asking it for a member finds no class and refuses there.
cpp_incomplete_instance(N, _) :- '$cpp_tmpl'(N, _, I), cpp_template_defined(I), !, cpp_refuse(0, template_without_body(N)).   % a body registered elsewhere and not taken: the old diagnostic
cpp_incomplete_instance(_, Name) :- cpp_trace(incomplete(Name)).
cpp_instance_body(N, Name, FullArgs, Item1) :-
    ( cpp_instance_class(Item1, L, K, Bases, Ms0) -> true ; cpp_refuse(0, instance_without_body(N)) ), cpp_lib_origin(N, Lib),
    cpp_member_defs(N, Name, FullArgs, Ms0, Ms),                                          % the members DEFINED out of the class: their bodies, substituted with this instance's arguments
    cpp_lazy_instance(Lib, Name),                                                         % a LIBRARY template's instance is lazy, as a library class already is: its members come as they are used
    (   cpp_as_lib(Lib, ( cpp_isolated(( cpp_register_class(L, Name, Bases, Ms),
                                        ( cpp_item(declare(L, base([], [class(K, Name, Bases, Ms)])), Items) -> true ; cpp_refuse(L, instance_not_emitted(Name)) ) )),
                          cpp_add_instance_items(Items) ))
    ->  true ; cpp_refuse(0, instance_not_emitted(Name)) ).
%% ---- A CLASS TEMPLATE'S MEMBER DEFINED OUT OF ITS CLASS ---------------------------------------------
%% `template <class _Tp, class _Allocator> void __vector_layout<_Tp, _Allocator>::__set_bound_using_pointer(
%%  pointer __p) noexcept { ... }' is how libc++ writes half of a container's members: the class's own member
%% is a DECLARATION. Such an item was dropped at registration, so an instance took its body from nowhere --
%% a bodyless function, a `declare' in the IR, and the linker saying the symbol is undefined. Every one of them
%% is kept by its CLASS's name ('$cpp_mdef'(Class, MemberKey, TParams, Pattern, Member)), and an instance takes
%% the definition whose pattern matches its arguments and whose parameters key alike -- a MEMBER TEMPLATE among
%% them (`template <class _Tp> template <class... _Args> ... vector<_Tp>::emplace_back(_Args &&...)'), whose own
%% parameters shadow the class's and wait for the call.
cpp_mdef_item(function(L, Sto, Ret, scoped(Path, M), Ps, V, Body), C, Pat, method(L, Qs, Ret, M, Ps, V, Body)) :-
    Body \== none, cpp_mdef_class(Path, C, Pat), cpp_mdef_name(M), ( Sto == none -> Qs = [] ; Qs = [Sto] ).
cpp_mdef_item(template(L, TPs, I), C, Pat, template(L, TPs, M)) :- cpp_mdef_item(I, C, Pat, M).
%% ... AND THE MEMBERS OF A NESTED CLASS DEFINED OUT OF ITS ENCLOSING CLASS TEMPLATE, `template <...> basic_ostream<
%% _CharT, _Traits>::sentry::sentry(basic_ostream &)': kept by the enclosing class's name under the key
%% nested_member(sentry, ...), bound by its template-id's pattern as any member's is, and merged into the nested
%% class's own members when the instance's are (cpp_nested_defs) -- so the nested class registers with its bodies.
cpp_mdef_item(function(L, Sto, Ret, scoped(Path, M), Ps, V, Body), C, Pat, in_nested(N, method(L, Qs, Ret, M, Ps, V, Body))) :-
    Body \== none, append(Front, [N], Path), atom(N), ccl_last(Front, tmpl(C, Pat)), cpp_mdef_name(M), ( Sto == none -> Qs = [] ; Qs = [Sto] ), !.
cpp_mdef_item(ctor_def(L, scoped(Path, N), Qs, Ps, Inits, Body), C, Pat, in_nested(N, ctor(L, Qs, Ps, Inits, Body))) :- atom(N), Body \== none, cpp_mdef_class(Path, C, Pat).
cpp_mdef_item(dtor_def(L, scoped(Path, N), Qs, Body), C, Pat, in_nested(N, dtor(L, Qs, Body))) :- atom(N), Body \== none, cpp_mdef_class(Path, C, Pat).
cpp_mdef_item(ctor_def(L, C, Qs, Ps, Inits, Body), C, none, ctor(L, Qs, Ps, Inits, Body)) :- atom(C), Body \== none.
cpp_mdef_item(dtor_def(L, C, Qs, Body), C, none, dtor(L, Qs, Body)) :- atom(C), Body \== none.
%% ... AND A NESTED CLASS DEFINED OUT OF ITS CLASS TEMPLATE: `template <class _CharT, class _Traits> class
%% basic_ostream<_CharT, _Traits>::sentry { ... }', the class declaring only `class sentry;' -- kept by the class's
%% name like a member's body, and merged into the instance's forward declaration (cpp_member_def), which the
%% nested-class machinery then registers as any nested class. Unindexed, the body never reached the instance, and
%% every `sentry __s(*this)' in the stream's members was initialized as a plain value.
cpp_mdef_item(declare(L, base(Q, [class(K, scoped(Path, Nested), Bases, Ms)])), C, Pat, nested(base(Q, [class(K, Nested, Bases, Ms)]))) :-
    atom(Nested), Ms \== none, cpp_mdef_class(Path, C, Pat), ( atom(L) -> true ; true ).
cpp_mdef_class(Path, C, Pat) :- ccl_last(Path, S), ( S = tmpl(C, Pat) -> true ; atom(S), C = S, Pat = none ).
cpp_mdef_name(M) :- ( atom(M) -> true ; M = operator(_) ).
cpp_mdef_put(C, TPs, Pat, Member) :- cpp_member_shape(Member, K, _, _), assertz('$cpp_mdef'(C, K, TPs, Pat, Member)).
%% a member's key, its parameters and its body, the member template's own wrapper looked through
cpp_member_shape(template(_, _, M), K, Ps, B) :- !, cpp_member_shape(M, K, Ps, B).
cpp_member_shape(method(_, _, _, M, Ps, _, B), M, Ps, B).
cpp_member_shape(ctor(_, _, Ps, _, B), '$ctor', Ps, B).
cpp_member_shape(dtor(_, _, B), '$dtor', [], B).
cpp_member_shape(in_nested(N, M), nested_member(N, K), Ps, B) :- !, cpp_member_shape(M, K, Ps, B).   % a nested class's member defined out of the enclosing class
cpp_member_shape(nested(base(_, [class(_, N, _, Ms)])), nested(N), [], Ms).       % a nested class, defined ...
cpp_member_shape(nested(base(_, [class(N, none)])), nested(N), [], none).         % ... or only declared inside its holder
cpp_member_shape(nested(base(_, [struct(N, Ms)])), nested(N), [], Ms).
cpp_member_defs(N, _, _, Ms, Ms) :- \+ '$cpp_mdef'(N, _, _, _, _), !.
cpp_member_defs(N, Name, Args, Ms0, Ms) :- findall(M, ( member(M0, Ms0), cpp_member_def(N, Name, Args, M0, M) ), Ms).
cpp_member_def(N, Name, Args, M0, M) :- cpp_member_def_key(N, Name, Args, plain, M0, M1), cpp_nested_defs(N, Name, Args, M1, M).
cpp_member_def_key(N, Name, Args, Where, M0, M) :-
    (   cpp_member_shape(M0, K, Ps, none), cpp_params_key(Ps, PK), cpp_mdef_key(Where, K, Key),
        '$cpp_mdef'(N, Key, TPs, Pat, Item0), cpp_mdef_inner(Item0, Item), cpp_mdef_bind(Pat, Args, TPs, B),
        cpp_subst(Item, [N-base([], [typedef(Name)])|B], M1), cpp_member_shape(M1, K, Ps1, B1), B1 \== none, cpp_params_key(Ps1, PK)
    ->  cpp_keep_defaults(Ps, Ps1, Ps2), cpp_member_params(M1, Ps2, M)     % the DEFINITION's body with the DECLARATION's default arguments
    ;   M = M0 ).
cpp_mdef_key(plain, K, K).
cpp_mdef_key(nested(Nested), K, nested_member(Nested, K)).
cpp_mdef_inner(in_nested(_, Item), Item) :- !.
cpp_mdef_inner(template(L, TPs, in_nested(_, Item)), template(L, TPs, Item)) :- !.
cpp_mdef_inner(Item, Item).
%% a nested class's members, once the class itself is whole: each bodyless one takes its definition from the
%% enclosing class's records, keyed nested_member(Nested, K)
cpp_nested_defs(N, Name, Args, nested(base(Q, [class(K, Nested, Bases, NMs0)])), nested(base(Q, [class(K, Nested, Bases, NMs)]))) :-
    is_list(NMs0), atom(Nested), '$cpp_mdef'(N, nested_member(Nested, _), _, _, _), !,
    findall(M, ( member(M0, NMs0), cpp_member_def_key(N, Name, Args, nested(Nested), M0, M) ), NMs).
cpp_nested_defs(_, _, _, M, M).
%% A DEFAULT ARGUMENT BELONGS TO THE DECLARATION, and C++ forbids repeating it on an out-of-class definition -- so
%% taking the definition whole threw the defaults away, and libc++'s `__grow_by_without_replace(a, b, c, d, 0)',
%% five arguments to six parameters, found no member of that arity at all.
cpp_keep_defaults([], Ps, Ps) :- !.
cpp_keep_defaults(_, [], []) :- !.
cpp_keep_defaults([param(_, _, D)|Ps0], [param(T, N)|Ps1], [param(T, N, D)|Ps2]) :- !, cpp_keep_defaults(Ps0, Ps1, Ps2).
cpp_keep_defaults([_|Ps0], [P|Ps1], [P|Ps2]) :- cpp_keep_defaults(Ps0, Ps1, Ps2).
cpp_member_params(template(L, TPs, M0), Ps, template(L, TPs, M)) :- !, cpp_member_params(M0, Ps, M).
cpp_member_params(method(L, Q, R, M, _, V, B), Ps, method(L, Q, R, M, Ps, V, B)) :- !.
cpp_member_params(ctor(L, Q, _, I, B), Ps, ctor(L, Q, Ps, I, B)) :- !.
cpp_member_params(M, _, M).
cpp_mdef_bind(none, Args, TPs, B) :- !, cpp_bind_targs(TPs, Args, B).       % a constructor's and a destructor's: the reader gives the class's bare name, so the parameters bind in order
cpp_mdef_bind(Pat, Args, TPs, B) :- cpp_match_pattern(Pat, Args, TPs, [], B).
cpp_instance_class(declare(L, base(_, [class(K, _, Bases, Ms)])), L, K, Bases, Ms) :- Ms \== none.
cpp_instance_class(declare(L, base(_, [struct(_, Ms)])), L, struct, [], Ms) :- Ms \== none.
%% the arguments in the parameters' order, a pack's spliced: what a specialization's pattern is matched against
cpp_full_args([], _, []).
cpp_full_args([requires(_)|TPs], B, As) :- !, cpp_full_args(TPs, B, As).
cpp_full_args([tparam(_, P, _)|TPs], B, As) :- memberchk(P-A, B), ( cpp_pack_list(A, L) -> append(L, As1, As) ; As = [A|As1] ), cpp_full_args(TPs, B, As1).
%% the specialization whose pattern matches, the most specialized of those that do (X is more specialized than Y when
%% X's pattern, taken as arguments, matches Y's)
cpp_pick_spec(N, Args, SB, Item) :-
    findall(m(TPs, Pat, It), '$cpp_spec'(N, TPs, Pat, It), Cands), Cands \== [],
    findall(m(TPs, Pat, It, B), ( member(m(TPs, Pat, It), Cands), cpp_match_pattern(Pat, Args, TPs, [], B) ), Ms0), Ms0 \== [],
    %% A DEFINITION BEFORE A FORWARD DECLARATION of the same specialization: libc++ declares `struct char_traits<char>;'
    %% early and defines it later, both matching `[char]' and equally specialized, so the empty one won and every
    %% `traits_type::copy' was a call to nothing. A declared-only specialization still stands where none is defined
    %% (an incomplete type a template argument may name).
    ( findall(M, ( member(M, Ms0), M = m(_, _, I2, _), cpp_template_class_def(I2) ), [D|Ds]) -> Ms = [D|Ds] ; Ms = Ms0 ),
    cpp_most_special(Ms, Ms, m(_, _, Item, SB)).
cpp_most_special([M|_], All, M) :- \+ ( member(Y, All), Y \== M, cpp_more_special(Y, M), \+ cpp_more_special(M, Y) ), !.
cpp_most_special([_|Ms], All, M) :- cpp_most_special(Ms, All, M).
cpp_more_special(m(TPsX, PatX, _, _), m(TPsY, PatY, _, _)) :- cpp_pattern_as_args(PatX, TPsX, ArgsX), cpp_match_pattern(PatY, ArgsX, TPsY, [], _).
cpp_pattern_as_args([], _, []).
cpp_pattern_as_args([pack(_)|Ps], TPs, As) :- !, cpp_pattern_as_args(Ps, TPs, As).
cpp_pattern_as_args([P|Ps], TPs, [P|As]) :- cpp_pattern_as_args(Ps, TPs, As).
%% two passes, as the standard deduces: the deducible elements bind the parameters, then every NON-DEDUCED element
%% -- an alias template's template-id, a name qualified by a parameter (`typename T::x'), a decltype -- is
%% substituted, resolved and compared with its argument; a refusal in that resolution is no match, which is the
%% SFINAE of the detection idiom: `__detector<_Default, __void_t<_Op<_Args...>>, _Op, _Args...>' is chosen only
%% where `_Op<_Args...>' has a type
cpp_match_pattern(Ps, As, TPs, B0, B) :- cpp_match_deducible(Ps, As, TPs, B0, B1, Later), cpp_match_later(Later, TPs, B1), B = B1.
cpp_match_deducible([], [], _, B, B, []).
cpp_match_deducible([pack(base(_, [typedef(P)]))], Args, TPs, B0, [P-pack(Args)|B0], []) :- memberchk(tparam(pack, P, _), TPs), !.
cpp_match_deducible([pack(id(P))], Args, TPs, B0, [P-pack(Args)|B0], []) :- memberchk(tparam(vpack(_), P, _), TPs), !.
cpp_match_deducible([P|Ps], [A|As], TPs, B0, B, Later) :-
    (   cpp_non_deduced(P, TPs) -> B1 = B0, Later = [P-A|Later1]
    ;   cpp_match_one(P, A, TPs, B0, B1), Later = Later1 ),
    cpp_match_deducible(Ps, As, TPs, B1, B, Later1).
cpp_non_deduced(base(_, [typedef(tmpl(N, _))]), TPs) :- atom(N), \+ memberchk(tparam(template, N, _), TPs), cpp_alias_template(N), !.
cpp_non_deduced(base(_, [typedef(scoped(_, tmpl(N, _)))]), TPs) :- atom(N), \+ memberchk(tparam(template, N, _), TPs), cpp_alias_template(N), !.
cpp_non_deduced(base(_, [typedef(scoped(Path, _))]), TPs) :- member(S, Path), atom(S), memberchk(tparam(_, S, _), TPs), !.
cpp_non_deduced(base(_, [decltype(_)]), _).
cpp_match_later([], _, _).
cpp_match_later([P-A|Ls], TPs, B) :- cpp_subst(P, B, P1),
    ( \+ ( member(tparam(_, Q, _), TPs), cpp_names_in(P1, Q) ) -> true ; cpp_trace(later_free(P1)), fail ),   % a parameter still free in it: no match
    ( catch(cpp_type(P1, T), error(not_lowered(W), _), ( cpp_trace(later_refused(W)), fail )) -> true ; cpp_trace(later_failed(P1)), fail ),
    ( cpp_same_type(T, A) -> true ; cpp_trace(later_differs(T, A)), fail ),
    cpp_match_later(Ls, TPs, B).
cpp_match_one(base(Q, [typedef(P)]), A, TPs, B0, B) :- memberchk(tparam(type, P, _), TPs), !,
    cpp_pattern_quals(Q, A, A1),                                                     % `numeric_limits<const _Tp>' matches only a CONST argument, and binds _Tp to it WITHOUT the const -- the qualifiers were ignored, so it matched everything and the class derived from itself
    ( memberchk(P-A0, B0) -> cpp_same_type(A0, A1), B = B0 ; B = [P-A1|B0] ).
cpp_pattern_quals([], A, A) :- !.
cpp_pattern_quals(Q, base(Q0, S), base(Q1, S)) :- forall(member(X, Q), memberchk(X, Q0)), findall(Y, ( member(Y, Q0), \+ memberchk(Y, Q) ), Q1).
cpp_match_one(base(_, [typedef(P)]), tname(X), TPs, B0, B) :- memberchk(tparam(template, P, _), TPs), !, ( memberchk(P-A0, B0) -> A0 == tname(X), B = B0 ; B = [P-tname(X)|B0] ).
cpp_match_one(base(_, [typedef(X)]), tname(X), _, B, B) :- !.
cpp_match_one(id(P), A, TPs, B0, B) :- memberchk(tparam(K, P, _), TPs), \+ memberchk(K, [type, pack, template]), !, ( memberchk(P-A0, B0) -> cpp_same_value(A0, A), B = B0 ; B = [P-A|B0] ).
cpp_match_one(base(_, [typedef(tmpl(N, Sub))]), A, TPs, B0, B) :- !, cpp_match_tmpl(N, Sub, A, TPs, B0, B).
cpp_match_one(base(_, [typedef(scoped(_, tmpl(N, Sub)))]), A, TPs, B0, B) :- !, cpp_match_tmpl(N, Sub, A, TPs, B0, B).
cpp_match_tmpl(N, Sub, A, TPs, B0, B) :- memberchk(tparam(template, N, _), TPs), !,               % `_Sp<_Tp, _Args...>': the template deduced too (tname)
    cpp_instance_of(A, N1, SubArgs), ( memberchk(N-tname(N0), B0) -> N0 == N1, B1 = B0 ; B1 = [N-tname(N1)|B0] ), cpp_match_pattern(Sub, SubArgs, TPs, B1, B).
cpp_match_tmpl(N, Sub, A, TPs, B0, B) :- cpp_instance_of(A, N, SubArgs), cpp_match_pattern(Sub, SubArgs, TPs, B0, B).
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
%% a function template at a call: its type arguments explicit, then deduced from the arguments' types, then defaulted.
%% The candidates are every DEFINITION of the name, in declaration order (a prototype is a declaration item, not a
%% function); one whose signature does not hold -- the arity, a deduction, a default, a value parameter's type, a
%% class-typed parameter's argument, the constraints -- is no candidate (SFINAE), and of those that hold the MOST
%% SPECIALIZED wins: X is more specialized than Y when Y's parameter types deduce from X's, taken as arguments with X's
%% own parameters opaque (`swap(vector<T, A> &, ...)' over `swap(T &, T &)'); the first declared among equals.
cpp_instantiate_function(F, Explicit, As, Name) :- cpp_where(fn(F), cpp_instantiate_function__(F, Explicit, As, Name)).
cpp_instantiate_function__(F, Explicit, As, Name) :-
    ( nb_getval('$cpp_trace', yes) -> findall(A-T, ( member(A, As), ( ccl_type_of(A, T0), T0 \== unknown -> T = T0 ; T = unknown ) ), ATs), cpp_trace(call_types(F, ATs)) ; true ),
    findall(TPs-Fn, ( cpp_template(F, TPs, Item), cpp_fn_item(Item, Fn) ), Cands0),     % assertz: declaration order
    cpp_fn_merge_defaults(F, Cands0, Cands),
    length(Cands, NC), nb_setval('$cpp_first_refusal', none),
    cpp_holding_candidates(Cands, 1, F, Explicit, As, Hs),
    (   Hs == [] -> nb_getval('$cpp_first_refusal', W), ( W == none -> cpp_refuse(0, no_matching_template(F)) ; cpp_refuse(0, W) )   % none fit: the first one's reason
    ;   cpp_fewest_conversions(Hs, Hs1), cpp_defined_first(Hs1, Hs2), cpp_most_special_fn(Hs2, Hs2, h(K, TPs, function(L, Sto, Ret, _, Ps, V, Body), B, _)),
        ( NC =:= 1 -> FN = F ; atomic_list_concat([F, '.c', K], FN) ), cpp_instance_name(FN, TPs, B, Name),
        cpp_instantiate_function_(F, TPs, B, L, Sto, Ret, Ps, V, Body, Name) ).
%% A FUNCTION TEMPLATE'S REDECLARATION TAKES THE DEFAULTS OF ITS FIRST DECLARATION: C++ lets a default template
%% argument stand on the first declaration only, so libc++ writes `template <class _Tp, __enable_if_t<..., int> =
%% 0>' on the prototype and `template <class _Tp, __enable_if_t<..., int>>' on the definition below it -- and the
%% definition refused cannot_deduce(anon) while the prototype held and was emitted as a declare: `__to_chars_integral',
%% the last symbol between `std::cout << "hello"' and a binary. The other declarations of the name with the same
%% parameter list lend theirs, as a class template's declarations do (cpp_merge_defaults, 0.44).
cpp_fn_merge_defaults(F, Cands, Merged) :- findall(TPs1-Fn, ( member(TPs0-Fn, Cands), cpp_fn_lend_defaults(F, TPs0, Fn, Cands, TPs1) ), Merged).
cpp_fn_lend_defaults(F, TPs0, function(_, _, _, _, Ps, _, _), Cands, TPs) :-
    cpp_params_key(Ps, K),
    findall(F-tmpl(TPs2, x), ( member(TPs2-function(_, _, _, _, Ps2, _, _), Cands), TPs2 \== TPs0, cpp_params_key(Ps2, K), cpp_same_tparams(TPs0, TPs2) ), Ts),
    ( Ts == [] -> TPs = TPs0 ; cpp_merge_defaults(F, TPs0, Ts, TPs) ).
%% ... a REDECLARATION only: the same template parameters, kind for kind and name for name (another overload over
%% the same value parameters lends nothing -- its defaults mean something else)
cpp_same_tparams([], []).
cpp_same_tparams([tparam(K, P, _)|Ps], [tparam(K, P, _)|Qs]) :- cpp_same_tparams(Ps, Qs).
cpp_same_tparams([requires(_)|Ps], Qs) :- !, cpp_same_tparams(Ps, Qs).
cpp_same_tparams(Ps, [requires(_)|Qs]) :- !, cpp_same_tparams(Ps, Qs).
%% a function template's item: its definition, or a DECLARATION with no body -- `template <class T> T &&declval();'
%% is never called, and a decltype wants only its return type
cpp_fn_item(function(L, Sto, Ret, N, Ps, V, Body), function(L, Sto, Ret, N, Ps, V, Body)).
cpp_fn_item(declaration(L, Sto, _, [var(N, fn(Ret, Ps, V), none)]), function(L, Sto, Ret, N, Ps, V, none)) :- atom(N).
cpp_holding_candidates([], _, _, _, _, []).
cpp_holding_candidates([TPs-Fn|Cs], K, F, Explicit, As, Hs) :-
    Fn = function(_, _, Ret, _, Ps, Var, _), nb_setval('$cpp_last_refusal', failed), nb_setval('$cpp_conversions', 0),
    (   catch(( cpp_signature_holds(F, TPs, Ps, Var, Explicit, As, B), cpp_result_holds(Ret, B) ), error(not_lowered(W), _), cpp_note_refusal(W))   % SFINAE: a signature that does not hold is no candidate
    ->  nb_getval('$cpp_conversions', Conv), cpp_trace(candidate(F, K, holds(Conv))), Hs = [h(K, TPs, Fn, B, Conv)|Hs1]
    ;   nb_getval('$cpp_last_refusal', W1), cpp_trace(candidate(F, K, refused(W1))), Hs = Hs1 ),
    K1 is K + 1, cpp_holding_candidates(Cs, K1, F, Explicit, As, Hs1).
%% THE RESULT TYPE IS PART OF THE SIGNATURE, C++'s immediate context: `typename __sfinae_underlying_type<_Tp>::__promoted_type
%% __convert_to_integral(_Tp)' is NO CANDIDATE for a _Tp that is no enum, since the trait's specialization for a non-enum has
%% no such member -- and libc++ writes the overload that way on purpose. Only a DEPENDENT QUALIFIED NAME is resolved here
%% (`typename X<T>::y'), the one shape written to fail: an auto or a decltype result is deduced later, from the body, and a
%% plain type or a template-id costs an instantiation a refused candidate need not make.
cpp_result_holds(Ret, B) :- cpp_subst(Ret, B, Ret1), ( cpp_sfinae_result(Ret1) -> cpp_type(Ret1, _) ; true ).
cpp_sfinae_result(base(_, [typedef(scoped(_, _))])) :- !.
cpp_sfinae_result(ptr(_, T)) :- cpp_sfinae_result(T).
cpp_sfinae_result(ref(_, T)) :- cpp_sfinae_result(T).
cpp_sfinae_result(rref(_, T)) :- cpp_sfinae_result(T).
cpp_note_refusal(W) :- nb_setval('$cpp_last_refusal', W), nb_getval('$cpp_first_refusal', W0), ( W0 == none -> nb_setval('$cpp_first_refusal', W) ; true ), fail.
%% an exact match beats one that converts (a derived object to a base's reference, a value to a class through a
%% constructor): the candidates with the fewest conversions, then the most specialized of those
cpp_fewest_conversions(Hs, Best) :- findall(C, member(h(_, _, _, _, C), Hs), [C0|Cs]), cpp_min_of(Cs, C0, Min), findall(H, ( member(H, Hs), H = h(_, _, _, _, Min) ), Best).
cpp_min_of([], M, M).
cpp_min_of([C|Cs], M0, M) :- ( C < M0 -> cpp_min_of(Cs, C, M) ; cpp_min_of(Cs, M0, M) ).
cpp_converted :- nb_getval('$cpp_conversions', C), C1 is C + 1, nb_setval('$cpp_conversions', C1).
%% a DECLARATION and a DEFINITION of one template are one entity: the definition is what an instance is made from,
%% and a declaration is a candidate only when nothing is defined (declval, whose type is all a decltype wants)
cpp_defined_first(Hs, Best) :- findall(H, ( member(H, Hs), H = h(_, _, function(_, _, _, _, _, _, Body), _, _), Body \== none ), Ds),
    ( Ds == [] -> Best = Hs ; Best = Ds ).
cpp_most_special_fn([H|_], All, H) :- \+ ( member(Y, All), Y \== H, cpp_fn_more_special(Y, H), \+ cpp_fn_more_special(H, Y) ), !.
cpp_most_special_fn([_|Hs], All, H) :- cpp_most_special_fn(Hs, All, H).
cpp_fn_more_special(h(_, TPsX, function(_, _, _, _, PsX, _, _), _, _), h(_, TPsY, function(_, _, _, _, PsY, _, _), _, _)) :-
    cpp_opaque_bindings(TPsX, BX), cpp_subst(PsX, BX, PsX1), cpp_param_types(PsX1, TsX0), cpp_opaque_types(TsX0, TsX), cpp_param_types(PsY, TsY),
    length(TsX, N), length(TsY, N),
    catch(cpp_deduce_types(TsY, TsX, TPsY, [], B), error(not_lowered(_), _), fail), cpp_all_bound(TPsY, TsY, B).
%% ... and a TEMPLATE-ID OVER OPAQUE NAMES among X's parameter types is an INCOMPLETE INSTANCE (0.58's: a name and
%% its arguments, recorded, no body), never instantiated: `ostreambuf_iterator<$opaque._CharT, $opaque._Traits>'
%% resolved as a class refused, so that overload of __pad_and_output was no more special than the generic one over
%% `_OutputIterator', the tie went to the first declared, and the generic one ran a stream through std::copy.
cpp_opaque_types([], []).
cpp_opaque_types([T0|Ts], [T|Us]) :- cpp_opaque_type(T0, T), cpp_opaque_types(Ts, Us).
cpp_opaque_type(base(Q, [typedef(X)]), base(Q, [typedef(Name)])) :- cpp_template_id(X, N, Args), cpp_has_opaque(Args),
    catch(( findall(K, ( member(A, Args), cpp_type_key(A, K) ), Ks), atomic_list_concat([N|Ks], '.', Name) ), _, fail), !,
    ( '$cpp_inst'(Name, _) -> true ; assertz('$cpp_inst'(Name, inst(N, Args))) ).
cpp_opaque_type(ptr(Q, T0), ptr(Q, T)) :- !, cpp_opaque_type(T0, T).
cpp_opaque_type(ref(Q, T0), ref(Q, T)) :- !, cpp_opaque_type(T0, T).
cpp_opaque_type(rref(Q, T0), rref(Q, T)) :- !, cpp_opaque_type(T0, T).
cpp_opaque_type(T, T).
cpp_has_opaque(T) :- atom(T), !, sub_atom(T, 0, 8, _, '$opaque.').
cpp_has_opaque(T) :- compound(T), T =.. [_|As], member(A, As), cpp_has_opaque(A), !.
cpp_opaque_bindings([], []).
cpp_opaque_bindings([tparam(K, P, _)|TPs], [P-A|B]) :- !, atom_concat('$opaque.', P, O),
    ( K == type -> A = base([], [typedef(O)]) ; K == template -> A = tname(O) ; cpp_pack_kind(K) -> A = pack([base([], [typedef(O)])]) ; A = id(O) ),
    cpp_opaque_bindings(TPs, B).
cpp_opaque_bindings([_|TPs], B) :- cpp_opaque_bindings(TPs, B).
cpp_param_types([], []).
cpp_param_types([param(T, _)|Ps], [T|Ts]) :- !, cpp_param_types(Ps, Ts).
cpp_param_types([param(T, _, _)|Ps], [T|Ts]) :- !, cpp_param_types(Ps, Ts).
cpp_param_types([_|Ps], Ts) :- cpp_param_types(Ps, Ts).
cpp_deduce_types([], [], _, B, B).
cpp_deduce_types([P|Ps], [A|As], TPs, B0, B) :- cpp_match(P, A, TPs, B0, B1), cpp_deduce_types(Ps, As, TPs, B1, B).
cpp_all_bound(TPs, Ts, B) :- \+ ( member(tparam(_, P, _), TPs), cpp_names_in(Ts, P), \+ memberchk(P-_, B) ).
cpp_path_dependent(Path, TPs) :- member(tparam(_, P, _), TPs), cpp_names_in(Path, P), !.
cpp_signature_holds(F, TPs, Ps, Explicit, As, B) :- cpp_signature_holds(F, TPs, Ps, false, Explicit, As, B).
cpp_signature_holds(F, TPs, Ps, Var, Explicit, As, B) :- cpp_where(sig(F), cpp_signature_holds_(F, TPs, Ps, Var, Explicit, As, B)).
cpp_signature_holds_(F, TPs, Ps, Var, Explicit, As, B) :-
    cpp_arity_holds(Ps, Var, As),
    cpp_bind_explicit(TPs, Explicit, B0), cpp_deduce_args(Ps, As, TPs, B0, B1), cpp_bind_defaults(TPs, B1, B), cpp_constraints_hold(F, TPs, B),
    cpp_params_accept(Ps, As, B).
%% the arguments must fit the parameters in number: a default fills, a pack takes any number
cpp_arity_holds(Ps, Var, As) :- length(As, NA), cpp_arity(Ps, Min, Max), NA >= Min, ( Var == true -> true ; Max == any -> true ; NA =< Max ), !.   % `...' takes any number
cpp_arity_holds(_, _, _) :- cpp_refuse(0, arity_mismatch).
cpp_arity([], 0, 0).
cpp_arity([param(pack(_), _)|_], 0, any) :- !.
cpp_arity([param(_, _, _)|Ps], Min, Max) :- !, cpp_arity(Ps, Min, Max0), ( Max0 == any -> Max = any ; Max is Max0 + 1 ).
cpp_arity([param(_, _)|Ps], Min, Max) :- !, cpp_arity(Ps, Min0, Max0), Min is Min0 + 1, ( Max0 == any -> Max = any ; Max is Max0 + 1 ).
cpp_arity([_|Ps], Min, Max) :- cpp_arity(Ps, Min, Max).
%% a class-typed parameter (under the bindings) takes an argument of that class, or of a class derived from it, or --
%% for an argument of no class -- a class with a one-argument constructor; a scalar parameter takes no class unless it
%% has a conversion operator; an argument the inference cannot type passes
cpp_params_accept([], _, _).
cpp_params_accept(_, [], _).
cpp_params_accept([param(pack(_), _)|_], _, _) :- !.
cpp_params_accept([P|Ps], [A|As], B) :- ( P = param(PT0, _) ; P = param(PT0, _, _) ), !,
    cpp_subst(PT0, B, PT), ( cpp_param_accepts(PT, A) -> true ; cpp_refuse(0, argument_mismatch) ), cpp_params_accept(Ps, As, B).
cpp_params_accept([_|Ps], [_|As], B) :- cpp_params_accept(Ps, As, B).
cpp_param_accepts(PT, A) :- ( ccl_type_of(A, AT), AT \== unknown -> ccl_unref(PT, PT1), ccl_unref(AT, AT1), cpp_type_accepts(PT1, AT1) ; true ).
cpp_type_accepts(PT, AT) :- cpp_type(PT, PT2), cpp_class_of_type(PT2, C), !, ( cpp_class_of_type(AT, D) -> ( D == C -> true ; cpp_class_fits(D, C), cpp_converted ) ; cpp_converting(C), cpp_converted ).
cpp_type_accepts(PT, AT) :- ccl_resolve_type(PT, RP), cpp_scalar_mismatch(RP, AT), !, fail.   % NO STANDARD CONVERSION: a pointer to an arithmetic parameter (a bool takes one), an arithmetic value to a pointer parameter -- `cout << "hello"' took the CHAR inserter, `operator<<(basic_ostream<_CharT, _Traits> &, _CharT)', and passed the literal's address truncated to a byte
cpp_type_accepts(_, AT) :- ( cpp_class_of_type(AT, D) -> cpp_has_conversion(D), cpp_converted ; true ).
cpp_scalar_mismatch(RP, AT) :- ccl_is_arith(RP), \+ RP = base(_, [bool|_]), cpp_pointerish(AT), !.
cpp_scalar_mismatch(RP, AT) :- ( RP = ptr(_, _) ; RP = arr(_, _) ), ccl_resolve_type(AT, RA), ccl_is_arith(RA), !.
cpp_class_fits(C, C) :- !.
cpp_class_fits(D, C) :- cpp_class(D, cls(B, _, _, _, _, _)), B \== none, cpp_class_fits(B, C).
cpp_converting(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(ctor(_, _, [_], _, _), Ms), !.
cpp_has_conversion(D) :- cpp_class(D, cls(_, _, Ms, _, _, _)), member(method(_, _, _, operator(conv(_)), _, _, _), Ms), !.
%% A FUNCTION TEMPLATE'S INSTANCE IS NOTED WHEN IT IS EMITTED, NOT BEFORE -- 0.69's rule, which the member template
%% and the lazy member got and this road kept the old way: the note was taken first, an emission abandoned by a
%% candidate's check (SFINAE throws and catches by design) left it behind, and the next ask found the instance
%% "done" with no body anywhere -- `__to_chars_integral' declared and never defined, the last symbol between
%% `std::cout << "hello"' and a binary. In progress while it emits (its own recursive call finds it declared).
cpp_instantiate_function_(F, _, B, L, Sto, Ret, Ps, V, Body, Name) :-
    (   cpp_instance_done(Name) -> true
    ;   cpp_making(Name) -> true
    ;   nb_getval('$cpp_making', M0), nb_setval('$cpp_making', [Name|M0]),
        (   catch(cpp_instantiate_function_emit(F, B, L, Sto, Ret, Ps, V, Body, Name), E, ( nb_setval('$cpp_making', M0), throw(E) ))
        ->  nb_setval('$cpp_making', M0), cpp_instance_note(Name, F)
        ;   nb_setval('$cpp_making', M0), cpp_refuse(0, function_not_emitted(Name)) ) ).
cpp_instantiate_function_emit(F, B, L, Sto, Ret, Ps, V, Body, Name) :-
    cpp_lib_origin(F, Lib),
    cpp_where(subst(F), cpp_subst(fn(Ret, Ps, Body), B, fn(Ret1, Ps1, Body1))),
    cpp_as_lib(Lib, ( cpp_isolated(( cpp_plain_params(Ps1, Ps2), ( Ret1 = base(_, [auto]) -> cpp_lambda_ret(Ps2, Body1, Ret2) ; cpp_type(Ret1, Ret2) ),
                                     ccl_declare(Name, fn(Ret2, Ps2, V)), cpp_note_defaults(Name, Ps1),
                                     ( Body1 == none -> Items = [declaration(L, Sto, Ret2, [var(Name, fn(Ret2, Ps2, V), none)])]   % declared, not defined: a declaration, never a bodyless function
                                     ; cpp_item(function(L, Sto, Ret2, Name, Ps1, V, Body1), Items) ) )),
                      cpp_add_instance_items(Items) )).
cpp_bind_targs(TPs, Args, B) :- cpp_bind_targs_(TPs, Args, [], B).
cpp_bind_targs_([], _, B, B).
cpp_bind_targs_([requires(_)|TPs], Args, Acc, B) :- !, cpp_bind_targs_(TPs, Args, Acc, B).
cpp_bind_targs_([tparam(K, P, _)|_], Args, Acc, [P-pack(Args)|Acc]) :- cpp_pack_kind(K), !.     % a pack takes what is left
cpp_bind_targs_([tparam(template, P, D)|TPs], Args, Acc, B) :- !,                                % a template template parameter: bound to a template's NAME
    ( Args = [A0|Rest] -> cpp_tname_arg(A0, Acc, A) ; D \== none -> cpp_tname_arg(D, Acc, A), Rest = [] ; cpp_refuse(0, template_argument_missing(P)) ),
    cpp_bind_targs_(TPs, Rest, [P-A|Acc], B).
%% AN EXPLICIT TEMPLATE ARGUMENT IS EVALUATED WHERE IT IS BOUND, whatever road brought it: the class path ran it
%% through cpp_targ_value first and the MEMBER TEMPLATE path handed it over raw, so `__align_it<__boundary>(n)' --
%% libc++'s alignment step, over a `const' local -- keyed its instance by the NAME and left it in the body.
cpp_bind_targs_([tparam(_, P, D)|TPs], Args, Acc, B) :-
    ( Args = [A0|Rest] -> ( cpp_targ_value(A0, A) -> true ; A = A0 ) ; D \== none -> cpp_subst(D, Acc, D1), cpp_type_or_value(D1, A), Rest = [] ; cpp_refuse(0, template_argument_missing(P)) ),
    cpp_bind_targs_(TPs, Rest, [P-A|Acc], B).
cpp_pack_kind(pack).
cpp_pack_kind(vpack(_)).
%% a template template parameter's argument is a template's name -- an atom (the reader gives a bare name as a
%% type, `Cell<int, Twice>'), a namespace's flattened away, or another such parameter's binding passed on
%% (`__split_buffer<_Tp, _Allocator, _Layout>') -- kept as tname(N): a type it is not, and no instance is made of it
cpp_tname_arg(tname(N), _, tname(N)) :- !.
cpp_tname_arg(base(_, [typedef(X)]), B, A) :- !, cpp_tname_arg(X, B, A).
cpp_tname_arg(scoped(_, X), B, A) :- !, cpp_tname_arg(X, B, A).
cpp_tname_arg(X, B, tname(N)) :- atom(X), !, ( memberchk(X-tname(N0), B) -> N = N0 ; N = X ).
cpp_tname_arg(X, _, _) :- cpp_refuse(0, not_a_template_name(X)).
%% C++20: the head's requires-clause, under the bindings, must hold
cpp_constraints_hold(N, TPs, B) :- ( memberchk(requires(R), TPs) -> cpp_subst(R, B, R1), ( cpp_satisfied(R1) -> true ; cpp_refuse(0, constraint_not_satisfied(N)) ) ; true ).
cpp_bind_explicit([], _, []) :- !.
cpp_bind_explicit(_, [], []) :- !.
cpp_bind_explicit([requires(_)|TPs], As, B) :- !, cpp_bind_explicit(TPs, As, B).
cpp_bind_explicit([tparam(K, P, _)|_], As, [P-pack(As)]) :- cpp_pack_kind(K), !.
cpp_bind_explicit([tparam(template, P, _)|TPs], [A0|As], [P-A|B]) :- !, cpp_tname_arg(A0, [], A), cpp_bind_explicit(TPs, As, B).
cpp_bind_explicit([tparam(_, P, _)|TPs], [A0|As], [P-A|B]) :- ( cpp_targ_value(A0, A) -> true ; A = A0 ), cpp_bind_explicit(TPs, As, B).   % EVALUATED where it binds, as the class path's arguments are
%% what deduction left unbound: a pack is empty, a default stands (under the bindings so far), and a value
%% parameter's TYPE must resolve -- `enable_if<c, int>::type = 0' has no type when c is false (SFINAE)
cpp_bind_defaults([], B, B).
cpp_bind_defaults([requires(_)|TPs], B0, B) :- !, cpp_bind_defaults(TPs, B0, B).
cpp_bind_defaults([tparam(template, P, D)|TPs], B0, B) :- !,
    ( memberchk(P-_, B0) -> B1 = B0 ; D \== none -> cpp_tname_arg(D, B0, A), B1 = [P-A|B0] ; cpp_refuse(0, cannot_deduce(P)) ),
    cpp_bind_defaults(TPs, B1, B).
cpp_bind_defaults([tparam(K, P, D)|TPs], B0, B) :-
    (   atom(P), memberchk(P-_, B0) -> B1 = B0                                            % ... and it binds nothing either, for the same reason
    ;   cpp_pack_kind(K) -> ( atom(P) -> B1 = [P-pack([])|B0] ; B1 = B0 )
    ;   D \== none -> cpp_subst(D, B0, D1), cpp_type_or_value(D1, A), ( atom(P) -> B1 = [P-A|B0] ; B1 = B0 )   % the default is still RESOLVED: that resolution is the SFINAE
    ;   atom(P) -> cpp_refuse(0, cannot_deduce(P))
    ;   B1 = B0 ),
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
cpp_match(base(_, [typedef(scoped(Path, _))]), _, TPs, B, B) :- cpp_path_dependent(Path, TPs), !.   % A NAME QUALIFIED BY A PARAMETER IS A NON-DEDUCED CONTEXT, whatever it names: `typename _IterOps<_AlgPolicy>::template __difference_type<_InIter> __n' binds nothing here and resolves once the others bind it (C++'s nested-name-specifier rule; 0.46 had it for a pattern); its last segment taken for a class template refused deduction_failed
cpp_match(base(_, [typedef(X)]), _, TPs, B, B) :- cpp_template_id(X, N, _), \+ memberchk(tparam(template, N, _), TPs), cpp_alias_template(N), !.   % __type_identity_t<T> *: a non-deduced context; the alias is substituted once T is bound (explicitly) and the parameter checked then
cpp_match(base(_, [typedef(X)]), AT, TPs, B0, B) :- cpp_template_id(X, N, Sub), !,                  % f(H<T>), f(vector<T>): the argument an instance of N, or of what H is bound to
    ( memberchk(tparam(template, N, _), TPs) -> Want = any ; Want = N ),
    (   cpp_instance_or_base(AT, Want, N1, SubArgs)
    ->  ( Want == any -> ( memberchk(N-tname(N0), B0) -> N0 == N1, B1 = B0 ; B1 = [N-tname(N1)|B0] ) ; B1 = B0 ),
        cpp_match_targs(Sub, SubArgs, TPs, B1, B)
    ;   cpp_refuse(0, deduction_failed(N)) ).                                                         % not an instance: no candidate
cpp_alias_template(N) :- atom(N), catch(cpp_class_template(N, _, typedef(_, _)), _, fail), \+ ( cpp_class_template(N, _, I), cpp_template_class_def(I) ), !.   % an alias only: std::pmr::vector shares std::vector's flattened name, and the class wins
%% the argument's type as an instance of the template wanted (any, for a template template parameter): itself, or a base
%% of its class -- a derived object binds a base's reference
cpp_instance_or_base(AT, Want, N, Args) :-
    ( cpp_instance_of(AT, N0, Args0) ; ccl_resolve_type(AT, AT1), AT1 \== AT, cpp_instance_of(AT1, N0, Args0) ), cpp_wanted(Want, N0), !, N = N0, Args = Args0.
cpp_instance_or_base(AT, Want, N, Args) :- cpp_class_of_type(AT, C), cpp_class_base_instance(C, Want, N, Args), cpp_converted.
cpp_class_base_instance(C, Want, N, Args) :- cpp_class(C, cls(B, _, _, _, _, _)), B \== none,
    ( '$cpp_inst'(B, inst(N0, Args0)), cpp_wanted(Want, N0) -> N = N0, Args = Args0 ; cpp_class_base_instance(B, Want, N, Args) ).
cpp_wanted(any, _) :- !.
cpp_wanted(N, N).
cpp_match(ptr(_, X), AT, TPs, B0, B) :- ccl_resolve_type(AT, AT1), ( AT1 = ptr(_, Y) ; AT1 = arr(_, Y) ), !, cpp_match(X, Y, TPs, B0, B).
cpp_match(ref(_, X), AT, TPs, B0, B) :- !, cpp_match(X, AT, TPs, B0, B).
cpp_match(rref(_, X), AT, TPs, B0, B) :- !, cpp_match(X, AT, TPs, B0, B).
cpp_match(_, _, _, B, B).
cpp_match_targs([], _, _, B, B) :- !.
cpp_match_targs(_, [], _, B, B) :- !.
cpp_match_targs([P|Ps], [A|As], TPs, B0, B) :-
    (   cpp_is_type(P) -> cpp_match(P, A, TPs, B0, B1)
    ;   P = id(V), memberchk(tparam(K, V, _), TPs), \+ memberchk(K, [type, pack, template]), \+ memberchk(V-_, B0) -> B1 = [V-A|B0]
    ;   B1 = B0 ),
    cpp_match_targs(Ps, As, TPs, B1, B).
cpp_decayed(T, T1) :- ( ccl_resolve_type(T, arr(_, E)) -> T1 = ptr([], E) ; T = base(_, S) -> T1 = base([], S) ; T1 = T ).
%% the instance's name: the template's, then a key per argument
cpp_instance_name(N0, TPs, B, Name) :- cpp_instance_base(N0, N),
    findall(K, ( member(tparam(_, P, _), TPs), atom(P), memberchk(P-A, B), cpp_type_key(A, K) ), Ks), atomic_list_concat([N|Ks], '.', Name).
%% AN UNNAMED TEMPLATE PARAMETER HAS NO NAME TO LOOK UP -- libc++ writes its SFINAE guard as one
%% (`template <class _Up, class... _Args, __enable_if_t<...> = 0>') -- and `memberchk(P-A, B)' with P unbound takes
%% whatever is FIRST in the bindings, so the instance was named one way where it was emitted and another where it
%% was called, and the call named nothing. It contributes no key, in both places alike.
cpp_instance_base(operator(Op), N) :- !, cpp_op_word(Op, W), atom_concat('op.', W, N).   % an OPERATOR member template: `__less<>::operator()' is a template of its own
cpp_instance_base(N, N).
cpp_type_key(pack([]), e) :- !.
cpp_type_key(pack(L), K) :- !, findall(K1, ( member(A, L), cpp_type_key(A, K1) ), Ks), atomic_list_concat(Ks, '_', K).
cpp_type_key(vpack(L), K) :- !, cpp_type_key(pack(L), K).
cpp_type_key(base(_, S), K) :- !, findall(W, ( member(X, S), cpp_spec_key(X, W) ), Ws), atomic_list_concat(Ws, '_', K).
cpp_type_key(ptr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_p', K).
cpp_type_key(ref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_r', K).
cpp_type_key(rref(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_rr', K).
cpp_type_key(arr(_, T), K) :- !, cpp_type_key(T, K0), atom_concat(K0, '_a', K).
cpp_type_key(tname(X), X) :- !.
cpp_type_key(int(N), N) :- !.
cpp_type_key(uint(N), K) :- !, atom_concat(N, u, K).
cpp_type_key(long(N), K) :- !, atom_concat(N, l, K).
cpp_type_key(ulong(N), K) :- !, atom_concat(N, ul, K).
cpp_type_key(neg(int(N)), K) :- !, atom_concat(m, N, K).
cpp_type_key(chr(C), K) :- !, atom_concat(c, C, K).
cpp_type_key(bool(true), '1') :- !.      % a bool argument keys as its NUMBER, so `true' and `1' name one instance and not two
cpp_type_key(bool(false), '0') :- !.
cpp_type_key(id(X), X) :- !.
cpp_type_key(X, K) :- term_to_atom(X, A), atom_codes(A, Cs), findall(C, ( member(C, Cs), ( C >= 0'a, C =< 0'z ; C >= 0'A, C =< 0'Z ; C >= 0'0, C =< 0'9 ) ), Ds), atom_codes(K, Ds).
cpp_spec_key(typedef(X), X) :- atom(X), !.
cpp_spec_key(struct(T, _), T) :- !.
cpp_spec_key(union(T, _), T) :- !.              % a nested union names its instance by its tag, as a struct does
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
cpp_subst(template(L, TPs, M), B, template(L, TPs1, M1)) :- !, cpp_shadow(TPs, B, B1), cpp_subst_tparams(TPs, B1, TPs1), cpp_subst(M, B1, M1).   % a member template's own parameters shadow; its defaults and value types take the class's bindings (`class _Ap = _Alloc')
cpp_subst_tparams([], _, []).
cpp_subst_tparams([tparam(K, P, D)|TPs], B, [tparam(K1, P, D1)|Qs]) :- !, ( cpp_is_type(K) -> cpp_subst(K, B, K1) ; K1 = K ), ( D == none -> D1 = none ; cpp_subst(D, B, D1) ), cpp_subst_tparams(TPs, B, Qs).
cpp_subst_tparams([requires(R)|TPs], B, [requires(R1)|Qs]) :- !, cpp_subst(R, B, R1), cpp_subst_tparams(TPs, B, Qs).
cpp_subst_tparams([X|TPs], B, [X|Qs]) :- cpp_subst_tparams(TPs, B, Qs).
cpp_subst(base(Q, [typedef(P)]), B, base(Q, [typedef(X)])) :- atom(P), memberchk(P-tname(X), B), !.      % a template template parameter passed on by name
cpp_subst(tmpl(P, Args0), B, tmpl(X, Args)) :- atom(P), memberchk(P-tname(X), B), !, cpp_subst(Args0, B, Args).   % L<A, B>: the template it is bound to
cpp_subst(base(Q, [typedef(P)]), B, T) :- memberchk(P-A, B), !, ( cpp_pack_list(A, _) -> cpp_refuse(0, pack_unexpanded(P)) ; cpp_merge_quals(Q, A, T) ).
cpp_subst(sizeof(id(P)), B, sizeof_type(A)) :- memberchk(P-A, B), cpp_is_type(A), !.          % sizeof(T), read as an expression while T was a name
cpp_subst(call(id(P), [X0]), B, ccast(functional, A, X)) :- memberchk(P-A, B), cpp_is_type(A), !, cpp_subst(X0, B, X).   % T(x)
cpp_subst(call(id(P), []), B, call(id(N), [])) :- memberchk(P-base(_, [typedef(N)]), B), atom(N), !.   % T(): the bound type's name called, the temporary road a class's name already takes -- how a constructor template writes its allocator's default argument, `const _Allocator & __a = _Allocator()'
cpp_subst(id(P), B, V) :- memberchk(P-V0, B), !, ( cpp_pack_list(V0, _) -> cpp_refuse(0, pack_unexpanded(P)) ; V = V0 ).
cpp_subst(scoped(Path, N0), B, scoped(Path1, N)) :- !, cpp_subst_path(Path, B, Path1), ( atom(N0) -> N = N0 ; cpp_subst(N0, B, N) ).   % C::value_type with C a parameter: the class it is bound to; std::vector<T> under T
cpp_subst_path([], _, []).
cpp_subst_path([P|Ps], B, [P1|Qs]) :-
    (   atom(P), memberchk(P-A, B), A = base(_, [typedef(X)]) -> P1 = X
    ;   atom(P), memberchk(P-tname(X), B) -> P1 = X
    ;   atom(P), memberchk(P-A, B), cpp_scalar_type(A) -> P1 = nonclass(A)   % `typename _Tp::pointer' with _Tp a POINTER, a scalar, a reference, a function: NO MEMBER TYPES AT ALL. The segment carries the type and RESOLVING the name refuses (cpp_type, cpp_expr) -- the SFINAE libc++'s detection idiom needs (`__pointer_member' on a deleter that is a function pointer); the parameter's name stayed in the path before, and flattened as a namespace into a free name
    ;   cpp_subst(P, B, P1) ),
    cpp_subst_path(Ps, B, Qs).
cpp_scalar_type(ptr(_, _)).  cpp_scalar_type(ref(_, _)).  cpp_scalar_type(rref(_, _)).  cpp_scalar_type(arr(_, _)).  cpp_scalar_type(fn(_, _, _)).
cpp_scalar_type(base(_, [K|_])) :- atom(K), ccl_basic_type(K).
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
cpp_subst_elems([type(pack(T))|Xs], B, Ys) :- cpp_pack_names(T, B, [_|_]), !, cpp_expand_pack(T, B, Ts), findall(type(T1), member(T1, Ts), Ss), cpp_subst_elems(Xs, B, Ys1), append(Ss, Ys1, Ys).   % a builtin trait's argument: `__is_constructible(_Tp, _Args...)', which is how libc++ writes is_constructible
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
cpp_member_template_call(C, M, Explicit, As, Name) :- cpp_where(member(C, M), cpp_member_template_call_(C, M, Explicit, As, Name)).
cpp_member_template_call_(C, M, Explicit, As, Name) :-
    findall(TPs-Mem, '$cpp_mt'(C, M, TPs, Mem), Cands0), Cands0 \== [],
    findall(X, ( member(X, Cands0), \+ cpp_variadic_member(X) ), Plain),      % an ELLIPSIS is C++'s worst match: `test(...)' only where nothing else fits
    findall(X, ( member(X, Cands0), cpp_variadic_member(X) ), Var), append(Plain, Var, Cands),
    cpp_try_member(Cands, C, Explicit, As, Name).
%% A NAME NOTED DONE BEFORE ITS EMISSION SURVIVES THAT EMISSION'S ABANDONMENT. A member template's instance is
%% made wherever its call is met, and that can be INSIDE another candidate's signature check, whose catch swallows
%% the refusal and rejects the candidate (SFINAE, by design) -- and the note was left behind, so every later ask
%% answered with a definition that had never been emitted: `std::vector<std::string>' called
%% `allocator<string>::construct' and the linker's own complaint arrived as `undeclared'. The name is IN PROGRESS
%% while the emission runs, which is all a recursive ask needs, and NOTED only once it is done; a throw clears it,
%% as cpp_isolated and cpp_in_class already restore what they set aside.
cpp_making(Name) :- nb_getval('$cpp_making', L), memberchk(Name, L).
cpp_make_member(Name, C, L, Qs, Ret1, MName, Ps1, V, Body1) :-
    nb_getval('$cpp_making', M0), nb_setval('$cpp_making', [Name|M0]),
    M = method(L, Qs, Ret1, MName, Ps1, V, Body1),
    (   catch(( cpp_class(C, cls(Base, _, _, _, Defaults, _)), ( cpp_lib_class(C) -> Lib = yes ; Lib = no ),
                cpp_as_lib(Lib, ( cpp_isolated(cpp_in_class(C, ( cpp_declare_members([M], C), cpp_member_fns([M], C, Base, Defaults, Fns) ))),
                                  cpp_add_instance_items(Fns) )) ),
              E, ( nb_setval('$cpp_making', M0), throw(E) ))
    ->  nb_setval('$cpp_making', M0), cpp_instance_note(Name, C)
    ;   nb_setval('$cpp_making', M0), cpp_refuse(L, member_instance_not_emitted(Name)) ).
cpp_variadic_member(_-method(_, _, _, _, _, true, _)).
cpp_try_member([], _, _, _, _) :- fail.
cpp_try_member([TPs-method(L, Qs, Ret, M, Ps, V, Body)|Cs], C, Explicit, As, Name) :-
    (   catch(cpp_in_class(C, cpp_signature_holds(M, TPs, Ps, V, Explicit, As, B)), error(not_lowered(W), _), ( cpp_trace(member_refused(C, M, W)), fail ))   % IN ITS OWN CLASS: a parameter written `const allocator_type &' is in the traits class's words, not the caller's
    ->  cpp_instance_name(M, TPs, B, MName), cpp_subst(method(L, Qs, Ret, M, Ps, V, Body), B, method(_, _, Ret1, _, Ps1, _, Body1)),
        cpp_mangle(C, MName, Ps1, Name),
        (   cpp_instance_done(Name) -> true
        ;   cpp_making(Name) -> true                                    % in progress: the NAME is all a recursive ask needs
        ;   cpp_make_member(Name, C, L, Qs, Ret1, MName, Ps1, V, Body1) )
    ;   cpp_try_member(Cs, C, Explicit, As, Name) ).
cpp_member_template_ctor(C, As, Name) :-
    findall(TPs-Mem, '$cpp_mt'(C, ctor, TPs, Mem), Cands), Cands \== [],
    cpp_try_ctor(Cands, C, As, Name).
cpp_try_ctor([TPs-ctor(L, Qs, Ps, Inits, Body)|Cs], C, As, Name) :-
    (   catch(cpp_signature_holds(C, TPs, Ps, [], As, B), error(not_lowered(_), _), fail)
    ->  cpp_subst(ctor(L, Qs, Ps, Inits, Body), B, ctor(_, _, Ps1, Inits1, Body1)), cpp_mangle(C, C, Ps1, Name),
        (   cpp_instance_done(Name) -> true
        ;   cpp_instance_note(Name, C), cpp_class(C, cls(Base, _, _, _, Defaults, _)), ( cpp_lib_class(C) -> Lib = yes ; Lib = no ),
            cpp_as_lib(Lib, ( cpp_isolated(cpp_in_class(C, ( cpp_declare_members([ctor(L, Qs, Ps1, Inits1, Body1)], C), cpp_member_fns([ctor(L, Qs, Ps1, Inits1, Body1)], C, Base, Defaults, Fns) ))),
                              cpp_add_instance_items(Fns) )) )
    ;   cpp_try_ctor(Cs, C, As, Name) ).
%% ---- the compiler's traits, decided here ----------------------------------------------------
cpp_trait('__is_same', [A, B], bool(V)) :- !, cpp_trait_type(A, TA), cpp_trait_type(B, TB), ( cpp_same_type(TA, TB) -> V = true ; V = false ).
%% offsetof: the byte offset the layout already computes (libc++ finds a type's data size with it -- the offset of a
%% char member placed after it)
cpp_trait('__builtin_offsetof', [A, M], int(Off)) :- !, cpp_trait_type(A, T), cpp_offset_path(M, Path), cpp_offsetof(T, Path, 0, Off).
cpp_offset_path(id(N), [N]) :- !.
cpp_offset_path(member(X, N), Path) :- !, cpp_offset_path(X, P0), append(P0, [N], Path).
cpp_offset_path(arrow(X, N), Path) :- !, cpp_offset_path(X, P0), append(P0, [N], Path).
cpp_offset_path(index(X, _), Path) :- !, cpp_offset_path(X, Path).
cpp_offset_path(X, _) :- cpp_refuse(0, offsetof_path(X)).
cpp_offsetof(_, [], Off, Off) :- !.
cpp_offsetof(T, [N|Ns], Acc, Off) :-
    ccl_members_of(T, Ms), ccl_members_layout(Ms, Lays, _, _), memberchk(lay(N, MT, MOff, _), Lays), !,
    Acc1 is Acc + MOff, cpp_offsetof(MT, Ns, Acc1, Off).
cpp_offsetof(T, [N|_], _, _) :- cpp_refuse(0, no_member(N, T)).
cpp_trait(N, [A], bool(V)) :- cpp_trait_type(A, T), ccl_resolve_type(T, R), cpp_trait_of(N, R, V), !.
cpp_trait(N, [A|As], bool(V)) :- cpp_trait_types([A|As], [T|Ts]), cpp_trait_n(N, T, Ts, V), !.
cpp_trait(N, _, _) :- cpp_refuse(0, trait_unknown(N)).
cpp_trait_types([], []).
cpp_trait_types([A|As], [T|Ts]) :- cpp_trait_type(A, T), cpp_trait_types(As, Ts).
%% the traits over two or more types, decided over the registry: a scalar constructs from and converts to what
%% C++ converts, a class through its constructors, its conversion operators, its bases; nothing throws here, so
%% the nothrow forms are the plain ones, and the trivial ones ask for no user-written special member
cpp_trait_n(N, T, Args, V) :- memberchk(N, ['__is_constructible', '__is_nothrow_constructible']), !, ( cpp_constructible(T, Args) -> V = true ; V = false ).
cpp_trait_n('__is_trivially_constructible', T, Args, V) :- !, ( cpp_constructible(T, Args), cpp_trivial_type(T) -> V = true ; V = false ).
cpp_trait_n(N, T, [F], V) :- memberchk(N, ['__is_assignable', '__is_nothrow_assignable']), !, ( cpp_assignable(T, F) -> V = true ; V = false ).
cpp_trait_n('__is_trivially_assignable', T, [F], V) :- !, ( cpp_assignable(T, F), cpp_trivial_type(T) -> V = true ; V = false ).
cpp_trait_n(N, F, [T], V) :- memberchk(N, ['__is_convertible', '__is_convertible_to', '__is_nothrow_convertible']), !, ( cpp_convertible(F, T) -> V = true ; V = false ).
cpp_trait_n('__is_base_of', B, [D], V) :- !, ( cpp_class_of_type(B, CB), cpp_class_of_type(D, CD), cpp_class_fits(CD, CB) -> V = true ; V = false ).
cpp_trait_n('__is_same_as', A, [B], V) :- !, ( cpp_same_type(A, B) -> V = true ; V = false ).
cpp_constructible(T, []) :- !, ccl_unref(T, T1),
    ( cpp_class_of_type(T1, C) -> ( \+ cpp_has_ctors(C) -> true ; cpp_ctor_arity_fits(C, 0) -> true ; cpp_trivial_default(C) )   % `allocator() = default' is dropped as the implicit one: still default-constructible
    ; \+ ccl_resolve_type(T1, base(_, [void])) ).
cpp_constructible(T, [F]) :- !, ccl_unref(T, T1), ccl_unref(F, F1),                                 % the ARGUMENT unreffed too: `__is_constructible(T, T &&)' is T's copy or move
    ( cpp_class_of_type(T1, C) -> ( cpp_class_of_type(F1, C) -> true ; cpp_has_ctors(C) -> cpp_ctor_arity_fits(C, 1) ; cpp_convertible(F1, T1) )
    ; cpp_convertible(F1, T1) ).
cpp_constructible(T, Args) :- length(Args, N), cpp_class_of_type(T, C), cpp_ctor_arity_fits(C, N).
cpp_ctor_arity_fits(C, N) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(ctor(_, _, Ps, _, _), Ms), cpp_arity(Ps, Min, Max), N >= Min, ( Max == any ; N =< Max ), !.
cpp_ctor_arity_fits(C, N) :- '$cpp_mt'(C, ctor, _, ctor(_, _, Ps, _, _)), cpp_arity(Ps, Min, Max), N >= Min, ( Max == any ; N =< Max ), !.   % a constructor TEMPLATE counts (libc++'s allocator has only that and a defaulted one)
cpp_assignable(T, F) :- ccl_unref(T, T1), ccl_unref(F, F1),
    ( cpp_class_of_type(T1, C) -> ( cpp_class_of_type(F1, C) -> true ; cpp_class(C, cls(_, _, Ms, _, _, _)), member(method(_, _, _, operator('='), [_], _, _), Ms) ) ; cpp_convertible(F1, T1) ).
cpp_convertible(F, T) :- ccl_unref(F, F1), ccl_unref(T, T1), ccl_resolve_type(F1, RF), ccl_resolve_type(T1, RT),
    (   cpp_same_type(F1, T1) -> true
    ;   ccl_is_arith(RF), ccl_is_arith(RT) -> true
    ;   ( RF = ptr(_, PF) ; RF = arr(_, PF) ), RT = ptr(_, PT), ( ccl_resolve_type(PT, base(_, [void])) -> true ; cpp_same_type(PF, PT) ) -> true
    ;   RF = ptr(_, base(_, [void])), RT = ptr(_, _) -> true                                          % nullptr's type here
    ;   cpp_class_of_type(RF, CF), cpp_class_of_type(RT, CT) -> cpp_class_fits(CF, CT)
    ;   cpp_class_of_type(RT, CT) -> cpp_converting(CT)
    ;   cpp_class_of_type(RF, CF) -> cpp_has_conversion(CF)
    ;   fail ).
cpp_trivial_type(T) :- ccl_unref(T, T1), ( cpp_class_of_type(T1, C) -> cpp_trivial_class(C) ; true ).
cpp_trivial_class(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), \+ member(ctor(_, _, _, _, _), Ms), \+ member(dtor(_, _, _), Ms), \+ member(method(_, _, _, operator('='), _, _, _), Ms), \+ cpp_implicit_dtor_needed(C).
cpp_has_dtor(C) :- cpp_class(C, cls(_, _, Ms, _, _, _)), ( memberchk(dtor(_, _, _), Ms) -> true ; cpp_implicit_dtor_needed(C) ).
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
cpp_trait_of('__is_union', R, V) :- ( R = base(_, [union(_, _)]) -> V = true ; V = false ).
cpp_trait_of('__is_function', R, V) :- ( R = fn(_, _, _) -> V = true ; V = false ).
cpp_trait_of('__is_scalar', R, V) :- ( ( ccl_is_arith(R) ; R = ptr(_, _) ; R = base(_, [enum(_, _)]) ; R = base(_, [enum_class(_, _)]) ) -> V = true ; V = false ).
cpp_trait_of('__is_fundamental', R, V) :- ( ( ccl_is_arith(R) ; R = base(_, [void]) ) -> V = true ; V = false ).
cpp_trait_of('__is_compound', R, V) :- ( ( ccl_is_arith(R) ; R = base(_, [void]) ) -> V = false ; V = true ).
cpp_trait_of('__is_object', R, V) :- ( ( R = fn(_, _, _) ; R = ref(_, _) ; R = rref(_, _) ; R = base(_, [void]) ) -> V = false ; V = true ).
cpp_trait_of('__is_referenceable', R, V) :- ( R = base(_, [void]) -> V = false ; V = true ).
cpp_trait_of('__is_bounded_array', R, V) :- ( R = arr(N, _), N \== none -> V = true ; V = false ).
cpp_trait_of('__is_unbounded_array', R, V) :- ( R = arr(none, _) -> V = true ; V = false ).
cpp_trait_of(N, _, false) :- memberchk(N, ['__is_member_pointer', '__is_member_function_pointer', '__is_member_object_pointer', '__is_final', '__is_null_pointer']).   % no member pointers here; nullptr is a void pointer
cpp_trait_of(N, R, V) :- memberchk(N, ['__is_trivially_copyable', '__is_trivial', '__is_pod', '__is_standard_layout', '__is_literal_type', '__is_trivially_copy_constructible', '__is_trivially_move_constructible']), ( cpp_trivial_type(R) -> V = true ; V = false ).
cpp_trait_of(N, R, V) :- memberchk(N, ['__is_trivially_destructible', '__has_trivial_destructor']), ( ( cpp_class_of_type(R, C) -> \+ cpp_has_dtor(C) ; true ) -> V = true ; V = false ).
cpp_trait_of(N, _, true) :- memberchk(N, ['__is_destructible', '__is_nothrow_destructible']).
cpp_trait_of('__has_virtual_destructor', R, V) :- ( cpp_class_of_type(R, C), cpp_class(C, cls(_, _, _, _, _, Slots)), memberchk(slot('$dtor', _, _, _, _), Slots) -> V = true ; V = false ).
cpp_trait_of('__is_polymorphic', R, V) :- ( cpp_class_of_type(R, C), cpp_polymorphic(C) -> V = true ; V = false ).
cpp_trait_of('__is_empty', R, V) :- ( cpp_class_of_type(R, C), cpp_class(C, cls(B, Data, _, _, _, _)), Data == [], ( B == none ; cpp_trait_of('__is_empty', base([], [typedef(B)]), true) ) -> V = true ; V = false ).
cpp_trait_of('__is_aggregate', R, V) :- ( ( R = arr(_, _) ; cpp_class_of_type(R, C), \+ cpp_has_ctors(C), \+ cpp_polymorphic(C) ) -> V = true ; V = false ).
%% the traits that name a type
%% THE TOP-LEVEL QUALIFIERS OF A TYPE are a specifier list's or a POINTER's (`char * const'); a reference, an array
%% and a function carry none. The three strippers took only a specifier list and FAILED on a pointer -- and libc++'s
%% is_void is `_BoolConstant<__is_same(__remove_cv(_Tp), void)>', which every pointer_traits asks.
cpp_builtin_type('__remove_cv', [A], T1) :- !, cpp_trait_type(A, T), ccl_resolve_type(T, R), cpp_strip_quals(R, _, T1).
cpp_builtin_type('__remove_const', [A], T1) :- !, cpp_trait_type(A, T), ccl_resolve_type(T, R), cpp_strip_quals(R, Q, T0), ccl_delete_one(Q, const, Q1), cpp_with_quals(Q1, T0, T1).
cpp_builtin_type('__remove_reference_t', [A], T1) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__remove_cvref', [A], T1) :- !, cpp_trait_type(A, T), ccl_unref(T, T0), ccl_resolve_type(T0, R), cpp_strip_quals(R, _, T1).
cpp_strip_quals(base(Q, S), Q, base([], S)) :- !.
cpp_strip_quals(ptr(Q, T), Q, ptr([], T)) :- !.
cpp_strip_quals(T, [], T).
cpp_with_quals(Q, base(_, S), base(Q, S)) :- !.
cpp_with_quals(Q, ptr(_, T), ptr(Q, T)) :- !.
cpp_with_quals(_, T, T).
cpp_builtin_type('__decay', [A], T1) :- !, cpp_trait_type(A, T), ccl_unref(T, T0), cpp_decayed(T0, T1).
cpp_builtin_type('__add_lvalue_reference', [A], ref([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__add_rvalue_reference', [A], rref([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__add_pointer', [A], ptr([], T1)) :- !, cpp_trait_type(A, T), ccl_unref(T, T1).
cpp_builtin_type('__remove_pointer', [A], T1) :- !, cpp_trait_type(A, T), ( ccl_resolve_type(T, ptr(_, T1)) -> true ; T1 = T ).
%% the signed and unsigned counterparts, which libc++ takes a type's DIGITS from
%% (`__builtin_popcountg(~__make_unsigned_t<type>(0))'): the qualifiers kept, an enum through its underlying type
cpp_builtin_type('__make_unsigned', [A], T1) :- !, cpp_trait_type(A, T), cpp_signedness(unsigned, T, T1).
cpp_builtin_type('__make_signed', [A], T1) :- !, cpp_trait_type(A, T), cpp_signedness(signed, T, T1).
cpp_builtin_type(N, _, _) :- cpp_refuse(0, trait_unknown(N)).
cpp_signedness(W, T0, base(Q, S1)) :- ccl_resolve_type(T0, base(Q, S0)), cpp_int_spec(S0, S), !, cpp_sign_spec(W, S, S1).
cpp_signedness(_, T, T).
%% the integer a specifier list names, its own signedness dropped: [unsigned, long] and [long] are both long
cpp_int_spec(S0, S) :- findall(X, ( member(X, S0), X \== signed, X \== unsigned ), S), S \== [], cpp_integer_spec(S).
cpp_integer_spec(S) :- ( memberchk(char, S) ; memberchk(short, S) ; memberchk(int, S) ; memberchk(long, S) ; memberchk('_Bool', S) ).
cpp_sign_spec(unsigned, S, [unsigned|S]).
cpp_sign_spec(signed, S, [signed|S]).
cpp_is_type(T) :- ( T = base(_, _) ; T = ptr(_, _) ; T = ref(_, _) ; T = rref(_, _) ; T = arr(_, _) ; T = fn(_, _, _) ), !.
cpp_merge_quals(Q, base(Q2, S), base(Q3, S)) :- !, append(Q, Q2, Q3).
cpp_merge_quals(_, A, A).

%% ---- lambdas: a class of the captures, operator() the body ----------------------------------
cpp_lambda(Ctx, Caps, Ps0, Ret0, Body, compound_lit(T, init(Items))) :-
    ( Ps0 = [param(this(ST0), SN)|Ps1] -> true ; Ps1 = Ps0, SN = none ),                                         % C++23: an explicit object parameter: the closure itself, `this auto self'
    ( ( memberchk(tparams(_), Caps) ; member(P, Ps1), ( P = param(PT, _) ; P = param(PT, _, _) ), cpp_auto_in(PT, 0, _, _) ) -> cpp_refuse(0, generic_lambda) ; true ),   % C++20: a template lambda, a member template of the closure
    cpp_plain_params(Ps1, Ps),
    nb_getval('$cpp_lambdas', K0), K is K0 + 1, nb_setval('$cpp_lambdas', K), atomic_list_concat(['lambda.', K], Name),
    T = base([], [typedef(Name)]),
    ( SN == none -> Self = [], SelfPs = Ps ; cpp_self_type(ST0, Name, ST), Self = [param(this(ST), SN)], SelfPs = [param(ST, SN)|Ps] ),
    cpp_captures(Caps, SelfPs, Body, Captures),
    ( Ret0 == none -> cpp_lambda_ret(Ctx, SelfPs, Body, Ret) ; cpp_type(Ret0, Ret) ),   % IN THE ENCLOSING CONTEXT: a member named in the body is a call or an access of this, which has a type
    findall(member(MT, N, none), ( member(N-How, Captures), ( How = val(CT) -> MT = CT ; How = ref(CT), MT = ref([], CT) ) ), Ms1),
    findall(item([], V), ( member(N-How, Captures), ( How = val(_) -> V0 = id(N) ; V0 = addr(id(N)) ), cpp_expr(Ctx, V0, V) ), Items1),
    (   cpp_captures_this(Ctx, Caps, Body, EC)                                                   % `[this]', and a default capture where the body names the enclosing class
    ->  cpp_note_closure_this(Name, EC), Ms0 = [member(ref([], base([], [typedef(EC)])), '$this', none)|Ms1], Items = [item([], id(this))|Items1]   % a REFERENCE to the object, as a `[&x]' capture is: the lowering reads a reference member through, and the check counts it as one
    ;   Ms0 = Ms1, Items = Items1 ),
    append(Self, Ps, MPs), append(Ms0, [method(0, [closure], Ret, operator('()'), MPs, false, Body)], Ms),
    cpp_isolated(( cpp_register_class(0, Name, [], Ms), cpp_item(declare(0, base([], [class(struct, Name, [], Ms)])), Its) )),
    cpp_add_instance_items(Its).
%% A LAMBDA CAPTURES THIS where `[this]' says so, and under a DEFAULT capture where its body names anything of the
%% enclosing class -- a data member, a static or a method, or `this' itself. The closure keeps the enclosing object's
%% address in the member `'$this'', and inside its operator() a name of that class is reached through it, as C++'s
%% closure reaches it: the capture is by REFERENCE to the object (C++ captures the pointer, never the object).
cpp_captures_this(Ctx, Caps, _, Ctx) :- atom(Ctx), memberchk(cap(this), Caps), !.
cpp_captures_this(Ctx, Caps, Body, Ctx) :- atom(Ctx), memberchk(cap(default, _), Caps), cpp_names_enclosing(Ctx, Body), !.
cpp_names_enclosing(C, Body) :- cpp_ids(Body, Ids), member(N, Ids), cpp_has_member(C, N), !.
cpp_names_enclosing(_, Body) :- cpp_mentions_this(Body), !.
cpp_mentions_this(this) :- !.
cpp_mentions_this(T) :- compound(T), T =.. [_|As], member(A, As), cpp_mentions_this(A), !.
cpp_has_member(C, N) :- cpp_data_member(C, N, _), !.
cpp_has_member(C, N) :- cpp_static_member(C, N, _), !.
cpp_has_member(C, N) :- '$cpp_mt'(C, N, _, _), !.                                        % a MEMBER TEMPLATE, which libc++'s vector names from a lambda inside emplace_back
cpp_has_member(C, N) :- cpp_class(C, cls(_, _, Ms, _, _, _)), member(M, Ms), cpp_member_named(M, N), !.
cpp_has_member(C, N) :- cpp_base_scope(C, B), cpp_has_member(B, N), !.
cpp_member_named(template(_, _, M), N) :- !, cpp_member_named(M, N).
cpp_member_named(method(_, _, _, N, _, _, _), N).
cpp_member_named(member(_, N, _), N).
cpp_note_closure_this(Name, C) :- nb_getval('$cpp_closure_this', L), nb_setval('$cpp_closure_this', [Name-C|L]).
cpp_closure_this(Ctx, C) :- atom(Ctx), nb_getval('$cpp_closure_this', L), memberchk(Ctx-C, L).
cpp_this_of_closure(arrow(id(this), '$this')).                                           % the enclosing OBJECT, an lvalue through the reference member (the closure's own this is a pointer)
cpp_closure_member(N, Hops, member(B, N)) :- cpp_this_of_closure(R), cpp_hops(R, Hops, B).
cpp_closure_object(Hops, addr(B)) :- cpp_this_of_closure(R), cpp_hops(R, Hops, B).       % its address, which a method takes as `this'
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
cpp_lambda_ret(Ps, Body, Ret) :- cpp_lambda_ret(none, Ps, Body, Ret).
%% the first return DESUGARED in the enclosing context and then typed, as a method's auto result already was
%% (cpp_method_ret): the body of a lambda in a member function names the class's members, which have a type only
%% once they are the calls and accesses the desugaring makes of them -- and here, where the lambda stands, the
%% enclosing locals and `this' are still in scope
cpp_lambda_ret(Ctx, Ps, Body, Ret) :-
    (   cpp_first_return(Body, E)
    ->  ccl_scope_push, ccl_declare_params(Ps),
        ( catch(cpp_expr(Ctx, E, E1), error(not_lowered(_), _), fail) -> true ; E1 = E ),
        ( ccl_type_of(E1, T), T \== unknown -> Ret = T ; Ret = none ), ccl_scope_pop,
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
