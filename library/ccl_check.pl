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
%% A consumed owner may own again by assignment.
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
%% THE ERRORS, each error(ownership(Kind, Name, Form), where(Function, line(L))),
%% the line the statement's, Name the owner's path (`a->name'):
%%   use_after_move      a consumed owner read, passed, freed again (the double free)
%%   owner_unset         an owner read, passed, freed or moved before it was given anything
%%   borrow_after_move   a borrow used after its owner was consumed
%%   borrow_escapes      a borrow returned from the function
%%   borrow_stored       a borrow stored into a struct field, an element, a global, through a pointer, or into an own slot
%%   owner_stored        an owner's pointer stored into a plain slot (its ownership would be lost)
%%   owner_leaked        an owner live, or partial, at its scope's end, at a return, or a field when its struct is freed
%%   move_in_loop        an owner from outside a loop consumed inside it (and not re-assigned)
%%   move_of_non_owner   move(x) of something that is not an owner
%%   owner_overwritten   assignment to a live owner (what it held would leak)
%%   goto_with_owners    a goto in a function that has owners (not followed yet)
%% Not tracked: owners through function pointers, what a plain pointer to a
%% struct reaches (its fields are C's), a borrow passed to a function.

:- use_module(library(ccl_infer)).

ccl_check_units(Units) :- ccl_ensure_globals, ccl_scope_init, ck_note_units(Units), ck_units(Units).
ccl_check_noted(Units) :- ck_units(Units).                            % on the table the caller built
ck_note_units([]).
ck_note_units([unit(Is)|Us]) :- ccl_items_note(Is), ck_note_units(Us).
ck_units([]).
ck_units([unit(Is)|Us]) :- ck_items(Is), ck_units(Us).
ck_items([]).
ck_items([function(L, _, _, Name, Params, _, Body)|Is]) :- !, ck_function(L, Name, Params, Body), ck_items(Is).
ck_items([_|Is]) :- ck_items(Is).

%% ---- state: frames of Key-State, innermost first; with each frame its defers ----------
ck_function(L, Name, Params, Body) :-
    nb_setval('$ck_fn', Name), nb_setval('$ck_line', L), nb_setval('$ck_loops', []),
    ccl_scope_push, ccl_declare_params(Params),
    ck_param_owners(Params, Owners),
    St0 = st([fr(Owners, [])]),
    ck_stmt(Body, St0, St1),
    ( St1 == dead -> true ; ck_leaks_all(St1, function_end) ),
    ccl_scope_pop.
%% an own parameter is an owner, complete: its own fields are live; a struct
%% given by value with own fields owns those fields (the struct itself is not freed)
ck_param_owners([], []).
ck_param_owners([param(T, N)|Ps], Os) :-
    ck_param_owners(Ps, Os0),
    (   N \== anon, ck_own_type(T)
    ->  ck_var_fields(N, T, Fs), ck_states(Fs, live, FOs),
        ( ck_is_pointer_type(T) -> append([N-live|FOs], Os0, Os) ; append(FOs, Os0, Os) )
    ;   Os = Os0 ).
%% `own char *p': C's grammar puts the qualifier with the pointee, so an owner
%% is a pointer with own on itself or on what it points to
ck_own_type(ptr(Q, B)) :- ( memberchk(own, Q) ; B = base(Q2, _), memberchk(own, Q2) ), !.
ck_own_type(base(Q, _)) :- memberchk(own, Q), !.
ck_is_pointer_type(T) :- ccl_resolve_type(T, T1), T1 = ptr(_, _), !.

%% the own fields of a variable: N->f under an own pointer to a struct, N.f in a
%% struct held by value; a member held by value opens its own fields too
%% (N.inner.f); an own pointer member is one field and stops there
ck_var_fields(N, T, Fs) :-
    ccl_resolve_type(T, T1),
    (   T1 = ptr(_, PT), ck_own_type(T), ccl_members_of(PT, Ms) -> ck_member_fields(Ms, N, '->', Fs)
    ;   T1 = base(_, [struct(_, _)]), ccl_members_of(T1, Ms) -> ck_member_fields(Ms, N, '.', Fs)
    ;   Fs = [] ).
ck_member_fields([], _, _, []).
ck_member_fields([member(MT, F, _)|Ms], Base, Sep, Fs) :-
    (   F == anon -> Fs = Fs1
    ;   atomic_list_concat([Base, Sep, F], K),
        (   ck_own_type(MT) -> Fs = [K|Fs1]
        ;   ccl_resolve_type(MT, MT1), MT1 = base(_, [struct(_, _)]), ccl_members_of(MT1, Sub) -> ck_member_fields(Sub, K, '.', Fs0), append(Fs0, Fs1, Fs)
        ;   Fs = Fs1 ) ),
    ck_member_fields(Ms, Base, Sep, Fs1).
ck_states([], _, []).
ck_states([K|Ks], S, [K-S|Ps]) :- ck_states(Ks, S, Ps).

%% the path an lvalue names: a, a.f, a->f, a->inner.f
ck_path(id(N), N) :- atom(N).
ck_path(member(E, F), K) :- ck_path(E, B), atomic_list_concat([B, '.', F], K).
ck_path(arrow(E, F), K) :- ck_path(E, B), atomic_list_concat([B, '->', F], K).
ck_owner_path(St, E, K) :- ck_path(E, K), ck_is_owner(St, K).
%% the keys under a base: its fields, at any depth
ck_under(st(Frs), Base, Keys) :- ck_under_states(st(Frs), Base, Ps), ck_keys(Ps, Keys).
ck_under_states(st(Frs), Base, Ps) :-
    atom_concat(Base, '.', P1), atom_concat(Base, '->', P2),
    findall(K-S, ( member(fr(Os, _), Frs), member(K-S, Os), atom(K), ( sub_atom(K, 0, _, _, P1) ; sub_atom(K, 0, _, _, P2) ) ), Ps).
ck_keys([], []).
ck_keys([K-_|T], [K|Ks]) :- ck_keys(T, Ks).
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
ck_null(cast(_, E)) :- ck_null(E).

ck_line(L) :- ( integer(L), L > 0 -> nb_setval('$ck_line', L) ; true ).
ck_fail(Kind, Name, Form) :- nb_getval('$ck_fn', F), nb_getval('$ck_line', L), ck_short(Form, Short), throw(error(ownership(Kind, Name, Short), where(F, line(L)))).
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
ck_is_owner(St, N) :- ck_state(St, N, S), memberchk(S, [live, moved, partial, null, unset]).
ck_declare(st([fr(Os, Ds)|Frs]), N, S, st([fr([N-S|Os], Ds)|Frs])).
ck_declare_all(St, [], St).
ck_declare_all(St0, [K-S|Ps], St) :- ck_declare(St0, K, S, St1), ck_declare_all(St1, Ps, St).
ck_push(st(Frs), st([fr([], [])|Frs])).
ck_declare_borrow(st([fr(Os, Ds)|Frs]), N, P, st([fr([N-borrow(P)|Os], Ds)|Frs])).
%% a plain pointer assigned again: a borrow of something else, or of nothing
ck_rebind(St0, N, none, St) :- !, ( ck_state(St0, N, S), ( S = borrow(_) ; S = dangling(_) ) -> ck_set(St0, N, none, St) ; St = St0 ).
ck_rebind(St0, N, S, St) :- ( ck_state(St0, N, _) -> ck_set(St0, N, S, St) ; ck_declare_borrow(St0, N, P, St), S = borrow(P) ).
%% a local: declared in a frame of the function's, not the file's
ck_is_local(N) :- ccl_scope(Fs), append(Locals, [_], Fs), member(F, Locals), memberchk(N-_, F), !.
%% what an expression borrows from: an owner named, a field, through arithmetic,
%% a cast, the address of an element or a member, another borrow
ck_borrows_from(id(N), St, P) :- ck_state(St, N, S), !, ck_borrow_source(N, S, P).
ck_borrows_from(member(E, F), St, P) :- ck_path(member(E, F), K), ck_state(St, K, S), !, ck_borrow_source(K, S, P).
ck_borrows_from(arrow(E, F), St, P) :- ck_path(arrow(E, F), K), ck_state(St, K, S), !, ck_borrow_source(K, S, P).
ck_borrows_from(bin(Op, A, _), St, P) :- memberchk(Op, ['+', '-']), !, ck_borrows_from(A, St, P).
ck_borrows_from(cast(_, A), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(index(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(member(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(arrow(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(cond(_, A, B), St, P) :- !, ( ck_borrows_from(A, St, P) -> true ; ck_borrows_from(B, St, P) ).
ck_borrows_from(comma(_, B), St, P) :- !, ck_borrows_from(B, St, P).
ck_borrow_source(K, S, P) :- ( memberchk(S, [live, moved, partial, null, unset]) -> P = K ; S = borrow(P) -> true ; S = dangling(P) ).
%% a borrow may not leave the function: its owner is consumed by then
ck_no_escape(E, St) :- ( E \= id(_), \+ ck_owner_path(St, E, _), ck_borrows_from(E, St, P) -> ck_fail(borrow_escapes, P, E) ; E = id(N), ck_state(St, N, borrow(P)) -> ck_fail(borrow_escapes, N, borrowed_from(P)) ; E = id(N), ck_state(St, N, dangling(P)) -> ck_fail(borrow_after_move, N, borrowed_from(P)) ; true ).
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
ck_stmt(declaration(L, _, _, Vs), St0, St) :- !, ck_line(L), ck_decls(Vs, St0, St).
ck_stmt(typedef(_, _), St, St) :- !.
ck_stmt(declare(_, _), St, St) :- !.
ck_stmt(directive(_, _), St, St) :- !.
ck_stmt(include(_, _, _), St, St) :- !.
ck_stmt(static_assert(_, _, _), St, St) :- !.
ck_stmt(empty, St, St) :- !.
ck_stmt(expr(L, E), St0, St) :- !, ck_line(L), ck_expr(E, St0, St).
ck_stmt(defer(L, _, Body), St0, St) :- !, ck_line(L), ck_defer(St0, Body, St).
ck_stmt(if(L, C, T, E), St0, St) :- !, ck_line(L),
    ck_expr(C, St0, St1), ck_stmt(T, St1, StT), ( E == none -> StE = St1 ; ck_stmt(E, St1, StE) ), ck_merge(StT, StE, St).
ck_stmt(while(L, C, S), St0, St) :- !, ck_line(L), ck_expr(C, St0, St1), ck_loop(S, St1, St2), ck_expr(C, St2, St).
ck_stmt(do(L, S, C), St0, St) :- !, ck_line(L), ck_loop(S, St0, St1), ck_expr(C, St1, St).
ck_stmt(for(L, Init, C, Step, S), St0, St) :- !, ck_line(L),
    ccl_scope_push, ck_push(St0, St1),
    ( Init = decl(_, Vs) -> ck_decls(Vs, St1, St2) ; Init == none -> St2 = St1 ; ck_expr(Init, St1, St2) ),
    ( C == none -> St3 = St2 ; ck_expr(C, St2, St3) ),
    ck_loop_with_step(S, Step, St3, St4),
    ck_scope_end(St4, St), ccl_scope_pop.
ck_stmt(return(L), St0, dead) :- !, ck_line(L), ck_exit_all(St0, return).
ck_stmt(return(L, E), St0, dead) :- !, ck_line(L), ck_no_escape(E, St0), ck_consume_or_use(E, St0, St1), ck_exit_all(St1, return(E)).
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
ck_stmt(S, _, _) :- ck_fail(not_checked, S, S).
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
%% unset too; a struct by value with own fields owns them; a plain pointer
%% given an owner's value is a borrow
ck_decls([], St, St).
ck_decls([var(N, T, Init)|Vs], St0, St) :-
    ccl_declare(N, T),
    ck_var_fields(N, T, Fs), ck_states(Fs, unset, FOs),
    (   ck_own_type(T), ck_is_pointer_type(T)
    ->  ck_declare_all(St0, FOs, St1), ck_declare(St1, N, unset, St2),
        (   Init == none -> St3 = St2
        ;   ck_into_own(N, Init, var(N, Init), St2, St3a, Kind),
            ( Kind == fresh, \+ ck_allocation(Init) -> ck_set_all(St3a, Fs, live, St3) ; St3 = St3a ) )
    ;   Fs \== []
    ->  ck_declare_all(St0, FOs, St1), ( Init == none -> St3 = St1 ; ck_fill(N, T, Init, var(N, Init), St1, St3) )
    ;   Init == none -> St3 = St0
    ;   Init = init(Items) -> ck_init_slots(Items, T, none, St0, St3)
    ;   ck_expr(Init, St0, St1),
        ( ck_borrows_from(Init, St1, P) -> ck_declare_borrow(St1, N, P, St3) ; St3 = St1 ) ),
    ck_decls(Vs, St3, St).
ck_allocation(call(id(F), _)) :- memberchk(F, [malloc, calloc, realloc]).

%% what a right-hand side is to a slot: an owner (moved in), a null, a borrow, or a fresh value
ck_kind(E, _, null) :- ck_null(E), !.
ck_kind(move(E), St, K) :- !, ( ck_owner_path(St, E, P) -> K = owner(P) ; ck_name(E, N), ck_fail(move_of_non_owner, N, move(E)) ).
ck_name(E, N) :- ( ck_path(E, N) -> true ; N = E ).
ck_kind(E, St, owner(P)) :- ck_owner_path(St, E, P), !.
ck_kind(E, St, borrow(P)) :- ck_borrows_from(E, St, P), !.
ck_kind(_, _, fresh).

%% an own slot -- an owner, an own field (Key), or an untracked own place (none) --
%% receives a value: an owner is consumed into it and its own fields come along,
%% a null makes it null, a fresh value makes it live, a borrow is refused
ck_into_own(Key, R, Form, St0, St, Kind) :-
    ck_kind(R, St0, Kind),
    (   Kind = owner(P) -> ck_strip_move(R, E), ck_base_use(E, St0, St1), ck_under_states(St1, P, Src), ck_consume(P, move, Form, St1, St2, Prior), New = Prior, ck_transfer(St2, Src, P, Key, St3)
    ;   Kind = null -> ck_expr(R, St0, St3), New = null
    ;   Kind = borrow(P) -> ck_fail(borrow_stored, P, Form)
    ;   ck_expr(R, St0, St3), New = live ),
    (   Key == none -> St = St3
    ;   ck_state(St3, Key, Cur) -> ( Cur == live -> ck_fail(owner_overwritten, Key, Form) ; ck_set(St3, Key, New, St) )
    ;   St = St3 ).
%% a plain slot receives a value: an owner's pointer or a borrow may not be stored there
ck_into_plain(R, Form, St0, St) :-
    ck_kind(R, St0, Kind),
    (   Kind = owner(P) -> ck_fail(owner_stored, P, Form)
    ;   Kind = borrow(P) -> ck_fail(borrow_stored, P, Form)
    ;   ck_expr(R, St0, St) ).
%% the fields of an owner moved into another owner: the same states, under the new base
ck_transfer(St, _, _, none, St) :- !.
ck_transfer(St, [], _, _, St) :- !.
ck_transfer(St0, [SK-SS|Ps], P, Key, St) :-
    ( atom_concat(P, Suffix, SK), ( atom_concat(Key, Suffix, TK) ) -> ck_set_if(St0, TK, SS, St1) ; St1 = St0 ),
    ck_transfer(St1, Ps, P, Key, St).
%% a struct by value with own fields receives a whole value: from another such
%% struct its fields move over; from an initializer list, item by item; from a
%% call or anything else, fresh: every own field live
ck_fill(Key, T, R, Form, St0, St) :-
    (   R = init(Items) -> ck_init_slots(Items, T, Key, St0, St)
    ;   R = compound_lit(_, init(Items)) -> ck_init_slots(Items, T, Key, St0, St)
    ;   ck_path(R, P), ck_under_states(St0, P, Src), Src \== [] -> ck_expr(R, St0, St1), ck_move_fields(St1, Src, P, Key, Form, St)
    ;   ck_expr(R, St0, St1), ck_under(St1, Key, Ks), ck_set_live(St1, Ks, Form, St) ).
ck_set_live(St, [], _, St).
ck_set_live(St0, [K|Ks], Form, St) :- ( ck_state(St0, K, live) -> ck_fail(owner_overwritten, K, Form) ; ck_set(St0, K, live, St1) ), ck_set_live(St1, Ks, Form, St).
ck_move_fields(St, [], _, _, _, St).
ck_move_fields(St0, [SK-SS|Ps], P, Key, Form, St) :-
    ( SS == live -> New = live ; SS == null -> New = null ; SS == unset -> ck_fail(owner_unset, SK, Form) ; ck_fail(use_after_move, SK, Form) ),
    atom_concat(P, Suffix, SK), atom_concat(Key, Suffix, TK),
    ck_set(St0, SK, moved, St1), ck_dangle(St1, SK, St2),
    ( ck_state(St2, TK, live) -> ck_fail(owner_overwritten, TK, Form) ; ck_set_if(St2, TK, New, St3) ),
    ck_move_fields(St3, Ps, P, Key, Form, St).

%% an initializer list against its type: every slot is own or plain; under a
%% base (a variable's key) an own slot is that field
ck_init_slots(Items, T, Base, St0, St) :- ccl_resolve_type(T, T1), ck_init_slots_(Items, T1, Base, 0, St0, St).
ck_init_slots_([], _, _, _, St, St).
ck_init_slots_([item(Ds, V)|Is], T, Base, I, St0, St) :-
    ck_slot(T, Ds, I, SlotT, F, I1),
    ( ( Base == none ; F == none ) -> Key = none ; atomic_list_concat([Base, '.', F], Key) ),
    ck_init_slot(V, SlotT, Key, St0, St1),
    ck_init_slots_(Is, T, Base, I1, St1, St).
ck_slot(T, [field(F)|_], _, MT, F, I1) :- ccl_members_of(T, Ms), ck_member_at(Ms, F, 0, MT, Idx), !, I1 is Idx + 1.
ck_slot(arr(_, ET), [at(int(K))|_], _, ET, none, I1) :- !, I1 is K + 1.
ck_slot(arr(_, ET), [], I, ET, none, I1) :- !, I1 is I + 1.
ck_slot(T, [], I, MT, F, I1) :- ccl_members_of(T, Ms), I0 is I + 1, ccl_nth(I0, Ms, member(MT, F, _)), !, I1 is I + 1.
ck_slot(_, _, I, unknown, none, I1) :- I1 is I + 1.
ck_member_at([member(MT, F, _)|_], F, I, MT, I) :- !.
ck_member_at([_|Ms], F, I0, MT, I) :- I1 is I0 + 1, ck_member_at(Ms, F, I1, MT, I).
ck_init_slot(init(Sub), SlotT, Key, St0, St) :- !, ck_init_slots(Sub, SlotT, Key, St0, St).
ck_init_slot(V, SlotT, Key, St0, St) :-
    (   SlotT \== unknown, ck_own_type(SlotT) -> ck_into_own(Key, V, init(V), St0, St, _)
    ;   SlotT == unknown -> ck_expr(V, St0, St)
    ;   ck_into_plain(V, init(V), St0, St) ).

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
%% the frame's defers run, last first; then its owners must be consumed
ck_scope_end(dead, dead) :- !.
ck_scope_end(st([fr(Os, Ds)|Frs]), St) :-
    ck_run_defers(Ds, st([fr(Os, [])|Frs]), St1),
    ( St1 == dead -> St = dead ; st([fr(Os1, _)|Frs1]) = St1, ck_leaks(Os1, scope_end), St = st(Frs1) ).
ck_run_defers([], St, St).
ck_run_defers([B|Bs], St0, St) :- ck_stmt(B, St0, St1), ck_run_defers(Bs, St1, St).
%% a return: every frame's defers run, innermost first, then no owner may be live
ck_exit_all(St0, Form) :- ck_exit_frames(St0, Form).
ck_exit_frames(dead, _) :- !.
ck_exit_frames(st([]), _) :- !.
ck_exit_frames(st([fr(Os, Ds)|Frs]), Form) :-
    ck_run_defers(Ds, st([fr(Os, [])|Frs]), St1),
    ( St1 == dead -> true ; st([fr(Os1, _)|Frs1]) = St1, ck_leaks(Os1, Form), ck_exit_frames(st(Frs1), Form) ).
ck_leaks_all(st(Frs), Form) :- ck_leaks_frames(Frs, Form).
ck_leaks_frames([], _).
ck_leaks_frames([fr(Os, _)|Frs], Form) :- ck_leaks(Os, Form), ck_leaks_frames(Frs, Form).
ck_leaks([], _).
ck_leaks([N-S|Os], Form) :- ( ( memberchk(S, [moved, unset, null, none]) ; S = borrow(_) ; S = dangling(_) ) -> true ; ck_fail(owner_leaked, N, Form) ), ck_leaks(Os, Form).
ck_any_owner(st(Frs)) :- member(fr(Os, _), Frs), Os \== [], !.
ck_merge_all([S], S) :- !.
ck_merge_all([A, B|T], S) :- ck_merge(A, B, C), ck_merge_all([C|T], S).

%% ---- expressions --------------------------------------------------------------------------------
%% a value that is consumed if it is an owner or a struct with own fields (a return), else used
ck_consume_or_use(E, St0, St) :- ck_owner_path(St0, E, K), !, ck_base_use(E, St0, St1), ck_consume(K, move, E, St1, St, _).
ck_consume_or_use(move(E), St0, St) :- !, ck_expr(move(E), St0, St).
ck_consume_or_use(E, St0, St) :- ck_path(E, K), ck_under(St0, K, Fs), Fs \== [], !, ck_expr(E, St0, St1), ck_move_out(St1, Fs, E, St).
ck_consume_or_use(E, St0, St) :- ck_expr(E, St0, St).
%% consuming an owner, by free (fclose) or by move: it must be live or null; its
%% own fields must be consumed already when it is freed, complete when it is
%% moved; then it and they are moved, and their borrows dangle
ck_consume(K, How, Form, St0, St, Prior) :-
    ck_state(St0, K, Prior),
    ( Prior == live -> true ; Prior == null -> true ; Prior == unset -> ck_fail(owner_unset, K, Form) ; ck_fail(use_after_move, K, Form) ),
    ck_under(St0, K, Fs),
    ( Prior == null -> true ; ck_fields_consumable(Fs, How, St0, Form) ),
    ck_set(St0, K, moved, St1), ck_set_all(St1, Fs, moved, St2),
    ck_dangle_all(St2, [K|Fs], St).
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
%% a read of an owner, a field or a borrow
ck_read(K, S) :- ( memberchk(S, [live, null, none]) -> true ; S = borrow(_) -> true ; S = dangling(P) -> ck_fail(borrow_after_move, K, borrowed_from(P)) ; S == unset -> ck_fail(owner_unset, K, id(K)) ; ck_fail(use_after_move, K, id(K)) ).

ck_expr(_, dead, dead) :- !.
ck_expr(id(N), St, St) :- !, ( ck_state(St, N, S) -> ck_read(N, S) ; true ).
ck_expr(member(E, F), St0, St) :- ck_path(member(E, F), K), ck_state(St0, K, S), !, ck_expr(E, St0, St), ck_read(K, S).
ck_expr(arrow(E, F), St0, St) :- ck_path(arrow(E, F), K), ck_state(St0, K, S), !, ck_expr(E, St0, St), ck_read(K, S).
ck_expr(move(E), St0, St) :- !, ( ck_owner_path(St0, E, K) -> ck_base_use(E, St0, St1), ck_consume(K, move, move(E), St1, St, _) ; ck_name(E, N), ck_fail(move_of_non_owner, N, move(E)) ).
ck_expr(call(id(F), Args), St0, St) :- !, ck_args(Args, F, 1, St0, St).
ck_expr(call(F, Args), St0, St) :- !, ck_expr(F, St0, St1), ck_exprs(Args, St1, St).
%% assignment: to an owner or an own field; to a struct by value with own fields;
%% to a local plain pointer (a borrow, or not); to any other place, by its type
ck_expr(assign('=', L, R), St0, St) :- ck_owner_path(St0, L, K), !,
    ck_base_use(L, St0, St1), ck_into_own(K, R, assign('=', L, R), St1, St, _).
ck_expr(assign('=', L, R), St0, St) :- ck_path(L, K), ck_under(St0, K, [_|_]), !,
    ck_base_use(L, St0, St1), ( ccl_type_of(L, T) -> true ; T = unknown ), ck_fill(K, T, R, assign('=', L, R), St1, St).
ck_expr(assign('=', id(N), R), St0, St) :- ( ck_state(St0, N, _) ; ck_is_local(N) ), !,
    ck_expr(R, St0, St1),
    (   ck_borrows_from(R, St1, P) -> ck_rebind(St1, N, borrow(P), St)
    ;   ck_state(St1, N, S), ( S = borrow(_) ; S = dangling(_) ) -> ck_rebind(St1, N, none, St)
    ;   St = St1 ).
ck_expr(assign('=', L, R), St0, St) :- !,
    ck_lval_use(L, St0, St1),
    (   ccl_type_of(L, T), T \== unknown -> ( ck_own_type(T) -> ck_into_own(none, R, assign('=', L, R), St1, St, _) ; ck_into_plain(R, assign('=', L, R), St1, St) )
    ;   ck_expr(R, St1, St) ).
ck_expr(assign(_, L, R), St0, St) :- !, ck_expr(R, St0, St1), ck_lval_use(L, St1, St).
ck_expr(int(_), St, St) :- !.
ck_expr(float(_), St, St) :- !.
ck_expr(chr(_), St, St) :- !.
ck_expr(str(_), St, St) :- !.
ck_expr(sizeof(_), St, St) :- !.
ck_expr(sizeof_type(_), St, St) :- !.
ck_expr(cond(C, A, B), St0, St) :- !, ck_expr(C, St0, St1), ck_expr(A, St1, StA), ck_expr(B, St1, StB), ck_merge(StA, StB, St).
ck_expr(bin('&&', A, B), St0, St) :- !, ck_expr(A, St0, St1), ck_expr(B, St1, St2), ck_merge(St1, St2, St).
ck_expr(bin('||', A, B), St0, St) :- !, ck_expr(A, St0, St1), ck_expr(B, St1, St2), ck_merge(St1, St2, St).
ck_expr(stmt_expr(B), St0, St) :- !, ck_stmt(B, St0, St).
ck_expr(compound_lit(T, init(Items)), St0, St) :- !, ck_init_slots(Items, T, none, St0, St).
ck_expr(E, St0, St) :- compound(E), !, E =.. [_|Args], ck_exprs(Args, St0, St).
ck_expr(_, St, St).
ck_exprs([], St, St).
ck_exprs([A|As], St0, St) :- ( is_list(A) -> ck_exprs(A, St0, St1) ; ck_expr(A, St0, St1) ), ck_exprs(As, St1, St).
%% an assignment target: its base is used, not consumed
ck_lval_use(id(_), St, St) :- !.
ck_lval_use(E, St0, St) :- ck_expr(E, St0, St).

%% arguments: the i-th is consumed when the callee consumes it -- freed by free
%% and fclose, moved by an own parameter -- else used
ck_args([], _, _, St, St).
ck_args([A|As], F, I, St0, St) :-
    (   ck_consumes(F, I)
    ->  ( memberchk(F, [free, fclose]) -> How = free ; How = move ), Form = call(id(F), [A|As]),
        (   ck_owner_path(St0, A, K) -> ck_base_use(A, St0, St1a), ck_consume(K, How, Form, St1a, St1, _)
        ;   A = move(_) -> ck_expr(A, St0, St1)
        ;   ck_path(A, K), ck_under(St0, K, Fs), Fs \== [] -> ck_expr(A, St0, St1a), ck_move_out(St1a, Fs, Form, St1)
        ;   ck_expr(A, St0, St1) )
    ;   ck_expr(A, St0, St1) ),
    I1 is I + 1, ck_args(As, F, I1, St1, St).
ck_consumes(free, 1) :- !.
ck_consumes(fclose, 1) :- !.
ck_consumes(F, I) :- ccl_declared(F, fn(_, Ps, _)), ccl_nth(I, Ps, param(T, _)), ck_own_type(T).
