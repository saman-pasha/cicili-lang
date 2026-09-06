%% cicili-lang -- library(ccl_check): the safe part. The ownership check,
%% run by cicili_ir/2 before anything is lowered.
%%
%% An OWNER is a pointer declared with the qualifier `own' -- a local, a
%% parameter (the callee owns what it is given), or a FIELD of a struct held
%% by an owner or by value (`a->name', `p.name', `p.inner.name'). An owner is
%% linear: it is CONSUMED exactly once on every path, by free(p) or fclose(p),
%% by move(p) (into another owner, or as an argument), by `return p', or by
%% passing it to a function whose parameter is `own'; a defer(p) { free(p); }
%% consumes it at the scope's exit, on every path, as the lowering runs it.
%% A consumed owner may own again by assignment. clone(p) hands a function a
%% fresh copy of what p points to (a statement expression whose last value is
%% a new owner), so p is not consumed.
%%
%% The states of an owner: live (holds memory), null (holds nothing: a null
%% constant was assigned; freeing or moving it is fine, so is overwriting it),
%% unset (declared without a value, or a field of a struct fresh from malloc:
%% garbage, not to be read, freed or moved), moved (consumed), partial (moved
%% on one path and not on another: not to be used, and a leak where a live one
%% would be). The walk is flow-sensitive: the states are threaded through the
%% statements and joined at every merge; a path that ends (return, break,
%% continue) contributes its state where it goes.
%%
%% A struct's own fields go with the struct. Freeing an owner (free, fclose)
%% demands its fields consumed first, else the field leaks; moving it (move,
%% an own parameter, return) demands them complete -- live or null -- and moves
%% them along; a struct copied by value moves its fields into the copy. An own
%% pointer from a call other than malloc/calloc/realloc is complete; one from
%% malloc has unset fields. Only a variable's own fields are tracked, and the
%% fields of the structs it holds by value: what an own pointer FIELD points to
%% is not opened (a list's next is one owner, whatever it holds).
%%
%% A BORROW is a plain pointer whose value came from an owner -- `char *q = p',
%% `q = p + 1', `&p[i]', `&p->x', `a->name', or from another borrow. It is
%% bound to the owner: the moment the owner is consumed the borrow dangles, and
%% a use of it is refused; a borrow may not be returned, since the owner is
%% consumed by then; and a borrow, or an owner's pointer, may only be held by a
%% local plain pointer -- stored into a plain struct field, an array element,
%% through a pointer, or into a global, the checker could not follow it, so
%% that is refused. An OWN field or slot receives an owner (moved in), a null,
%% or a fresh value, never a borrow. Assigning a borrow from something else
%% unbinds it.
%%
%% A PLAIN POINTER PARAMETER is a borrow of the caller's, tagged with its own
%% name: the callee may read it, pass it on, and return it (the caller still
%% owns what it points to), but not store it, free it, or move it -- so a
%% borrow handed to any function is safe, and `own' is the one way memory
%% comes in. What a borrowed pointer reaches -- a member, an element, what it
%% points to -- is borrowed from the same. A callee's prototype is read the
%% same way through a function pointer.
%%
%% A TIE is declared with the tie operator, `x <*> y': x lives within y. y is
%% declared before x -- in scope, an earlier parameter, an earlier member of
%% the struct -- and x is dead the moment y is consumed or y's scope ends. A
%% tied plain value is a BORROW of y (of y's root, when y is itself a borrow),
%% whatever its type: it dangles when y goes, may not escape, and takes only
%% values whose root outlives y (y within the root: the same, or tied to it).
%% A tied OWNER must be consumed before y is, and may be moved
%% only into a slot within y, or to a parameter tied the same way. A struct
%% member tied to an earlier member is such a slot in every instance (`l.cur'
%% tied to `l.head'), where a borrow of the tie may be stored -- the one place
%% a borrow is stored; a struct instance tied to an owner may hold borrows of
%% it in any plain field. On a prototype the tie is a contract: a parameter
%% tied to an earlier one is checked at every call, the argument within the
%% argument; a result tied to a parameter makes the caller's variable a borrow
%% of that argument, and the callee's returns are checked against it. A tie
%% to a plain local ANCHORS it: a root consumed by nothing, ending with its
%% scope, so what is tied to it dangles there; `&x' of a plain local and a
%% local array used as a pointer anchor it the same way.
%%
%% THE ERRORS, each error(ownership(Kind, Name, Form), where(Function, line(L))),
%% the line the statement's, Name the owner's path (`a->name'):
%%   use_after_move      a consumed owner read, passed, freed again (the double free)
%%   owner_unset         an owner read, passed, freed or moved before it was given anything
%%   borrow_after_move   a borrow used after its owner was consumed (a tied value after its tie went)
%%   borrow_escapes      a borrow returned from the function
%%   borrow_stored       a borrow stored into a struct field, an element, a global, through a pointer, or into an own slot
%%   borrow_consumed     a borrow freed, or passed where an owner is taken (a parameter freed in its callee)
%%   borrow_incomplete   an own field of a struct a parameter points to, freed or moved out and not replaced by the return
%%   owner_stored        an owner's pointer stored into a plain slot (its ownership would be lost)
%%   owner_leaked        an owner live, or partial, at its scope's end, at a return, or a field when its struct is freed
%%   move_in_loop        an owner from outside a loop consumed inside it (and not re-assigned)
%%   move_of_non_owner   move(x) of something that is not an owner
%%   owner_overwritten   assignment to a live owner (what it held would leak)
%%   goto_with_owners    a goto in a function that has owners (not followed yet)
%%   tie_unknown         `<*> y' with no y declared before it (in scope, an earlier parameter or member)
%%   tie_outlived        an owner tied to y still live when y is consumed
%%   tie_escapes         a tied owner moved beyond its tie: into an untied slot, to an untied own parameter, returned with no result tie
%%   tie_mismatch        a value not within the tie of the slot, the parameter or the result it is given to
%%   own_unbounded       an own pointer with no owner to name: behind a plain pointer, in an array with no constant bound, an array parameter
%%   own_array_by_value  a struct with an own array held by value
%%   own_array_untagged  an own array in a struct without a tag
%%   array_unset         an own array not zeroed at birth: from malloc or realloc, or a local without an initializer
%% A plain pointer LOCAL given fresh memory -- malloc's result, an untied
%% function's, anything not null, not static, not a borrow -- is LOOSE: memory
%% with no owner behind it, that the check follows as an owner without the
%% word. free (fclose, realloc, an own parameter), a return, a store into a
%% slot, or an own slot taking it over consumes it; a borrow of it dangles
%% when it is freed, as an owner's would; and where it is still unconsumed --
%% its scope's end, a return, an overwrite -- it is refused (owner's rule:
%% every pointer has an ownership path, or the program is not accepted):
%%   unconsumed          a loose pointer (a plain local holding fresh memory) at its scope's end, a return, or overwritten
%%   untied              a slot the check cannot follow -- a field, an element, a global, *p, a struct by value -- given a value with no owner behind it
%% An OWN ARRAY, `own node *c[4]', holds a fixed number of owners: which one an
%% index names cannot be told at compile time, so the array is one key whose
%% elements are null or owned -- an invariant the lowering keeps by draining
%% it: every non-null element freed (its own struct drained first) when the
%% struct holding it is freed or the local's scope ends, the old element freed
%% when one is overwritten, the slot nulled when an element is moved out or
%% consumed. The check asks the rest: an element takes an owner (moved in), a
%% null or a fresh value, never a borrow; an element leaves by move (or free,
%% or an own parameter), and every borrow of the array dangles when any
%% element goes; the array is zeroed at birth (calloc, an initializer, a call:
%% `array_unset' for malloc or nothing); it lives as a local or in a struct
%% behind an own pointer, never by value (`own_array_by_value': a copy would
%% own its elements twice), in a struct with a tag (`own_array_untagged': the
%% drain is a function named by it); and an own pointer sits nowhere else --
%% behind a plain pointer, in an array with no constant bound, as an array
%% parameter -- `own_unbounded'. One more bound the check can name: a struct's
%% LAST member may be `own T *a[n]' with n an earlier integer member of the
%% same struct, a flexible array the developer allocates room for and counts
%% (`calloc(1, sizeof(struct s) + k * sizeof(T *))', `s->n = k'); the drain
%% loops to n. A wrong n is the developer's, as a wrong index is.
%%
%% A function's result may be tied to a static local of its own or to a global
%% (`<*> table'): the caller's variable is then a borrow of static storage,
%% static(Name), which nothing ends and nothing may free. `if (!p)' and
%% `if (p == NULL)' make an owner null on the then path, `if (p)' and
%% `if (p != NULL)' on the else path, its own fields with it.
%% Not tracked: what a plain pointer reaches is not opened for ownership (a
%% borrowed struct's own field may be given an owner, that is all).

:- use_module(library(ccl_infer)).

ccl_check_units(Units) :- ccl_ensure_globals, ccl_scope_init, ck_note_units(Units), ck_units(Units).
ccl_check_noted(Units) :- ck_units(Units).                            % on the table the caller built
ck_note_units([]).
ck_note_units([unit(Is)|Us]) :- ccl_items_note(Is), ck_note_units(Us).
ck_units([]).
ck_units([unit(Is)|Us]) :- ck_items(Is), ck_units(Us).
ck_items([]).
ck_items([function(L, _, Ret, Name, Params, _, Body)|Is]) :- !, ck_function(L, Ret, Name, Params, Body), ck_items(Is).
ck_items([_|Is]) :- ck_items(Is).

%% ---- state: frames of Key-State, innermost first; with each frame its defers ----------
ck_function(L, Ret, Name, Params0, Body) :-
    ck_ref_params(Params0, Params),                                      % C++: a reference parameter is a borrow, as a pointer is
    nb_setval('$ck_fn', Name), nb_setval('$ck_ret', Ret), nb_setval('$ck_line', L), nb_setval('$ck_loops', []), nb_setval('$ck_ties', []), nb_setval('$ck_statics', []), nb_setval('$ck_arrays', []),
    nb_setval('$ck_arrlocals', []), ck_note_arrparams(Params),
    ccl_scope_push, ccl_declare_params(Params),
    ck_param_names(Params, Names), nb_setval('$ck_params', Names),
    (   ccl_tie_of(Ret, RY)
    ->  (   memberchk(RY, Names) -> RT = RY
        ;   ck_body_static(Body, RY) -> RT = static(RY)                   % a static local of the function's, or a global: storage nothing ends
        ;   ck_is_global(RY) -> RT = static(RY)
        ;   ck_fail(tie_unknown, RY, result(Name)) ),
        nb_setval('$ck_ret_tie', RT)
    ;   nb_setval('$ck_ret_tie', none) ),
    ck_borrowed_fields(Params, Borrowed), nb_setval('$ck_borrowed', Borrowed),
    ck_dying_fields(Params, Dying), nb_setval('$ck_dying_fields', Dying),
    ck_param_owners(Params, Owners),
    ck_param_ties(Params, [], st([fr(Owners, [])]), St0),
    ck_stmt(Body, St0, St1),
    ( St1 == dead -> true ; St1 = st([fr(Os, _)]), ck_complete_owners(Os, function_end), ck_leaks_all(St1, function_end) ),
    ccl_scope_pop.
%% the own fields of the structs the plain pointer parameters point to: the
%% struct's, not the callee's -- one may be freed and replaced, and must be
%% whole (live or null) again when the callee returns
ck_borrowed_fields([], []).
ck_borrowed_fields([param(T, N)|Ps], Fs) :-
    ck_borrowed_fields(Ps, Fs0),
    ( N \== anon, \+ ck_own_type(T), ck_pointee_fields(N, T, Fs1) -> append(Fs1, Fs0, Fs) ; Fs = Fs0 ).
ck_pointee_fields(N, T, Fs) :- ccl_resolve_type(T, ptr(_, PT)), ccl_members_of(PT, Ms), ck_member_fields(Ms, N, '->', Fs), Fs \== [].
ck_is_borrowed_field(N) :- nb_getval('$ck_borrowed', Bs), memberchk(N, Bs).
ck_complete_owners([], _).
ck_complete_owners([N-S|Os], Form) :-
    ( ck_is_borrowed_field(N), \+ ck_is_dying_field(N), \+ memberchk(S, [live, null, array]) -> ck_fail(borrow_incomplete, N, Form) ; true ),
    ck_complete_owners(Os, Form).
%% C++ (M6): a constructor's `this' points at fresh storage -- its own fields
%% start unset, and must be live or null when it returns -- and a destructor's
%% at dying storage: its fields may be consumed and left, and the caller of a
%% destructor (delete, a scope's end) takes the object's own fields as moved.
%% The desugaring marks the pointee: ptr(_, base([fresh | dying], ...)).
ck_this_marker(T, M) :- ccl_resolve_type(T, ptr(_, base(Q, _))), memberchk(M, Q), !.
ck_dying_fields([], []).
ck_dying_fields([param(T, N)|Ps], Fs) :-
    ck_dying_fields(Ps, Fs0),
    ( N \== anon, ck_this_marker(T, dying), ck_pointee_fields(N, T, Fs1) -> ck_field_names(Fs1, Ns), append(Ns, Fs0, Fs) ; Fs = Fs0 ).
ck_field_names([], []).
ck_field_names([K-_|Fs], [K|Ns]) :- !, ck_field_names(Fs, Ns).
ck_field_names([K|Fs], [K|Ns]) :- ck_field_names(Fs, Ns).
ck_is_dying_field(N) :- nb_getval('$ck_dying_fields', Ds), memberchk(N, Ds).
ck_dying_param(Callee, I) :- ck_callee_params(Callee, Ps), ccl_nth(I, Ps, param(PT, _)), ck_this_marker(PT, dying).
ck_fresh_param(Callee, I) :- ck_callee_params(Callee, Ps), ccl_nth(I, Ps, param(PT, _)), ck_this_marker(PT, fresh).
%% the callee takes the argument by value (not by C++'s reference, which borrows); an unknown callee is taken to
ck_param_by_value(Callee, I) :- ( ck_callee_params(Callee, Ps), ccl_nth(I, Ps, param(PT, _)) -> \+ PT = ref(_, _), \+ PT = rref(_, _) ; true ).
ck_arg_base(addr(id(K)), K) :- !.
ck_arg_base(addr(E), K) :- ck_path(E, K), !.                                   % &this->name, &p.name: the member's own fields
ck_arg_base(id(K), K).
ck_body_static(declaration(_, static, _, Vs), N) :- member(var(N, _, _), Vs), !.
ck_body_static(T, N) :- compound(T), T =.. [_|As], member(A, As), ck_body_static(A, N), !.
ck_param_names([], []).
ck_param_names([param(_, N)|Ps], Ns) :- ck_param_names(Ps, Ns0), ( N == anon -> Ns = Ns0 ; Ns = [N|Ns0] ).
ck_is_param(N) :- nb_getval('$ck_params', Ps), memberchk(N, Ps).
%% an own parameter is an owner, complete: its own fields are live; a struct
%% given by value with own fields owns those fields (the struct itself is not
%% freed); a plain pointer parameter is a BORROW of the caller's, tagged with
%% its own name: read, passed on and returned, never stored, freed or moved
ck_param_owners([], []).
ck_param_owners([param(T, N)|Ps], Os) :-
    ck_param_owners(Ps, Os0),
    (   N == anon -> Os = Os0
    ;   ck_own_type(T)
    ->  ck_var_fields(N, T, Fs), ck_field_states(Fs, complete, FOs),
        ( ck_is_pointer_type(T) -> append([N-live|FOs], Os0, Os) ; append(FOs, Os0, Os) )
    ;   ck_is_pointer_type(T) -> ( ck_pointee_fields(N, T, Fs) -> ( ck_this_marker(T, fresh) -> Mode = garbage ; Mode = complete ), ck_field_states(Fs, Mode, FOs) ; FOs = [] ), append([N-borrow(N)|FOs], Os0, Os)
    ;   ccl_resolve_type(T, arr(_, _)) -> Os = [N-borrow(N)|Os0]
    ;   ck_var_fields(N, T, Fs), Fs \== [] -> ck_field_states(Fs, complete, FOs), append(FOs, Os0, Os)   % a struct by value with owners inside: theirs to consume (a moved string)
    ;   Os = Os0 ).
%% the ties of the parameters, in order: the fields' (a struct's members tied
%% to earlier members, in what an own or a plain pointer parameter points to,
%% or a struct given by value), then the parameter's own, to an earlier one
ck_param_ties([], _, St, St).
ck_param_ties([param(T, N)|Ps], Seen, St0, St) :-
    (   N == anon -> St2 = St0, Seen1 = Seen
    ;   ( ck_own_array_type(T) -> ck_fail(own_unbounded, N, param(N)) ; ck_type_rules(N, T, param(N)) ),
        (   ck_own_type(T) -> ck_var_ties(N, T, Ts)
        ;   ck_is_pointer_type(T) -> ( ck_pointee_ties(N, T, Ts) -> true ; Ts = [] )
        ;   ck_var_ties(N, T, Ts) ),
        ck_field_ties_(Ts, St0, St1),
        (   ccl_tie_of(T, Y) -> ( memberchk(Y, Seen) -> true ; ck_fail(tie_unknown, Y, param(N)) ), ck_var_tie(N, T, St1, St2)
        ;   St2 = St1 ),
        Seen1 = [N|Seen] ),
    ck_param_ties(Ps, Seen1, St2, St).
%% `own char *p': C's grammar puts the qualifier with the pointee, so an owner
%% is a pointer with own on itself or on what it points to
ck_own_type(ptr(Q, B)) :- ( memberchk(own, Q) ; B = base(Q2, _), memberchk(own, Q2) ), !.
ck_own_type(base(Q, _)) :- memberchk(own, Q), !.
ck_is_pointer_type(T) :- ccl_resolve_type(T, T1), T1 = ptr(_, _), !.
%% a type whose value carries a pointer: a pointer, an array of them, a struct
%% holding one at any depth -- what a borrow, or a tie, travels in
ck_carries_type(T) :- ccl_resolve_type(T, T1), ck_carries_(T1).
ck_carries_(ptr(_, _)) :- !.
ck_carries_(block(_, _)) :- !.
ck_carries_(arr(_, E)) :- !, ck_carries_type(E).
ck_carries_(T) :- ccl_members_of(T, Ms), member(member(MT, _, _), Ms), ck_carries_type(MT), !.

%% the own fields of a variable: N->f under an own pointer to a struct, N.f in a
%% struct held by value; a member held by value opens its own fields too
%% (N.inner.f); an own pointer member is one field and stops there
ck_var_fields(N, T, Fs) :-
    ccl_resolve_type(T, T1),
    (   T1 = ptr(_, PT), ck_own_type(T), ccl_members_of(PT, Ms) -> ck_member_fields(Ms, N, '->', Fs)
    ;   T1 = base(_, [struct(_, _)]), ccl_members_of(T1, Ms) -> ck_member_fields(Ms, N, '.', Fs)
    ;   Fs = [] ).
ck_member_fields([], _, _, []).
ck_member_fields([M|Ms], Base, Sep, Fs) :- M \= member(_, _, _), !, ck_member_fields(Ms, Base, Sep, Fs).   % a C++ class's methods, labels
ck_member_fields([member(MT, F, _)|Ms], Base, Sep, Fs) :-
    (   F == anon -> Fs = Fs1
    ;   atomic_list_concat([Base, Sep, F], K),
        (   ck_own_type(MT) -> Fs = [K|Fs1]
        ;   ck_own_array_type(MT) -> ck_note_array(K), Fs = [K|Fs1]
        ;   ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]), ccl_members_of(MT1, Sub) -> ck_member_fields(Sub, K, '.', Fs0), append(Fs0, Fs1, Fs)
        ;   Fs = Fs1 ) ),
    ck_member_fields(Ms, Base, Sep, Fs1).
ck_states([], _, []).
ck_states([K|Ks], S, [K-S|Ps]) :- ck_states(Ks, S, Ps).
%% the fields' states by how the struct was born: complete (a call, a move),
%% zeroed (calloc: null), garbage (malloc: unset); an own array is `array' or
%% refused, since the lowering drains it and garbage cannot be drained
ck_field_states([], _, []).
ck_field_states([K|Ks], Mode, [K-S|Ps]) :- ck_field_state(K, Mode, S), ck_field_states(Ks, Mode, Ps).
ck_field_state(K, Mode, S) :- ( ck_is_array_key(K) -> S = array ; Mode == garbage -> S = unset ; Mode == zeroed -> S = null ; S = live ).
ck_alloc_mode(call(id(F), _), garbage) :- memberchk(F, [malloc, realloc]), !.
ck_alloc_mode(call(id(calloc), _), zeroed) :- !.
ck_alloc_mode(cast(_, E), M) :- !, ck_alloc_mode(E, M).                              % C++'s new T is (T *) malloc(sizeof(T))
ck_alloc_mode(new(_, []), garbage) :- !.                                            % new T of a struct without a constructor: malloc's bytes
ck_alloc_mode(new_array(_, _), garbage) :- !.
ck_alloc_mode(_, complete).
ck_set_fields(St0, Key, Mode, Form, St) :-
    ck_under_states(St0, Key, Ps),
    ( Mode == garbage, member(A-_, Ps), ck_is_array_key(A) -> ck_fail(array_unset, A, Form) ; true ),
    ck_set_fields_(Ps, Mode, St0, St).
ck_set_fields_([], _, St, St).
ck_set_fields_([K-S|Ps], Mode, St0, St) :-
    (   ck_is_array_key(K) -> ck_set(St0, K, array, St1)
    ;   ck_owner_state(S) -> ck_field_state(K, Mode, S1), ck_set(St0, K, S1, St1)
    ;   St1 = St0 ),
    ck_set_fields_(Ps, Mode, St1, St).

%% ---- own arrays ---------------------------------------------------------------------------
%% `own node *c[4]': the key is the array's (a local's name, a field's path,
%% listed in '$ck_arrays'), its state `array'; an element is index(Path, _)
ck_own_array_type(arr(_, ET)) :- !, ck_own_type(ET).                            % asked of every type the lowering meets: the shape first
ck_own_array_type(ptr(_, _)) :- !, fail.
ck_own_array_type(base(_, [S|_])) :- atom(S), !, fail.
ck_own_array_type(T) :- ccl_resolve_type(T, arr(_, ET)), ck_own_type(ET), !.
ck_const(E, N) :- ccl_const_eval(E, N), !.                          % a literal, an enumerator, a constant expression
ck_note_array(K) :- nb_getval('$ck_arrays', As), ( memberchk(K, As) -> true ; nb_setval('$ck_arrays', [K|As]) ).
ck_is_array_key(K) :- nb_getval('$ck_arrays', As), memberchk(K, As).
ck_own_elem(index(A, _), K) :- ck_path(A, K), ck_is_array_key(K).
ck_has_array_under(St, K) :- ck_under_states(St, K, Ps), member(A-_, Ps), ck_is_array_key(A), !.
%% the rules a declared type must meet: an own pointer only where its owner is
%% named (never behind a plain pointer, never in an array without a constant
%% bound); a struct with an own array behind a pointer, never by value, and
%% with a tag
ck_type_rules(N, T, Form) :-
    ck_bounds_ok(T, N, Form),
    ccl_resolve_type(T, T1),
    (   T1 = ptr(_, PT) -> ck_array_struct_ok(PT, N, Form)
    ;   T1 = base(_, [struct(_, _)]) -> ( ck_has_own_array(T1) -> ck_fail(own_array_by_value, N, Form) ; true )
    ;   true ).
ck_bounds_ok(T, N, Form) :- ccl_resolve_type(T, T1), ck_bounds_ok_(T1, N, Form).
ck_bounds_ok_(arr(NE, ET), N, Form) :- !, ( ck_own_type(ET), \+ ck_const(NE, _) -> ck_fail(own_unbounded, N, Form) ; true ), ck_bounds_ok(ET, N, Form).
ck_bounds_ok_(ptr(_, ET), N, Form) :- !,
    ccl_resolve_type(ET, ET1),
    (   ( ET1 = ptr(_, _), ck_own_type(ET1) ; ck_own_array_type(ET1) ) -> ck_fail(own_unbounded, N, Form)
    ;   ( ET1 = ptr(_, _) ; ET1 = arr(_, _) ) -> ck_bounds_ok(ET1, N, Form)
    ;   true ).
ck_bounds_ok_(_, _, _).
ck_array_struct_ok(T, N, Form) :-
    ccl_resolve_type(T, T1),
    (   ck_has_own_array(T1)
    ->  ( T1 = base(_, [struct(anon, _)]) -> ck_fail(own_array_untagged, N, Form) ; true ),
        ccl_members_of(T1, Ms), ck_members_ok(Ms, [], Form)
    ;   true ).
%% a member's bound: a constant, or -- for the last member -- an earlier integer member
ck_members_ok([], _, _).
ck_members_ok([member(MT, F, _)|Ms], Seen, Form) :-
    (   ccl_resolve_type(MT, arr(NE, ET)), ck_own_type(ET), \+ ck_const(NE, _)
    ->  ( NE = id(B), memberchk(B-BT, Seen), ccl_is_integer(BT), Ms == [] -> true ; ck_fail(own_unbounded, F, Form) )
    ;   ck_bounds_ok(MT, F, Form) ),
    ( ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]) -> ck_array_struct_ok(MT1, F, Form) ; true ),
    ck_members_ok(Ms, [F-MT|Seen], Form).
%% answered once per tag: the lowering asks it of every struct in the symbol
%% table, the headers' too, and walks their members with a resolution each
ck_has_own_array(T) :-
    (   ccl_resolve_type(T, base(_, [struct(Tag, _)])), Tag \== anon
    ->  ccl_cached_named('$ck_oa:', Tag, V, ( ck_has_own_array_nocache(T) -> V = yes ; V = no )), V == yes
    ;   ck_has_own_array_nocache(T) ).
ck_has_own_array_nocache(T) :-
    ccl_members_of(T, Ms), member(member(MT, _, _), Ms),
    ( ck_own_array_type(MT) -> true ; ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]), ck_has_own_array(MT1) ), !.
ck_no_array_copy(St, K, Form) :- ( ck_has_array_under(St, K) -> ck_fail(own_array_by_value, K, Form) ; true ).
%% the tied fields of a variable, Key-TieKey in member order (a tie names an
%% earlier member, else tie_unknown): under an own pointer with `->', in a
%% struct by value with `.', a member held by value opened the same way
ck_var_ties(N, T, Ts) :-
    ccl_resolve_type(T, T1),
    (   T1 = ptr(_, PT), ck_own_type(T), ccl_members_of(PT, Ms) -> ck_member_ties(Ms, N, '->', [], Ts)
    ;   T1 = base(_, [struct(_, _)]), ccl_members_of(T1, Ms) -> ck_member_ties(Ms, N, '.', [], Ts)
    ;   Ts = [] ).
ck_pointee_ties(N, T, Ts) :- ccl_resolve_type(T, ptr(_, PT)), ccl_members_of(PT, Ms), ck_member_ties(Ms, N, '->', [], Ts).
ck_member_ties([], _, _, _, []).
ck_member_ties([member(MT, F, _)|Ms], Base, Sep, Seen, Ts) :-
    (   F == anon -> Ts = Ts1, Seen1 = Seen
    ;   atomic_list_concat([Base, Sep, F], K),
        (   ccl_tie_of(MT, Y) -> ( memberchk(Y, Seen) -> true ; ck_fail(tie_unknown, Y, member(F)) ), atomic_list_concat([Base, Sep, Y], YK), Ts = [K-YK|Ts0]
        ;   Ts = Ts0 ),
        (   ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]), ccl_members_of(MT1, Sub) -> ck_member_ties(Sub, K, '.', [], Sub1), append(Sub1, Ts1, Ts0)
        ;   Ts0 = Ts1 ),
        Seen1 = [F|Seen] ),
    ck_member_ties(Ms, Base, Sep, Seen1, Ts1).

%% the path an lvalue names: a, a.f, a->f, a->inner.f
ck_path(id(N), N) :- atom(N).
ck_path(member(E, F), K) :- ck_path(E, B), atomic_list_concat([B, '.', F], K).
ck_path(arrow(E, F), K) :- ck_path(E, B), atomic_list_concat([B, '->', F], K).
ck_owner_path(St, E, K) :- ck_path(E, K), ck_is_owner(St, K).
%% the base of a path: `a' of `a.f', `a->f' of `a->f.g'
ck_base_path(K, B) :-
    atom(K), sub_atom(K, Bl, _, _, Sep), memberchk(Sep, ['.', '->']),
    \+ ( sub_atom(K, Bl2, _, _, Sep2), memberchk(Sep2, ['.', '->']), Bl2 > Bl ),
    sub_atom(K, 0, Bl, _, B).
%% the keys under a base: its fields, at any depth; the own ones among them
ck_under(st(Frs), Base, Keys) :- ck_under_states(st(Frs), Base, Ps), ck_keys(Ps, Keys).
ck_own_under(St, Base, Keys) :- ck_under_states(St, Base, Ps), ck_own_keys(Ps, Keys).
ck_under_states(st(Frs), Base, Ps) :-
    atom_concat(Base, '.', P1), atom_concat(Base, '->', P2),
    findall(K-S, ( member(fr(Os, _), Frs), member(K-S, Os), atom(K), ( sub_atom(K, 0, _, _, P1) ; sub_atom(K, 0, _, _, P2) ) ), Ps).
ck_keys([], []).
ck_keys([K-_|T], [K|Ks]) :- ck_keys(T, Ks).
ck_own_keys([], []).
ck_own_keys([K-S|T], Ks) :- ( ck_owner_state(S) -> Ks = [K|Ks1] ; Ks = Ks1 ), ck_own_keys(T, Ks1).
ck_owner_state(S) :- memberchk(S, [live, moved, partial, null, unset]).
%% the base of a path is read when the path is
ck_base_use(id(_), St, St) :- !.
ck_base_use(member(E, _), St0, St) :- !, ck_expr(E, St0, St).
ck_base_use(arrow(E, _), St0, St) :- !, ck_expr(E, St0, St).
ck_base_use(move(E), St0, St) :- !, ck_base_use(E, St0, St).
ck_base_use(_, St, St).
ck_strip_move(move(E), E) :- !.
ck_strip_move(E, E).
%% a null constant
ck_null(int(0)).
ck_null(id('NULL')).
ck_null(cast(ptr(_, base(_, [void])), int(0))).                                  % NULL expanded: ((void *)0)
ck_null(int(0)).
ck_null(cast(_, E)) :- ck_null(E).
ck_null(nullptr).                                                                % C++
ck_null(ccast(_, _, E)) :- ck_null(E).
%% C++ (M6): the check sees a reference as the pointer it is -- a parameter a
%% borrow, a local bound to an lvalue a borrow of its address (an anchor, an
%% array's element); one bound to a call's result is not followed (no state)
%% The reference names of the function are '$ck_refs': a use of one as a
%% place is a use of what it refers to (`x = v' stores through, `&x' is the
%% pointer held), never a rebinding of the pointer.
ck_ref_params(Ps0, Ps) :- ck_ref_params_(Ps0, Ps, Names), nb_setval('$ck_refs', Names).
ck_ref_params_([], [], []).
ck_ref_params_([param(T0, N)|Ps], [param(T, N)|Ps1], Ns) :- !, ck_ref_as_ptr(T0, T), ( T \== T0 -> Ns = [N|Ns1] ; Ns = Ns1 ), ck_ref_params_(Ps, Ps1, Ns1).
ck_ref_params_([P|Ps], [P|Ps1], Ns) :- ck_ref_params_(Ps, Ps1, Ns).
ck_ref_as_ptr(ref(Q, T), ptr(Q, T)) :- !.
ck_ref_as_ptr(rref(Q, T), ptr(Q, T)) :- !.
ck_ref_as_ptr(T, T).
ck_ref_decl(N, T0, Init0, T, Init) :-
    (   ck_ref_as_ptr(T0, T), T \== T0
    ->  nb_getval('$ck_refs', Rs), nb_setval('$ck_refs', [N|Rs]),
        ( ck_lvalue_form(Init0) -> Init = addr(Init0) ; Init = none )
    ;   T = T0, Init = Init0,
        ( nb_getval('$ck_refs', Rs), memberchk(N, Rs) -> ccl_delete_one(Rs, N, Rs1), nb_setval('$ck_refs', Rs1) ; true ) ).
ck_is_ref(N) :- nb_getval('$ck_refs', Rs), memberchk(N, Rs).
ck_lvalue_form(id(_)).
ck_lvalue_form(scoped(_, _)).
ck_lvalue_form(index(_, _)).
ck_lvalue_form(member(_, _)).
ck_lvalue_form(arrow(_, _)).
ck_lvalue_form(deref(_)).
%% a value that lives as long as the program: a string literal, a global's
%% address, a global array or function used as a pointer
ck_static_value(str(_)) :- !.
ck_static_value(cast(_, E)) :- !, ck_static_value(E).
ck_static_value(addr(E)) :- !, ck_storage_base(E, N), ck_is_global(N).
ck_static_value(id(N)) :- !, ck_is_global(N), ccl_declared(N, T), ccl_resolve_type(T, T1), ( T1 = arr(_, _) ; T1 = fn(_, _, _) ), !.
ck_static_value(bin(Op, A, _)) :- memberchk(Op, ['+', '-']), !, ck_static_value(A).
ck_static_value(cond(_, A, B)) :- !, ck_static_value(A), ck_static_value(B).
ck_static_value(comma(_, B)) :- !, ck_static_value(B).

ck_line(L) :- ( integer(L), L > 0 -> nb_setval('$ck_line', L) ; true ).
ck_fail(Kind, Name, Form) :- nb_getval('$ck_fn', F), nb_getval('$ck_line', L), ck_short(Form, Short0), ck_squash(Short0, Short), throw(error(ownership(Kind, Name, Short), where(F, line(L)))).
%% a form without a macro's whole expansion in it
ck_squash(stmt_expr(_), '({ ... })') :- !.
ck_squash(T, S) :- compound(T), !, T =.. [F|As], ck_squash_list(As, Bs), S =.. [F|Bs].
ck_squash(T, T).
ck_squash_list([], []).
ck_squash_list([A|As], [B|Bs]) :- ck_squash(A, B), ck_squash_list(As, Bs).
%% a statement form is named without its line
ck_short(T, S) :- compound(T), functor(T, F, A), A > 1, memberchk(F, [expr, if, while, do, for, return, switch, case, default, label, goto]), arg(1, T, L), integer(L), !, T =.. [F, _|As], S =.. [F|As].
ck_short(return(L), return) :- integer(L), !.
ck_short(break(_), break) :- !.
ck_short(continue(_), continue) :- !.
ck_short(T, T).

%% lookup and update, innermost frame first
ck_state(st(Frs), N, S) :- ck_in(Frs, N, S).
ck_in([fr(Os, _)|Frs], N, S) :- ( memberchk(N-S0, Os) -> S = S0 ; ck_in(Frs, N, S) ).
ck_set(st(Frs), N, S, st(Frs1)) :- ck_set_(Frs, N, S, Frs1).
ck_set_([fr(Os, Ds)|Frs], N, S, [fr(Os1, Ds)|Frs]) :- memberchk(N-_, Os), !, ck_put(Os, N, S, Os1).
ck_set_([F|Frs], N, S, [F|Frs1]) :- ck_set_(Frs, N, S, Frs1).
ck_put([], _, _, []).
ck_put([N-_|T], N, S, [N-S|T]) :- !.
ck_put([X|T], N, S, [X|T1]) :- ck_put(T, N, S, T1).
ck_set_all(St, [], _, St).
ck_set_all(St0, [K|Ks], S, St) :- ( ck_state(St0, K, _) -> ck_set(St0, K, S, St1) ; St1 = St0 ), ck_set_all(St1, Ks, S, St).
ck_set_if(St0, K, S, St) :- ( ck_state(St0, K, _) -> ck_set(St0, K, S, St) ; St = St0 ).
ck_is_owner(St, N) :- ck_state(St, N, S), ck_owner_state(S).
%% a key declared in the innermost frame; a tie it had before is gone with it
ck_declare(st([fr(Os, Ds)|Frs]), N, S, st([fr([N-S|Os], Ds)|Frs])) :- ck_drop_tie(N).
ck_declare_all(St, [], St).
ck_declare_all(St0, [K-S|Ps], St) :- ck_declare(St0, K, S, St1), ck_declare_all(St1, Ps, St).
ck_push(st(Frs), st([fr([], [])|Frs])).
ck_declare_borrow(st([fr(Os, Ds)|Frs]), N, P, st([fr([N-borrow(P)|Os], Ds)|Frs])).
%% a plain pointer assigned again: a borrow of something else, or of nothing
ck_rebind(St0, N, none, St) :- !, ( ck_state(St0, N, S), ( S = borrow(_) ; S = dangling(_) ; S == loose ) -> ck_set(St0, N, none, St) ; St = St0 ).
ck_rebind(St0, N, S, St) :- ( ck_state(St0, N, _) -> ck_set(St0, N, S, St) ; ck_declare_at(St0, N, S, St) -> true ; ck_declare(St0, N, S, St) ).
%% a local: declared in a frame of the function's, not the file's, and not
%% static (a static local's storage never ends: a global's); its type from there
ck_is_local(N) :- \+ ck_is_static(N), ccl_locals(Ls), member(F, Ls), memberchk(N-_, F), !.
ck_is_static(N) :- nb_getval('$ck_statics', Ss), memberchk(N, Ss).
ck_note_statics([]).
ck_note_statics([var(N, _, _)|Vs]) :- nb_getval('$ck_statics', Ss), nb_setval('$ck_statics', [N|Ss]), ck_note_statics(Vs).
ck_local_type(N, T) :- ccl_locals(Ls), member(F, Ls), memberchk(N-T, F), !.
ck_is_global(N) :- atom(N), \+ ck_is_local(N), ccl_declared(N, _).

%% ---- ties ---------------------------------------------------------------------------------
%% '$ck_ties' holds Key-Root for every declared tie: a local's, a parameter's,
%% a field's in an instance; the root is an owner, an anchor, a parameter or a
%% global -- what y borrows when y is a borrow. A slot under a tied base is
%% tied to the base's root.
ck_note_tie(K, R) :- nb_getval('$ck_ties', Ts), ck_del_tie(K, Ts, Ts1), nb_setval('$ck_ties', [K-R|Ts1]).
ck_drop_tie(K) :- nb_getval('$ck_ties', Ts), ( memberchk(K-_, Ts) -> ck_del_tie(K, Ts, Ts1), nb_setval('$ck_ties', Ts1) ; true ).
ck_del_tie(_, [], []).
ck_del_tie(K, [K-_|T], T1) :- !, ck_del_tie(K, T, T1).
ck_del_tie(K, [X|T], [X|T1]) :- ck_del_tie(K, T, T1).
ck_declared_tie(K, R) :- nb_getval('$ck_ties', Ts), memberchk(K-R, Ts).
ck_tied_to(K, R) :- ck_declared_tie(K, R), !.
ck_tied_to(K, R) :- ck_base_path(K, B), ck_tied_to(B, R).
%% P lies within Y: the same; P tied to something within Y; P a borrow of
%% something within Y; P a field of something within Y
ck_within(_, P, P) :- !.
ck_within(St, _, P) :- ck_state(St, P, loose), !.                      % nobody ends a loose pointer's memory
ck_within(_, _, static(_)) :- !.                                        % nor static storage
ck_within(St, P, Y) :- ck_declared_tie(P, T), !, ck_within(St, T, Y).
ck_within(St, P, Y) :- ck_state(St, P, S), ( S = borrow(R) ; S = dangling(R) ), R \== P, !, ck_within(St, R, Y).
ck_within(St, P, Y) :- ck_base_path(P, B), ck_within(St, B, Y), !.
ck_within(St, Y, P) :- ck_base_path(P, B), ck_within(St, Y, B).        % a value rooted at a field: its holder stands for it (a child of x, returned as x's)
%% what `<*> y' refers to, for a local or a parameter: a key's root (its state
%% borrow or dangling when y is a borrow); a plain local, anchored now; a
%% global, which never ends; else nothing declared before, tie_unknown
ck_tie_ref(St0, Y, Form, St, Kind, R) :-
    (   ck_state(St0, Y, S) -> St = St0, ck_root_of(Y, S, Kind, R)
    ;   ck_is_local(Y) -> ck_anchor(St0, Y, St), Kind = borrow, R = Y
    ;   ck_is_global(Y) -> St = St0, Kind = borrow, R = Y
    ;   ck_fail(tie_unknown, Y, Form) ).
ck_root_of(_, borrow(R), borrow, R) :- !.
ck_root_of(_, dangling(R), dangling, R) :- !.
ck_root_of(Y, _, borrow, Y).
%% a field's tie: the sibling's key, anchored when it is a plain member
ck_field_tie_ref(St0, YK, St, Kind, R) :-
    (   ck_state(St0, YK, S) -> St = St0, ck_root_of(YK, S, Kind, R)
    ;   ck_declare(St0, YK, anchor, St), Kind = borrow, R = YK ).
%% an anchor for a plain local: a root in the frame where the local was
%% declared (the state's frames and the symbol table's are pushed together)
ck_anchor(St, Y, St1) :- ck_declare_at(St, Y, anchor, St1).
ck_declare_at(st(Frs), N, S, st(Frs1)) :- ccl_scope(SFs), ck_frame_index(SFs, N, 0, I), ck_insert_at(Frs, I, N-S, Frs1).
ck_frame_index([F|Fs], Y, I0, I) :- ( memberchk(Y-_, F) -> I = I0 ; I1 is I0 + 1, ck_frame_index(Fs, Y, I1, I) ).
ck_insert_at([fr(Os, Ds)|Frs], 0, P, [fr(Os1, Ds)|Frs]) :- !, append(Os, [P], Os1).
ck_insert_at([F|Frs], I, P, [F|Frs1]) :- I1 is I - 1, ck_insert_at(Frs, I1, P, Frs1).
%% `&x' of a plain local, `&x.f', `&a[i]' of a local array, a local array used
%% as a pointer: the local's storage is what is pointed to, so it is anchored
%% before the expression is read, and the pointer is a borrow of it
ck_anchor_addrs(E, St, St) :- \+ compound(E), !.
ck_anchor_addrs(addr(E), St0, St) :- !, ( ck_storage_base(E, N), \+ ck_is_ref(N) -> ck_anchor_local(N, St0, St1) ; St1 = St0 ), ck_anchor_addrs(E, St1, St).
ck_anchor_addrs(id(N), St0, St) :- !, ( ck_arrlocal(N), ck_local_type(N, T), ccl_resolve_type(T, arr(_, _)) -> ck_anchor_local(N, St0, St) ; St = St0 ).
%% the names declared with an array type in this function, so the walk over
%% every expression asks the scope only of those (every id cost a lookup and
%% a resolution: 7 ms of the B-tree's check); the scope still decides
ck_note_arrlocal(N, T) :- ( ccl_resolve_type(T, arr(_, _)) -> nb_getval('$ck_arrlocals', As), nb_setval('$ck_arrlocals', [N|As]) ; true ).
ck_note_arrparams([]).
ck_note_arrparams([P|Ps]) :- ( ( P = param(T, N) ; P = param(T, N, _) ), N \== anon -> ck_note_arrlocal(N, T) ; true ), ck_note_arrparams(Ps).
ck_arrlocal(N) :- nb_getval('$ck_arrlocals', As), memberchk(N, As).
ck_anchor_addrs(bin(_, A, B), St0, St) :- !, ck_anchor_addrs(A, St0, St1), ck_anchor_addrs(B, St1, St).      % the common shapes, without a univ
ck_anchor_addrs(index(A, I), St0, St) :- !, ck_anchor_addrs(A, St0, St1), ck_anchor_addrs(I, St1, St).
ck_anchor_addrs(arrow(E, _), St0, St) :- !, ck_anchor_addrs(E, St0, St).
ck_anchor_addrs(member(E, _), St0, St) :- !, ck_anchor_addrs(E, St0, St).
ck_anchor_addrs(assign(_, L, R), St0, St) :- !, ck_anchor_addrs(L, St0, St1), ck_anchor_addrs(R, St1, St).
ck_anchor_addrs(call(F, As), St0, St) :- !, ck_anchor_addrs(F, St0, St1), ck_anchor_addrs_list(As, St1, St).
ck_anchor_addrs(E, St0, St) :- E =.. [_|As], ck_anchor_addrs_list(As, St0, St).
ck_anchor_addrs_list([], St, St).
ck_anchor_addrs_list([A|As], St0, St) :- ck_anchor_addrs(A, St0, St1), ck_anchor_addrs_list(As, St1, St).
ck_anchor_local(N, St0, St) :- ( ck_state(St0, N, _) -> St = St0 ; ck_is_local(N) -> ck_anchor(St0, N, St) ; St = St0 ).
ck_storage_base(id(N), N).
ck_storage_base(member(E, _), N) :- ck_storage_base(E, N).
ck_storage_base(index(E, _), N) :- ccl_type_of(E, T), ccl_resolve_type(T, arr(_, _)), ck_storage_base(E, N).
%% the tie a variable declares for itself: an owner (or a struct by value with
%% own fields) keeps its state and the tie is noted; anything else becomes a
%% borrow of the root, whatever its type
ck_var_tie(N, T, St0, St) :-
    (   ccl_tie_of(T, Y)
    ->  ( Y == N -> ck_fail(tie_unknown, Y, tie(N, Y)) ; true ),
        ck_tie_ref(St0, Y, tie(N, Y), St1, Kind, R),
        (   ck_state(St1, N, S), ck_owner_state(S) -> St = St1
        ;   ck_own_under(St1, N, [_|_]) -> St = St1
        ;   Sn =.. [Kind, R], ( ck_state(St1, N, _) -> ck_set(St1, N, Sn, St) ; ck_declare(St1, N, Sn, St) ) ),
        ck_note_tie(N, R)
    ;   St = St0 ).
%% the tied fields of an instance: each an own field (the tie noted) or a
%% borrow of its sibling's root, declared in order
ck_field_ties(N, T, St0, St, Ts) :- ck_var_ties(N, T, Ts), ck_field_ties_(Ts, St0, St).
ck_field_ties_([], St, St).
ck_field_ties_([K-YK|Ts], St0, St) :-
    ck_field_tie_ref(St0, YK, St1, Kind, R),
    (   ck_state(St1, K, S), ck_owner_state(S) -> St2 = St1
    ;   ck_own_under(St1, K, [_|_]) -> St2 = St1
    ;   Sn =.. [Kind, R], ck_declare(St1, K, Sn, St2) ),
    ck_note_tie(K, R),
    ck_field_ties_(Ts, St2, St).
%% a tied owner consumed: nothing tied to it may still hold memory
ck_tied_consumed(St, K, Form) :- nb_getval('$ck_ties', Ts), ck_tied_consumed_(Ts, St, K, Form).
ck_tied_consumed_([], _, _, _).
ck_tied_consumed_([X-R|Ts], St, K, Form) :-
    ( X \== K, ck_within(St, R, K), ck_state(St, X, S), memberchk(S, [live, partial]) -> ck_fail(tie_outlived, X, Form) ; true ),
    ck_tied_consumed_(Ts, St, K, Form).
%% an owner moved: its tie, if any, must cover the slot it goes into
ck_tie_kept(St, P, Key, Form) :- ( ck_tied_to(P, T) -> ( Key \== none, ck_within(St, Key, T) -> true ; ck_fail(tie_escapes, P, Form) ) ; true ).
%% a value with no owner behind it, given to a variable that carries a pointer
%% without being one (a struct by value: the check cannot follow it)
ck_no_owner_behind(N, T, V, Form) :-
    (   ck_carries_type(T), \+ ck_is_pointer_type(T), \+ ck_declared_tie(N, _), ck_fresh_value(V) -> ck_fail(untied, N, Form)
    ;   true ).
ck_fresh_value(V) :- V \== none, V \= init(_), \+ ck_null(V), \+ ck_static_value(V).
%% a loose pointer's memory taken: by free, a return, a slot, an owner
ck_consume_loose(St0, P, St) :- ck_set(St0, P, none, St1), ck_dangle(St1, P, St).
ck_loose_taken(E, St0, St) :- ( ck_borrows_from(E, St0, P), ck_state(St0, P, loose) -> ck_set(St0, P, none, St) ; St = St0 ).
%% the borrows of a loose pointer, once an owner holds its memory, borrow the owner
ck_retarget(st(Frs), P, Key, st(Frs1)) :- ck_retarget_frames(Frs, P, Key, Frs1).
ck_retarget_frames([], _, _, []).
ck_retarget_frames([fr(Os, D)|T], P, K, [fr(Os1, D)|T1]) :- ck_retarget_owners(Os, P, K, Os1), ck_retarget_frames(T, P, K, T1).
ck_retarget_owners([], _, _, []).
ck_retarget_owners([N-borrow(P)|T], P, K, [N-borrow(K)|T1]) :- !, ck_retarget_owners(T, P, K, T1).
ck_retarget_owners([X|T], P, K, [X|T1]) :- ck_retarget_owners(T, P, K, T1).
%% a borrow of P bound to N: within N's tie when N has one, else a plain borrow
ck_bind_var(N, P, Form, St0, St) :-
    (   ck_declared_tie(N, R) -> ( ck_within(St0, R, P) -> true ; ck_fail(tie_mismatch, N, Form) ), ck_tied_state(St0, R, S), ck_set(St0, N, S, St)
    ;   ck_declare_borrow(St0, N, P, St) ).
%% the state of something tied to root R now: dangling when R is gone
ck_tied_state(St, R, S) :-
    (   ck_state(St, R, RS) -> ( memberchk(RS, [moved, partial]) -> S = dangling(R) ; RS = dangling(R1) -> S = dangling(R1) ; S = borrow(R) )
    ;   S = borrow(R) ).
%% what an expression borrows from: an owner named, a field, through arithmetic,
%% a cast, the address of an element or a member, another borrow
%% (an anchored plain variable's VALUE borrows nothing -- only its address does,
%% and a local array's value, which is its address)
ck_borrows_from(scoped(_, N), St, P) :- !, ck_borrows_from(id(N), St, P).        % C++ (M6): a qualified name is its bare name
ck_borrows_from(ccast(_, _, E), St, P) :- !, ck_borrows_from(E, St, P).
ck_borrows_from(id(N), St, P) :- ck_state(St, N, S), !, ( S == anchor -> ck_local_type(N, T), ccl_resolve_type(T, arr(_, _)), P = N ; ck_borrow_source(N, S, P) ).
ck_borrows_from(member(E, F), St, P) :- ck_path(member(E, F), K), ck_state(St, K, S), !, ck_borrow_source(K, S, P).
ck_borrows_from(arrow(E, F), St, P) :- ck_path(arrow(E, F), K), ck_state(St, K, S), !, ck_borrow_source(K, S, P).
ck_borrows_from(bin(Op, A, _), St, P) :- memberchk(Op, ['+', '-']), !, ck_borrows_from(A, St, P).
ck_borrows_from(cast(_, A), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(index(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(member(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(arrow(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(id(N)), St, P) :- ck_is_ref(N), !, ck_state(St, N, S), ck_borrow_source(N, S, P).   % C++: &x of a reference is the pointer held
ck_borrows_from(id(N), St, P) :- ck_is_ref(N), !, ck_local_type(N, ptr(_, RT)), ck_carries_type(RT), ck_state(St, N, S), ck_borrow_source(N, S, P).   % its value: what it refers to
ck_borrows_from(addr(id(N)), St, P) :- !, ck_state(St, N, S), ( S == anchor -> P = N ; ck_borrow_source(N, S, P) ).   % of an anchored local, an owner's slot
%% what a borrowed pointer reaches -- a member, an element, what it points to -- is borrowed from the same
ck_borrows_from(arrow(E, _), St, P) :- !, ck_borrows_from(E, St, P).
ck_borrows_from(member(E, _), St, P) :- !, ck_borrows_from(E, St, P).
ck_borrows_from(index(A, _), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(deref(E), St, P) :- !, ck_borrows_from(E, St, P).
ck_borrows_from(cond(_, A, B), St, P) :- !, ( ck_borrows_from(A, St, P) -> true ; ck_borrows_from(B, St, P) ).
ck_borrows_from(comma(_, B), St, P) :- !, ck_borrows_from(B, St, P).
ck_borrows_from(stmt_expr(block(Is)), St, P) :- append(_, [expr(_, E)], Is), !, ck_borrows_from(E, St, P).
%% a call whose result is tied to a parameter borrows from that argument (an
%% own result is an owner instead: fresh, checked against the tie where it lands)
ck_borrows_from(call(F, Args), St, P) :- ck_callee_sig(F, fn(R, _, _)), \+ ck_own_type(R), ck_call_tie(call(F, Args), St, P0), !, P = P0.
ck_call_tie(call(F, Args), St, P) :-
    ck_callee_sig(F, fn(R, Ps, _)), ccl_tie_of(R, Y),
    ( ck_param_index(Ps, Y, 1, I) -> ccl_nth(I, Args, A), ck_borrows_from(A, St, P) ; P = static(Y) ).
ck_param_index([param(_, Y)|_], Y, I, I) :- !.
ck_param_index([_|Ps], Y, I0, I) :- I1 is I0 + 1, ck_param_index(Ps, Y, I1, I).
ck_callee_sig(id(F), Sig) :- ccl_declared(F, T), !, ck_fn_sig(T, Sig).
ck_callee_sig(F, Sig) :- ccl_type_of(F, T), T \== unknown, ck_fn_sig(T, Sig).
ck_fn_sig(T, Sig) :- ccl_resolve_type(T, T1), ( T1 = fn(_, _, _) -> Sig = T1 ; T1 = ptr(_, FT), ccl_resolve_type(FT, Sig), Sig = fn(_, _, _) ).
ck_borrow_source(K, S, P) :- ( ck_owner_state(S) -> P = K ; memberchk(S, [anchor, loose, array]) -> P = K ; S = borrow(P) -> true ; S = dangling(P) ).
%% a return: a tied owner only within the result's tie; a borrow of a parameter
%% or a global may leave, and with a result tie only what lies within it
ck_no_escape(E, St) :-
    nb_getval('$ck_ret_tie', RT),
    (   nb_getval('$ck_ret', Ret), ck_ref_as_ptr(Ret, RP), RP \== Ret                 % C++: a reference result is a pointer out
    ->  (   E = id(N), ck_is_ref(N) -> ( ck_state(St, N, borrow(P)) -> ck_ret_borrow(St, P, RT, N, borrowed_from(P)) ; true )
        ;   ck_lvalue_form(E), ck_storage_base(E, B), ck_is_local(B), \+ ck_is_ref(B), nb_getval('$ck_params', Ps), \+ memberchk(B, Ps) -> ck_fail(borrow_escapes, B, reference_to_local(E))
        ;   true )
    ;   E = id(N), ck_is_ref(N) -> true                                                % a value out of the referent
    ;   ck_owner_path(St, E, K) -> ( ck_tied_to(K, R) -> ck_ret_tied(St, R, RT, K, E) ; true )
    ;   E = id(N), ck_state(St, N, dangling(P)) -> ck_fail(borrow_after_move, N, borrowed_from(P))
    ;   E = id(N), ck_state(St, N, borrow(P)) -> ( ck_local_type(N, T), ck_carries_type(T) -> ck_ret_borrow(St, P, RT, N, borrowed_from(P)) ; true )
    ;   ccl_type_of(E, T), ck_carries_type(T), ck_borrows_from(E, St, P) -> ck_ret_borrow(St, P, RT, P, E)
    ;   true ).
ck_ret_borrow(St, P, RT, N, Form) :-
    (   ck_state(St, P, loose) -> true                                  % the caller takes the memory over
    ;   P = static(_) -> true
    ;   RT \== none -> ( ck_within(St, RT, P) -> true ; ck_fail(tie_mismatch, N, Form) )
    ;   ( ck_is_param(P) ; ck_is_global(P) ) -> true
    ;   ck_fail(borrow_escapes, N, Form) ).
ck_ret_tied(St, R, RT, K, Form) :- ( RT \== none, ck_within(St, RT, R) -> true ; ck_fail(tie_escapes, K, Form) ).
ck_pop(st([_|Frs]), st(Frs)).
ck_defer(st([fr(Os, Ds)|Frs]), Body, st([fr(Os, [Body|Ds])|Frs])).

%% a join: the same owner in the same state on both sides keeps it; null beside
%% live is live (one path holds memory), null or unset beside moved is moved,
%% unset beside null is unset (garbage on one path); anything else is partial
ck_merge(dead, S, S) :- !.
ck_merge(S, dead, S) :- !.
ck_merge(st(A), st(B), st(C)) :- ck_merge_frames(A, B, C).
ck_merge_frames([], [], []).
ck_merge_frames([fr(Oa, D)|As], [fr(Ob, _)|Bs], [fr(Oc, D)|Cs]) :- ck_merge_owners(Oa, Ob, Oc), ck_merge_frames(As, Bs, Cs).
ck_merge_owners([], _, []).
ck_merge_owners([N-Sa|T], Ob, [N-Sc|T1]) :- ( memberchk(N-Sb, Ob) -> ck_merge_state(Sa, Sb, Sc) ; Sc = Sa ), ck_merge_owners(T, Ob, T1).
ck_merge_state(S, S, S) :- !.
ck_merge_state(dangling(P), _, dangling(P)) :- !.
ck_merge_state(_, dangling(P), dangling(P)) :- !.
ck_merge_state(borrow(P), borrow(_), borrow(P)) :- !.
ck_merge_state(loose, borrow(P), borrow(P)) :- !.                   % fresh memory on one path, a borrow on the other: the borrow is what can dangle
ck_merge_state(borrow(P), loose, borrow(P)) :- !.
ck_merge_state(none, S, S) :- !.                    % a plain pointer, bound on one side only: bound
ck_merge_state(S, none, S) :- !.
ck_merge_state(null, live, live) :- !.
ck_merge_state(live, null, live) :- !.
ck_merge_state(null, moved, moved) :- !.
ck_merge_state(moved, null, moved) :- !.
ck_merge_state(unset, moved, moved) :- !.
ck_merge_state(moved, unset, moved) :- !.
ck_merge_state(unset, null, unset) :- !.
ck_merge_state(null, unset, unset) :- !.
ck_merge_state(_, _, partial).

%% ---- statements: ck_stmt(+S, +St0, -St), St dead when the path ends here --------------
ck_stmt(_, dead, dead) :- !.
ck_stmt(block(Is), St0, St) :- !, ccl_scope_push, ck_push(St0, St1), ck_stmts(Is, St1, St2), ck_scope_end(St2, St), ccl_scope_pop.
ck_stmt('$splice'(Is), St0, St) :- !, ck_stmts(Is, St0, St).
ck_stmt(declaration(L, Sto, _, Vs), St0, St) :- !, ck_line(L), ( Sto == static -> ck_note_statics(Vs) ; true ), ck_decls(Vs, St0, St).
ck_stmt(typedef(_, _), St, St) :- !.
ck_stmt(declare(_, _), St, St) :- !.
ck_stmt(directive(_, _), St, St) :- !.
ck_stmt(include(_, _, _), St, St) :- !.
ck_stmt(static_assert(_, _, _), St, St) :- !.
ck_stmt(empty, St, St) :- !.
ck_stmt(expr(L, E), St0, St) :- !, ck_line(L), ck_anchor_addrs(E, St0, St1), ck_expr(E, St1, St).
ck_stmt(defer(L, _, Body), St0, St) :- !, ck_line(L), ck_defer(St0, Body, St).
ck_stmt(if(L, C, T, E), St0, St) :- !, ck_line(L),
    ck_expr(C, St0, St1), ck_refine(C, St1, StThen, StElse),
    ck_stmt(T, StThen, StT), ( E == none -> StE = StElse ; ck_stmt(E, StElse, StE) ), ck_merge(StT, StE, St).
%% a null test on an owner refines it: `if (!p)', `if (p == NULL)' make p null
%% on the then path, `if (p)', `if (p != NULL)' on the else path -- and its
%% own fields with it, there being nothing behind a null
ck_refine(C, St, StThen, StElse) :-
    (   ck_null_test(C, E, Sense) -> ( Sense == null -> ck_set_null(E, St, StThen), StElse = St ; StThen = St, ck_set_null(E, St, StElse) )
    ;   StThen = St, StElse = St ).
ck_null_test(not(E), E, null) :- !.
ck_null_test(bin('==', E, N), E, null) :- ck_null(N), !.
ck_null_test(bin('==', N, E), E, null) :- ck_null(N), !.
ck_null_test(bin('!=', E, N), E, live) :- ck_null(N), !.
ck_null_test(bin('!=', N, E), E, live) :- ck_null(N), !.
ck_null_test(E, E, live) :- ( E = id(_) ; E = member(_, _) ; E = arrow(_, _) ), !.
ck_set_null(E, St0, St) :-
    (   ck_path(E, K), ck_state(St0, K, S), memberchk(S, [live, partial]) -> ck_own_under(St0, K, Ks), ck_set_all(St0, [K|Ks], null, St)
    ;   St = St0 ).
ck_stmt(while(L, C, S), St0, St) :- !, ck_line(L), ck_expr(C, St0, St1), ck_loop(S, St1, St2), ck_expr(C, St2, St).
ck_stmt(do(L, S, C), St0, St) :- !, ck_line(L), ck_loop(S, St0, St1), ck_expr(C, St1, St).
ck_stmt(for_each(L, D, R, S), St0, St) :- !, ck_line(L),                        % C++: a range-for over an array is the for it stands for
    ( ccl_for_each_as_for(for_each(L, D, R, S), For) -> ck_stmt(For, St0, St) ; ck_fail(not_checked, range_for, for_each(L, D, R, S)) ).
ck_stmt(using(_, _), St, St) :- !.
ck_stmt(for(L, Init, C, Step, S), St0, St) :- !, ck_line(L),
    ccl_scope_push, ck_push(St0, St1),
    ( Init = decl(_, Vs) -> ck_decls(Vs, St1, St2) ; Init == none -> St2 = St1 ; ck_anchor_addrs(Init, St1, St1a), ck_expr(Init, St1a, St2) ),
    ( C == none -> St3 = St2 ; ck_expr(C, St2, St3) ),
    ck_loop_with_step(S, Step, St3, St4),
    ck_scope_end(St4, St), ccl_scope_pop.
ck_stmt(return(L), St0, dead) :- !, ck_line(L), ck_exit_all(St0, return).
ck_stmt(return(L, E), St0, dead) :- !, ck_line(L), ck_anchor_addrs(E, St0, St1), ck_no_escape(E, St1), ck_consume_or_use(E, St1, St2), ck_exit_all(St2, return(E)).
ck_stmt(break(L), St0, dead) :- !, ck_line(L), ck_exit_to_loop(St0, break).
ck_stmt(continue(L), St0, dead) :- !, ck_line(L), ck_exit_to_loop(St0, continue).
ck_stmt(goto(Ln, L), St, dead) :- !, ck_line(Ln), ( ck_any_owner(St) -> ck_fail(goto_with_owners, L, goto(L)) ; true ).
ck_stmt(label(_, _, S), St0, St) :- !, ck_stmt(S, St0, St).
ck_stmt(switch(L, E, S), St0, St) :- !, ck_line(L),
    ck_expr(E, St0, St1),
    ( S = block(Is) -> true ; Is = [S] ),
    ccl_scope_push, ck_push(St1, St2), ck_loop_enter(St2, switch), ck_switch_items(Is, St2, St2, St3), ck_loop_leave(Brk),
    ck_merge_all([St3|Brk], St4), ( ck_has_default(Is) -> St5 = St4 ; ck_merge(St4, St2, St5) ),
    ck_scope_end(St5, St), ccl_scope_pop.
ck_stmt(case(_, _, S), St0, St) :- !, ck_stmt(S, St0, St).
ck_stmt(default(_, S), St0, St) :- !, ck_stmt(S, St0, St).
ck_stmt(S, _, _) :- functor(S, F, _), nb_getval('$ck_fn', Fn), nb_getval('$ck_line', L), throw(error(not_lowered(F), where(Fn, line(L)))).   % a form of C++'s later steps
ck_stmts([], St, St).
ck_stmts([S|Ss], St0, St) :- ck_stmt(S, St0, St1), ck_stmts(Ss, St1, St).

ck_switch_items([], _, St, St).
ck_switch_items([case(_, E, S)|Is], Entry, St0, St) :- !, ck_merge(St0, Entry, St1), ck_switch_items([S|Is], Entry, St1, St).
ck_switch_items([default(_, S)|Is], Entry, St0, St) :- !, ck_merge(St0, Entry, St1), ck_switch_items([S|Is], Entry, St1, St).
ck_switch_items([S|Is], Entry, St0, St) :- ck_stmt(S, St0, St1), ck_switch_items(Is, Entry, St1, St).
ck_has_default(Is) :- member(default(_, _), Is), !.
ck_has_default(Is) :- member(case(_, _, S), Is), ck_has_default([S]), !.

%% ---- declarations -----------------------------------------------------------------------
%% every local joins the symbol table (the types of paths come from it); an own
%% pointer is an owner from here, unset until given something, its own fields
%% unset too; a struct by value with own fields owns them; the tied fields are
%% declared with them; then the variable's own tie; a plain pointer given an
%% owner's value is a borrow, given a value with no owner behind it a warning
ck_decls([], St, St).
ck_decls([var(N, T0, Init0)|Vs], St0, St) :-
    ck_ref_decl(N, T0, Init0, T, Init),
    ccl_declare(N, T), ck_note_arrlocal(N, T), ck_type_rules(N, T, var(N, Init)),
    ck_var_fields(N, T, Fs), ck_states(Fs, unset, FOs),
    ck_declare_all(St0, FOs, St1), ck_field_ties(N, T, St1, St2, Ts), ck_anchor_addrs(Init, St2, St3),
    (   ck_own_array_type(T)
    ->  ck_note_array(N),
        ( Init = init(Items) -> ck_declare(St3, N, array, St5), ck_init_slots(Items, T, N, St5, St6) ; ck_fail(array_unset, N, var(N, Init)) )
    ;   ck_own_type(T), ck_is_pointer_type(T)
    ->  ck_declare(St3, N, unset, St4), ck_var_tie(N, T, St4, St5),
        ( Init == none -> St6 = St5 ; ck_into_own(N, Init, var(N, Init), St5, St6, _) )
    ;   ( Fs \== [] ; Ts \== [] )
    ->  ck_var_tie(N, T, St3, St5), ( Init == none -> St6 = St5 ; ck_fill(N, T, Init, var(N, Init), St5, St6) )
    ;   ck_var_tie(N, T, St3, St5),
        (   Init == none -> St6 = St5
        ;   Init = init(Items) -> ck_init_slots(Items, T, N, St5, St6)
        ;   ck_expr(Init, St5, St5a),
            (   ck_carries_type(T), ck_borrows_from(Init, St5a, P) -> ck_bind_var(N, P, var(N, Init), St5a, St6)
            ;   ck_is_pointer_type(T), \+ ck_declared_tie(N, _), ck_fresh_value(Init) -> ck_declare(St5a, N, loose, St6)
            ;   ck_no_owner_behind(N, T, Init, var(N, Init)), St6 = St5a ) ) ),
    ck_decls(Vs, St6, St).

%% what a right-hand side is to a slot: an owner (moved in), a null, a borrow, or a fresh value
ck_kind(E, _, null) :- ck_null(E), !.
ck_kind(move(E), _, fresh) :- ck_own_elem(E, _), !.                  % an element moved out: an owner, complete
ck_kind(move(E), St, K) :- ck_path(E, P), ck_by_value(E), ck_own_under(St, P, Fs), Fs \== [], !, ck_kind(E, St, K).   % a struct with owners moved whole: the value's kind, the fields going in ck_expr
ck_kind(move(E), St, K) :- !, ( ck_owner_path(St, E, P) -> K = owner(P) ; ck_name(E, N), ck_fail(move_of_non_owner, N, move(E)) ).
ck_name(E, N) :- ( ck_path(E, N) -> true ; N = E ).
ck_kind(E, St, owner(P)) :- ck_owner_path(St, E, P), !.
ck_kind(E, St, borrow(P)) :- ck_borrows_from(E, St, P), !.
ck_kind(_, _, fresh).

%% an own slot -- an owner, an own field (Key), or an untracked own place (none) --
%% receives a value: an owner is consumed into it and its own fields come along
%% (a tied owner only into a slot within its tie), a null makes it null, a
%% fresh value makes it live (an own result tied to an argument, the same
%% rule), a borrow is refused
ck_into_own(Key, R, Form, St0, St, Kind) :-
    ck_kind(R, St0, Kind),
    (   Kind = owner(P) -> ck_strip_move(R, E), ck_base_use(E, St0, St1), ck_tie_kept(St1, P, Key, Form), ck_under_states(St1, P, Src), ck_consume(P, move, Form, St1, St2, Prior), New = Prior, ck_transfer(St2, Src, P, Key, St3a), ck_complete_rest(St3a, Key, Prior, St3)
    ;   Kind = null -> ck_expr(R, St0, St3), New = null
    ;   Kind = borrow(P) -> ( ck_state(St0, P, loose) -> ck_expr(R, St0, St3a), ck_set(St3a, P, none, St3b), ( Key == none -> St3 = St3b ; ck_retarget(St3b, P, Key, St3) ), New = live   % the owner takes loose memory over
                              ; ck_fail(borrow_stored, P, Form) )
    ;   ck_strip_move(R, E), ( ck_call_tie(E, St0, PR) -> ( Key \== none, ck_within(St0, Key, PR) -> true ; ck_fail(tie_escapes, Key, Form) ) ; true ),
        ck_expr(R, St0, St3a), New = live,
        ( Key == none -> St3 = St3a ; ck_alloc_mode(E, Mode), ck_set_fields(St3a, Key, Mode, Form, St3) ) ),   % its fields: complete, zeroed, or garbage
    (   Key == none -> St = St3
    ;   ck_state(St3, Key, Cur) -> ( Cur == live -> ck_fail(owner_overwritten, Key, Form) ; ck_set(St3, Key, New, St) )
    ;   St = St3 ).
%% a plain slot (named, for the warning) receives a value: an owner's pointer
%% or a borrow may not be stored there -- but the address of a plain local (a
%% borrow of its anchor) may, as C has always had it: nothing consumes an
%% anchor; a fresh value that is not static has no owner behind it, a warning
ck_into_plain(Name, R, Form, St0, St) :-
    ck_kind(R, St0, Kind),
    (   Kind = owner(P) -> ck_fail(owner_stored, P, Form)
    ;   Kind = borrow(P) -> (   ck_state(St0, P, anchor) -> ck_expr(R, St0, St)
                            ;   P = static(_) -> ck_expr(R, St0, St)
                            ;   ck_state(St0, P, loose) -> ck_fail(untied, Name, Form)             % stored, still nobody's
                            ;   ck_fail(borrow_stored, P, Form) )
    ;   Kind == null -> ck_expr(R, St0, St)
    ;   ( ck_static_value(R) -> true ; ck_fail(untied, Name, Form) ), ck_expr(R, St0, St) ).
%% a slot's name for a diagnostic: a path, `*p', `a[]', else the expression
ck_slot_name(E, N) :- ck_path(E, N), !.
ck_slot_name(deref(E), N) :- ck_slot_name(E, N0), atom(N0), !, atom_concat('*', N0, N).
ck_slot_name(index(E, _), N) :- ck_slot_name(E, N0), atom(N0), !, atom_concat(N0, '[]', N).
ck_slot_name(E, E).
%% a tied slot (Key, tied to Root) receives a value: a borrow of something
%% within the root, a null, a fresh value; an owner's pointer is refused as
%% for any plain slot; the slot is a borrow of the root from here
ck_into_tied(Key, Root, R, Form, St0, St) :-
    (   R = move(_) -> ck_fail(owner_stored, Key, Form)
    ;   ck_borrows_from(R, St0, P) -> ( ck_within(St0, Root, P) -> true ; ck_fail(tie_mismatch, Key, Form) )
    ;   true ),
    ck_expr(R, St0, St1), ck_loose_taken(R, St1, St2), ck_tied_state(St2, Root, S), ck_set_if(St2, Key, S, St).
%% the fields the source did not cover -- an own FIELD's pointee is not opened,
%% so it has none -- are complete, as the source was when it moved
ck_complete_rest(St, none, _, St) :- !.
ck_complete_rest(St0, Key, Prior, St) :- ck_under_states(St0, Key, Ps), ( Prior == null -> S = null ; S = live ), ck_complete_unset(Ps, S, St0, St).
ck_complete_unset([], _, St, St).
ck_complete_unset([K-KS|Ps], S, St0, St) :- ( KS == unset -> ( ck_is_array_key(K) -> ck_set(St0, K, array, St1) ; ck_set(St0, K, S, St1) ) ; St1 = St0 ), ck_complete_unset(Ps, S, St1, St).
%% the fields of an owner moved into another owner: the same states, under the
%% new base; a field's borrow of a sibling is re-rooted to the sibling's copy
ck_transfer(St, _, _, none, St) :- !.
ck_transfer(St, [], _, _, St) :- !.
ck_transfer(St0, [SK-SS|Ps], P, Key, St) :-
    ( atom_concat(P, Suffix, SK), ( atom_concat(Key, Suffix, TK) ) -> ck_reroot(SS, P, Key, SS1), ck_set_if(St0, TK, SS1, St1) ; St1 = St0 ),
    ck_transfer(St1, Ps, P, Key, St).
ck_reroot(borrow(R0), P, Key, borrow(R)) :- ck_under_root(R0, P, Key, R), !.
ck_reroot(dangling(R0), P, Key, dangling(R)) :- ck_under_root(R0, P, Key, R), !.
ck_reroot(S, _, _, S).
ck_under_root(R0, P, Key, R) :- atom_concat(P, Sfx, R0), ( sub_atom(Sfx, 0, 1, _, '.') ; sub_atom(Sfx, 0, 2, _, '->') ), !, atom_concat(Key, Sfx, R).
%% a struct by value with own fields receives a whole value: from another such
%% struct its fields move over; from an initializer list, item by item; from a
%% call or anything else, fresh: every own field live
ck_fill(Key, T, R, Form, St0, St) :-
    ck_no_array_copy(St0, Key, Form),
    (   R = init(Items) -> ck_init_slots(Items, T, Key, St0, St)
    ;   R = compound_lit(_, init(Items)) -> ck_init_slots(Items, T, Key, St0, St)
    ;   ck_path(R, P), ck_under_states(St0, P, Src), Src \== [] -> ck_expr(R, St0, St1), ck_move_fields(St1, Src, P, Key, Form, St)
    ;   ck_expr(R, St0, St1), ck_own_under(St1, Key, Ks), ck_set_live(St1, Ks, Form, St) ).
ck_set_live(St, [], _, St).
ck_set_live(St0, [K|Ks], Form, St) :- ( ck_state(St0, K, live) -> ck_fail(owner_overwritten, K, Form) ; ck_set(St0, K, live, St1) ), ck_set_live(St1, Ks, Form, St).
ck_move_fields(St, [], _, _, _, St).
ck_move_fields(St0, [SK-SS|Ps], P, Key, Form, St) :- \+ ck_owner_state(SS), !,          % a tied field, an anchor: copied, re-rooted
    atom_concat(P, Suffix, SK), atom_concat(Key, Suffix, TK), ck_reroot(SS, P, Key, SS1), ck_set_if(St0, TK, SS1, St1),
    ck_move_fields(St1, Ps, P, Key, Form, St).
ck_move_fields(St0, [SK-SS|Ps], P, Key, Form, St) :-
    ( SS == live -> New = live ; SS == null -> New = null ; SS == unset -> ck_fail(owner_unset, SK, Form) ; ck_fail(use_after_move, SK, Form) ),
    atom_concat(P, Suffix, SK), atom_concat(Key, Suffix, TK),
    ck_set(St0, SK, moved, St1), ck_dangle(St1, SK, St2),
    ( ck_state(St2, TK, live) -> ck_fail(owner_overwritten, TK, Form) ; ck_set_if(St2, TK, New, St3) ),
    ck_move_fields(St3, Ps, P, Key, Form, St).

%% an initializer list against its type: every slot is own, tied, or plain;
%% under a base (a variable's key) an own or tied slot is that field
ck_init_slots(Items, T, Base, St0, St) :- ccl_resolve_type(T, T1), ck_init_slots_(Items, T1, Base, 0, St0, St).
ck_init_slots_([], _, _, _, St, St).
ck_init_slots_([item(Ds, V)|Is], T, Base, I, St0, St) :-
    ck_slot(T, Ds, I, SlotT, F, I1),
    ( ( Base == none ; F == none ) -> Key = none ; atomic_list_concat([Base, '.', F], Key) ),
    ck_slot_label(Base, F, Key, Name),
    ck_init_slot(V, SlotT, Key, Name, St0, St1),
    ck_init_slots_(Is, T, Base, I1, St1, St).
ck_slot_label(_, _, Key, Key) :- Key \== none, !.
ck_slot_label(Base, none, _, Name) :- Base \== none, !, atom_concat(Base, '[]', Name).
ck_slot_label(_, F, _, F) :- F \== none, !.
ck_slot_label(_, _, _, element).
ck_slot(T, [field(F)|_], _, MT, F, I1) :- ccl_members_of(T, Ms), ck_member_at(Ms, F, 0, MT, Idx), !, I1 is Idx + 1.
ck_slot(arr(_, ET), [at(int(K))|_], _, ET, none, I1) :- !, I1 is K + 1.
ck_slot(arr(_, ET), [], I, ET, none, I1) :- !, I1 is I + 1.
ck_slot(T, [], I, MT, F, I1) :- ccl_members_of(T, Ms), I0 is I + 1, ccl_nth(I0, Ms, member(MT, F, _)), !, I1 is I + 1.
ck_slot(_, _, I, unknown, none, I1) :- I1 is I + 1.
ck_member_at([member(MT, F, _)|_], F, I, MT, I) :- !.
ck_member_at([_|Ms], F, I0, MT, I) :- I1 is I0 + 1, ck_member_at(Ms, F, I1, MT, I).
ck_init_slot(init(Sub), SlotT, Key, _, St0, St) :- !, ck_init_slots(Sub, SlotT, Key, St0, St).
ck_init_slot(V, SlotT, Key, Name, St0, St) :-
    (   SlotT \== unknown, ck_own_type(SlotT) -> ck_into_own(Key, V, init(V), St0, St, _)
    ;   Key \== none, ck_tied_to(Key, Root) -> ck_into_tied(Key, Root, V, init(V), St0, St)
    ;   SlotT \== unknown, ck_carries_type(SlotT) -> ck_into_plain(Name, V, init(V), St0, St)
    ;   ck_expr(V, St0, St) ).

%% ---- loops: a body may not consume an owner from outside, unless it re-owns it ------------
ck_loop(S, St0, St) :- ck_loop_with_step(S, none, St0, St).
ck_loop_with_step(S, Step, St0, St) :-
    ck_loop_enter(St0, loop),
    ck_stmt(S, St0, St1),
    ck_loop_leave(Exits), ck_continues(Conts),
    ck_merge_all([St1|Conts], StEnd),
    ( Step == none -> StEnd1 = StEnd ; StEnd == dead -> StEnd1 = dead ; ck_expr(Step, StEnd, StEnd1) ),
    ck_no_moves_across(St0, StEnd1, S),
    ck_merge_all([St0, StEnd1|Exits], St).
ck_loop_enter(St, Kind) :- nb_getval('$ck_loops', L), nb_setval('$ck_loops', [lp(Kind, St, [], [])|L]).
ck_loop_leave(Exits) :- nb_getval('$ck_loops', [lp(_, _, Exits, _)|L]), nb_setval('$ck_loops', L).
ck_continues(Cs) :- nb_getval('$ck_loops', L), ( L = [] -> Cs = [] ; Cs = [] ).   % continues were merged when leaving
ck_no_moves_across(_, dead, _) :- !.
ck_no_moves_across(st(Before), st(After), S) :- ck_frames_kept(Before, After, S).
ck_frames_kept([], _, _).
ck_frames_kept([fr(Ob, _)|Bs], [fr(Oa, _)|As], S) :-
    ( member(N-live, Ob), memberchk(N-SA, Oa), SA \== live -> ck_fail(move_in_loop, N, S) ; true ),
    ck_frames_kept(Bs, As, S).
%% a break or continue: its state joins the loop's exits (or the switch's), the frames inside the loop closed first
ck_exit_to_loop(St0, Kind) :-
    nb_getval('$ck_loops', [lp(LKind, StIn, Exits, Conts)|L]),
    st(FrsIn) = StIn, length(FrsIn, Depth), ck_close_to(St0, Depth, St1),
    ( Kind == continue, LKind == switch -> nb_setval('$ck_loops', [lp(LKind, StIn, Exits, Conts)|L]), ck_exit_to_loop_outer(St1, L, continue)
    ; Kind == continue -> nb_setval('$ck_loops', [lp(LKind, StIn, [St1|Exits], Conts)|L])   % a continue rejoins the head: checked as an exit too
    ; nb_setval('$ck_loops', [lp(LKind, StIn, [St1|Exits], Conts)|L]) ).
ck_exit_to_loop_outer(St1, [lp(K, StIn, Exits, Conts)|L], Kind) :- !, nb_setval('$ck_loops', [lp(K, StIn, [St1|Exits], Conts)|L]), true.
ck_exit_to_loop_outer(_, [], _) :- ck_fail(not_checked, continue, continue).
%% close the frames opened inside the loop: their defers run, their owners must be consumed
ck_close_to(St, Depth, St) :- st(Frs) = St, length(Frs, Depth), !.
ck_close_to(St0, Depth, St) :- ck_scope_end(St0, St1), ck_close_to(St1, Depth, St).

%% ---- scope ends and returns -----------------------------------------------------------------
%% the frame's defers run, last first; then its owners must be consumed; then
%% whatever borrowed one of its keys -- an anchor, an owner -- dangles
ck_scope_end(dead, dead) :- !.
ck_scope_end(st([fr(Os, Ds)|Frs]), St) :-
    ck_run_defers(Ds, st([fr(Os, [])|Frs]), St1),
    ( St1 == dead -> St = dead ; st([fr(Os1, _)|Frs1]) = St1, ck_leaks(Os1, scope_end), ck_keys(Os1, Ks), ck_dangle_all(st(Frs1), Ks, St) ).
ck_run_defers([], St, St).
ck_run_defers([B|Bs], St0, St) :- ck_stmt(B, St0, St1), ck_run_defers(Bs, St1, St).
%% a return: every frame's defers run, innermost first, then no owner may be live
ck_exit_all(St0, Form) :- ck_exit_frames(St0, Form).
ck_exit_frames(dead, _) :- !.
ck_exit_frames(st([]), _) :- !.
ck_exit_frames(st([fr(Os, Ds)|Frs]), Form) :-
    ck_run_defers(Ds, st([fr(Os, [])|Frs]), St1),
    (   St1 == dead -> true
    ;   st([fr(Os1, _)|Frs1]) = St1, ( Frs1 == [] -> ck_complete_owners(Os1, Form) ; true ),
        ck_leaks(Os1, Form), ck_exit_frames(st(Frs1), Form) ).
ck_leaks_all(st(Frs), Form) :- ck_leaks_frames(Frs, Form).
ck_leaks_frames([], _).
ck_leaks_frames([fr(Os, _)|Frs], Form) :- ck_leaks(Os, Form), ck_leaks_frames(Frs, Form).
ck_leaks([], _).
ck_leaks([N-S|Os], Form) :-
    (   S == loose -> ck_fail(unconsumed, N, Form)
    ;   ( memberchk(S, [moved, unset, null, none, anchor, array]) ; S = borrow(_) ; S = dangling(_) ; ck_is_borrowed_field(N) ) -> true
    ;   ck_fail(owner_leaked, N, Form) ),
    ck_leaks(Os, Form).
ck_any_owner(st(Frs)) :- member(fr(Os, _), Frs), member(_-S, Os), ck_owner_state(S), !.
ck_merge_all([S], S) :- !.
ck_merge_all([A, B|T], S) :- ck_merge(A, B, C), ck_merge_all([C|T], S).

%% ---- expressions --------------------------------------------------------------------------------
%% a value that is consumed if it is an owner or a struct with own fields (a return), else used
ck_consume_or_use(E, St0, St) :- ck_owner_path(St0, E, K), ck_is_borrowed_field(K), nb_getval('$ck_ret', Ret), \+ ck_own_type(Ret), !,   % a parameter's own field returned as a plain pointer: a borrow out, the caller's still (c_str)
    ck_base_use(E, St0, St).
ck_consume_or_use(E, St0, St) :- ck_owner_path(St0, E, K), !, ck_base_use(E, St0, St1), ck_consume(K, move, E, St1, St, _).
ck_consume_or_use(move(E), St0, St) :- !, ck_expr(move(E), St0, St).
ck_consume_or_use(E, St0, St) :- ck_path(E, K), ck_by_value(E), ck_has_array_under(St0, K), !, ck_fail(own_array_by_value, K, E).
ck_consume_or_use(E, St0, St) :- ck_path(E, K), ck_by_value(E), ck_own_under(St0, K, Fs), Fs \== [], !, ck_expr(E, St0, St1), ck_move_out(St1, Fs, E, St).
%% a struct held by value, not a pointer to one (whose own fields are the struct's, not the pointer's to move)
ck_by_value(E) :- ccl_type_of(E, T), T \== unknown, \+ ck_is_pointer_type(T).
ck_consume_or_use(E, St0, St) :- ck_expr(E, St0, St1), ck_loose_taken(E, St1, St).
%% consuming an owner, by free (fclose) or by move: it must be live or null; its
%% own fields must be consumed already when it is freed, complete when it is
%% moved; nothing tied to it may still hold memory; then it and they are moved,
%% and their borrows dangle
ck_consume(K, How, Form, St0, St, Prior) :-
    ck_state(St0, K, Prior),
    ( Prior == live -> true ; Prior == null -> true ; Prior == unset -> ck_fail(owner_unset, K, Form) ; ck_fail(use_after_move, K, Form) ),
    ck_own_under(St0, K, Fs),
    ( Prior == null -> true ; ck_fields_consumable(Fs, How, St0, Form) ),
    ck_tied_consumed(St0, K, Form),
    ck_set(St0, K, moved, St1), ck_set_all(St1, Fs, moved, St2),
    ck_under(St2, K, All), ck_dangle_all(St2, [K|All], St).
ck_fields_consumable([], _, _, _).
ck_fields_consumable([F|Fs], How, St, Form) :-
    ck_state(St, F, S),
    (   How == free -> ( memberchk(S, [moved, unset, null]) -> true ; ck_fail(owner_leaked, F, Form) )
    ;   memberchk(S, [live, null]) -> true
    ;   S == unset -> ck_fail(owner_unset, F, Form)
    ;   ck_fail(use_after_move, F, Form) ),
    ck_fields_consumable(Fs, How, St, Form).
%% a struct by value moved out (returned, passed to an own parameter): its fields go, complete
ck_move_out(St0, Fs, Form, St) :- ck_fields_consumable(Fs, move, St0, Form), ck_set_all(St0, Fs, moved, St1), ck_dangle_all(St1, Fs, St).
%% the borrows of a consumed owner dangle, in every frame
ck_dangle_all(St, [], St).
ck_dangle_all(St0, [K|Ks], St) :- ck_dangle(St0, K, St1), ck_dangle_all(St1, Ks, St).
ck_dangle(st(Frs), P, st(Frs1)) :- ck_dangle_frames(Frs, P, Frs1).
ck_dangle_frames([], _, []).
ck_dangle_frames([fr(Os, D)|T], P, [fr(Os1, D)|T1]) :- ck_dangle_owners(Os, P, Os1), ck_dangle_frames(T, P, T1).
ck_dangle_owners([], _, []).
ck_dangle_owners([N-borrow(P)|T], P, [N-dangling(P)|T1]) :- !, ck_dangle_owners(T, P, T1).
ck_dangle_owners([X|T], P, [X|T1]) :- ck_dangle_owners(T, P, T1).
%% a read of an owner, a field, a borrow, an anchor
ck_read(K, S) :- ( memberchk(S, [live, null, none, anchor, loose, array]) -> true ; S = borrow(_) -> true ; S = dangling(P) -> ck_fail(borrow_after_move, K, borrowed_from(P)) ; S == unset -> ck_fail(owner_unset, K, id(K)) ; ck_fail(use_after_move, K, id(K)) ).

%% the walk's clauses are ordered by what a node is most often (counted on
%% the B-tree: a third are names, then members, operators, literals), and a
%% node no clause below cares for is walked without a univ: an operator or a
%% number was tried against every head before the last clause took it, a
%% `x->f' that is no owner's key computed its path, looked it up, then went
%% the generic way with its field name as a child
ck_expr(_, dead, dead) :- !.
ck_expr(E, St, St) :- \+ compound(E), !.                                          % an operator, a number, a name as a field
ck_expr(id(N), St, St) :- !, ( ck_state(St, N, S) -> ck_read(N, S) ; true ).
ck_expr(int(_), St, St) :- !.
ck_expr(float(_), St, St) :- !.
ck_expr(chr(_), St, St) :- !.
ck_expr(str(_), St, St) :- !.
ck_expr(member(E, F), St0, St) :- ck_path(member(E, F), K), ck_state(St0, K, S), !, ck_expr(E, St0, St), ck_read(K, S).
ck_expr(member(E, _), St0, St) :- !, ck_expr(E, St0, St).
ck_expr(arrow(E, F), St0, St) :- ck_path(arrow(E, F), K), ck_state(St0, K, S), !, ck_expr(E, St0, St), ck_read(K, S).
ck_expr(arrow(E, _), St0, St) :- !, ck_expr(E, St0, St).
ck_expr(index(A, I), St0, St) :- !, ck_expr(A, St0, St1), ck_expr(I, St1, St).
ck_expr(bin(Op, A, B), St0, St) :- Op \== '&&', Op \== '||', !, ck_expr(A, St0, St1), ck_expr(B, St1, St).
ck_expr(E, St0, St) :- ck_unary_shape(E, A), !, ck_expr(A, St0, St).           % a wrapper around one expression: its child
ck_unary_shape(neg(E), E). ck_unary_shape(not(E), E). ck_unary_shape(bitnot(E), E). ck_unary_shape(pos(E), E).
ck_unary_shape(deref(E), E). ck_unary_shape(cast(_, E), E). ck_unary_shape(postinc(E), E). ck_unary_shape(postdec(E), E).
ck_unary_shape(preinc(E), E). ck_unary_shape(predec(E), E).
ck_expr(move(E), St0, St) :- ck_own_elem(E, K), !, ck_expr(E, St0, St1), ck_dangle(St1, K, St).   % an element out: the array's borrows dangle
ck_expr(move(E), St0, St) :- ck_path(E, K), ck_by_value(E), ck_own_under(St0, K, Fs), Fs \== [], !, ck_expr(E, St0, St1), ck_move_out(St1, Fs, move(E), St).   % a struct with owners moved whole: its fields go
ck_expr(move(E), St0, St) :- !, ( ck_owner_path(St0, E, K) -> ck_base_use(E, St0, St1), ck_consume(K, move, move(E), St1, St, _) ; ck_name(E, N), ck_fail(move_of_non_owner, N, move(E)) ).
ck_expr(scoped(_, N), St0, St) :- !, ck_expr(id(N), St0, St).                  % C++ (M6)
ck_expr(ccast(_, _, E), St0, St) :- !, ck_expr(E, St0, St).
ck_expr(new(_, Args), St0, St) :- !, ck_exprs(Args, St0, St).
ck_expr(new_array(_, N), St0, St) :- !, ck_expr(N, St0, St).
ck_expr(delete(E), St0, St) :- !, ck_expr(call(id(free), [E]), St0, St).
ck_expr(delete_array(E), St0, St) :- !, ck_expr(call(id(free), [E]), St0, St).
ck_expr(call(id(F), Args), St0, St) :- !, ck_args(Args, id(F), St0, St).
ck_expr(call(F, Args), St0, St) :- !,
    ck_expr(F, St0, St1),
    ( ccl_type_of(F, FT), ck_fn_params(FT, Ps) -> ck_args(Args, params(Ps), St1, St) ; ck_exprs(Args, St1, St) ).
%% the parameters of a function type, or of a pointer to one
ck_fn_params(T, Ps) :- ccl_resolve_type(T, T1), ( T1 = fn(_, Ps, _) -> true ; T1 = ptr(_, FT), ccl_resolve_type(FT, fn(_, Ps, _)) ).
%% assignment: to an owner or an own field; to a struct by value with own fields;
%% to a tied slot; to a local plain pointer (a borrow, or not); to any other
%% place, by its type
ck_expr(assign(Op, id(N), R), St0, St) :- ck_is_ref(N), !, ck_expr(assign(Op, deref(id(N)), R), St0, St).   % C++: through the reference
ck_expr(assign('=', L, R), St0, St) :- ck_owner_path(St0, L, K), !,
    ck_base_use(L, St0, St1), ck_into_own(K, R, assign('=', L, R), St1, St, _).
ck_expr(assign('=', L, R), St0, St) :- ck_path(L, K), ck_by_value(L), ck_own_under(St0, K, [_|_]), !,
    ck_base_use(L, St0, St1), ( ccl_type_of(L, T) -> true ; T = unknown ), ck_fill(K, T, R, assign('=', L, R), St1, St).
ck_expr(assign('=', L, R), St0, St) :- ck_path(L, K), ck_tied_to(K, Root), !,
    ck_base_use(L, St0, St1), ck_into_tied(K, Root, R, assign('=', L, R), St1, St).
ck_expr(assign('=', L, R), St0, St) :- ck_own_elem(L, K), !,                 % an element: an own slot; the old one freed by the lowering
    ck_lval_use(L, St0, St1), ck_into_own(none, R, assign('=', L, R), St1, St2, _), ck_dangle(St2, K, St).
ck_expr(assign('=', id(N), R), St0, St) :- ( ck_state(St0, N, _) ; ck_is_local(N) ), !,
    ck_expr(R, St0, St1),
    (   ck_is_param(N), ck_state(St1, N, borrow(N)) -> ck_rebind(St1, N, none, St2)   % a parameter re-assigned is a plain local from here
    ;   St2 = St1 ),
    ( ck_local_type(N, T) -> true ; T = unknown ),
    ( ck_state(St2, N, loose) -> ck_fail(unconsumed, N, assign('=', id(N), R)) ; true ),      % overwritten, its memory still nobody's
    (   T \== unknown, ck_carries_type(T), ck_borrows_from(R, St1, P) -> ck_rebind(St2, N, borrow(P), St)   % read before the parameter was unbound
    ;   T \== unknown, ck_is_pointer_type(T), ck_fresh_value(R) -> ck_rebind(St2, N, loose, St)
    ;   ck_state(St2, N, S), ( S = borrow(_) ; S = dangling(_) ; S == loose ) -> ck_rebind(St2, N, none, St), ( T \== unknown -> ck_no_owner_behind(N, T, R, assign('=', id(N), R)) ; true )
    ;   T \== unknown, \+ ck_state(St2, N, _) -> ck_no_owner_behind(N, T, R, assign('=', id(N), R)), St = St2
    ;   St = St2 ).
ck_expr(assign('=', L, R), St0, St) :- !,
    ck_lval_use(L, St0, St1),
    ( ck_path(R, RK), ck_by_value(R), ck_has_array_under(St1, RK) -> ck_fail(own_array_by_value, RK, assign('=', L, R)) ; true ),
    (   ccl_type_of(L, T), T \== unknown
    ->  (   ck_own_type(T) -> ck_into_own(none, R, assign('=', L, R), St1, St, _)
        ;   ck_carries_type(T) -> ck_slot_name(L, Name), ck_into_plain(Name, R, assign('=', L, R), St1, St)
        ;   ck_expr(R, St1, St) )
    ;   ck_expr(R, St1, St) ).
ck_expr(assign(_, L, R), St0, St) :- !, ck_expr(R, St0, St1), ck_lval_use(L, St1, St).
ck_expr(sizeof(_), St, St) :- !.
ck_expr(sizeof_type(_), St, St) :- !.
ck_expr(cond(C, A, B), St0, St) :- !, ck_expr(C, St0, St1), ck_expr(A, St1, StA), ck_expr(B, St1, StB), ck_merge(StA, StB, St).
ck_expr(bin('&&', A, B), St0, St) :- !, ck_expr(A, St0, St1), ck_expr(B, St1, St2), ck_merge(St1, St2, St).
ck_expr(bin('||', A, B), St0, St) :- !, ck_expr(A, St0, St1), ck_expr(B, St1, St2), ck_merge(St1, St2, St).
%% a statement expression: its last expression is its value, consumed when it
%% is an owner (clone's fresh copy leaves this way), else used
ck_expr(stmt_expr(block(Is)), St0, St) :- append(Init, [expr(L, E)], Is), !,
    ccl_scope_push, ck_push(St0, St1), ck_stmts(Init, St1, St2), ck_line(L),
    ( St2 == dead -> St3 = dead ; ck_anchor_addrs(E, St2, St2a), ck_consume_or_use(E, St2a, St3) ),
    ck_scope_end(St3, St), ccl_scope_pop.
ck_expr(stmt_expr(B), St0, St) :- !, ck_stmt(B, St0, St).
ck_expr(compound_lit(T, init(Items)), St0, St) :- !, ck_init_slots(Items, T, none, St0, St).
ck_expr(E, St0, St) :- compound(E), !, E =.. [_|Args], ck_exprs(Args, St0, St).
ck_expr(_, St, St).
ck_exprs([], St, St).
ck_exprs([A|As], St0, St) :- ( is_list(A) -> ck_exprs(A, St0, St1) ; ck_expr(A, St0, St1) ), ck_exprs(As, St1, St).
%% an assignment target: its base is used, not consumed
ck_lval_use(id(_), St, St) :- !.
ck_lval_use(E, St0, St) :- ck_expr(E, St0, St).

%% arguments: first the callee's ties -- an argument for a parameter tied to
%% an earlier one lies within that argument -- then each in turn: the i-th is
%% consumed when the callee consumes it -- freed by free and fclose, moved by
%% an own parameter, the callee named or a function type (a pointer's) -- else
%% used; a borrow is not the callee's to take; a tied owner goes only to a
%% parameter tied itself
ck_args(Args, Callee, St0, St) :- ck_arg_ties(Args, Callee, St0), ck_args_(Args, Callee, 1, St0, St).
ck_arg_ties(Args, Callee, St) :- ( ck_callee_params(Callee, Ps) -> ck_arg_ties_(Ps, 1, Ps, Args, Callee, St) ; true ).
ck_arg_ties_([], _, _, _, _, _).
ck_arg_ties_([param(PT, _)|Rest], I, Ps, Args, Callee, St) :-
    (   ccl_tie_of(PT, Y), ck_param_index(Ps, Y, 1, J), ccl_nth(I, Args, A), ccl_nth(J, Args, B),
        ck_borrows_from(A, St, PA), ck_borrows_from(B, St, PB), \+ ck_within(St, PB, PA)
    ->  ck_name(A, N), ck_fail(tie_mismatch, N, call(Callee, Args))
    ;   true ),
    I1 is I + 1, ck_arg_ties_(Rest, I1, Ps, Args, Callee, St).
ck_callee_params(id(F), Ps) :- ccl_declared(F, T), ck_fn_params(T, Ps).
ck_callee_params(params(Ps), Ps).
ck_param_tied(Callee, I) :- ck_callee_params(Callee, Ps), ccl_nth(I, Ps, param(PT, _)), ccl_tie_of(PT, _).
ck_args_([], _, _, St, St).
ck_args_([A|As], Callee, I, St0, St) :-
    ( ck_path(A, AK), ck_by_value(A), ck_has_array_under(St0, AK) -> ck_fail(own_array_by_value, AK, call(Callee, [A|As])) ; true ),
    (   ck_consumes(Callee, I)
    ->  ( Callee = id(F), memberchk(F, [free, fclose]) -> How = free ; How = move ),
        ( Callee = id(_) -> Form = call(Callee, [A|As]) ; Form = call(pointer, [A|As]) ),
        ck_strip_move(A, A1),
        (   ck_owner_path(St0, A1, K)
        ->  ( How == move, ck_tied_to(K, _), \+ ck_param_tied(Callee, I) -> ck_fail(tie_escapes, K, Form) ; true ),
            ck_base_use(A1, St0, St1a), ck_consume(K, How, Form, St1a, St1, _)
        ;   ck_own_elem(A1, K) -> ck_expr(A1, St0, St1a), ck_dangle(St1a, K, St1)          % an element freed, or taken: the slot nulled by the lowering
        ;   A = move(_) -> ck_expr(A, St0, St1)
        ;   ck_path(A, K), ck_by_value(A), ck_own_under(St0, K, Fs), Fs \== [] -> ck_expr(A, St0, St1a), ck_move_out(St1a, Fs, Form, St1)
        ;   ck_borrows_from(A, St0, P), ck_state(St0, P, loose) -> ck_expr(A, St0, St1a), ck_consume_loose(St1a, P, St1)   % loose memory freed, or taken by an own parameter
        ;   ck_kind(A, St0, borrow(P)) -> ( A = id(N) -> true ; N = P ), ck_fail(borrow_consumed, N, Form)
        ;   ck_expr(A, St0, St1) )
    ;   ck_strip_move(A, A1), ck_path(A1, K), ck_by_value(A1), ck_own_under(St0, K, Fs), Fs \== [], ck_param_by_value(Callee, I)   % a struct with owners handed by value: its fields go to the callee's copy
    ->  ck_expr(A1, St0, St1a), ck_move_out(St1a, Fs, call(Callee, [A|As]), St1)
    ;   ck_expr(A, St0, St1) ),
    (   ck_dying_param(Callee, I), ck_arg_base(A, K), ck_own_under(St1, K, Fs), Fs \== []                % a destructor ran: the object's own fields are gone
    ->  ck_set_all(St1, Fs, moved, St1m), ck_dangle_all(St1m, Fs, St1d)
    ;   ck_fresh_param(Callee, I), ck_arg_base(A, K), ck_own_under(St1, K, Fs), Fs \== []               % a constructor ran: the object's own fields are live (or null, as good)
    ->  ck_set_all(St1, Fs, live, St1d)
    ;   St1d = St1 ),
    I1 is I + 1, ck_args_(As, Callee, I1, St1d, St).
ck_consumes(id(free), 1) :- !.
ck_consumes(id(fclose), 1) :- !.
ck_consumes(id(realloc), 1) :- !.                                    % the old block goes; the result is the new owner
ck_consumes(id(F), I) :- ccl_declared(F, T), ck_fn_params(T, Ps), ccl_nth(I, Ps, param(PT, _)), ck_own_type(PT).
ck_consumes(params(Ps), I) :- ccl_nth(I, Ps, param(PT, _)), ck_own_type(PT).
