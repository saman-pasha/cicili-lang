%% cicili-lang -- library(ccl_check): the safe part. The first ownership
%% check, run by cicili_ir/2 before anything is lowered.
%%
%% An OWNER is a pointer declared with the qualifier `own' -- a local, or a
%% parameter (the callee owns what it is given). An owner is linear: it is
%% CONSUMED exactly once on every path, by free(p) or fclose(p), by move(p)
%% (into another owner, or as an argument), by `return p', or by passing it
%% to a function whose parameter is `own'; a defer(p) { free(p); } consumes
%% it at the scope's exit, on every path, as the lowering runs it. Assigning
%% to a consumed owner makes it live again.
%%
%% The walk is flow-sensitive: the state of every owner (live | moved) is
%% threaded through the statements; at a join, an owner moved on one side
%% and live on the other is `partial' -- a use of it is refused as possibly
%% moved, and it counts as leaked where a live one would. A path that ends
%% (return, break, continue) contributes its state where it goes.
%%
%% A BORROW is a plain pointer whose value came from an owner -- `char *q = p',
%% `q = p + 1', `&p[i]', `&p->x', or from another borrow. It is bound to the
%% owner: the moment the owner is consumed the borrow dangles, and a use of it
%% is refused; and a borrow may not be returned, since the owner is consumed
%% by then. Assigning a borrow from something else unbinds it.
%%
%% THE ERRORS, each error(ownership(Kind, Name, Form), where(Function, line(L))),
%% the line the statement's:
%%   use_after_move      a consumed owner read, passed, freed again (the double free)
%%   borrow_after_move   a borrow used after its owner was consumed
%%   borrow_escapes      a borrow returned from the function
%%   owner_leaked        an owner live, or partial, at its scope's end or at a return
%%   move_in_loop        an owner from outside a loop consumed inside it (and not re-assigned)
%%   move_of_non_owner   move(x) of something that is not an owner
%%   owner_overwritten   assignment to a live owner (what it held would leak)
%%   goto_with_owners    a goto in a function that has owners (not followed yet)
%% Not tracked yet (M3's edge): non-owning pointers copied from an owner,
%% owners inside structs, owners through function pointers.

:- use_module(library(ccl_infer)).

ccl_check_units(Units) :- ccl_scope_init, ck_note_units(Units), ck_units(Units).
ccl_check_noted(Units) :- ck_units(Units).                            % on the table the caller built
ck_note_units([]).
ck_note_units([unit(Is)|Us]) :- ccl_items_note(Is), ck_note_units(Us).
ck_units([]).
ck_units([unit(Is)|Us]) :- ck_items(Is), ck_units(Us).
ck_items([]).
ck_items([function(L, _, _, Name, Params, _, Body)|Is]) :- !, ck_function(L, Name, Params, Body), ck_items(Is).
ck_items([_|Is]) :- ck_items(Is).

%% ---- state: frames of Name-State, innermost first; with each frame its defers ----------
ck_function(L, Name, Params, Body) :-
    nb_setval('$ck_fn', Name), nb_setval('$ck_line', L), nb_setval('$ck_loops', []),
    ccl_scope_push, ccl_declare_params(Params),
    ck_param_owners(Params, Owners),
    St0 = st([fr(Owners, [])]),
    ck_stmt(Body, St0, St1),
    ( St1 == dead -> true ; ck_leaks_all(St1, function_end) ),
    ccl_scope_pop.
ck_param_owners([], []).
ck_param_owners([param(T, N)|Ps], Os) :- ck_param_owners(Ps, Os0), ( N \== anon, ck_own_type(T) -> Os = [N-live|Os0] ; Os = Os0 ).
%% `own char *p': C's grammar puts the qualifier with the pointee, so an owner
%% is a pointer with own on itself or on what it points to
ck_own_type(ptr(Q, B)) :- ( memberchk(own, Q) ; B = base(Q2, _), memberchk(own, Q2) ), !.
ck_own_type(base(Q, _)) :- memberchk(own, Q), !.

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
ck_is_owner(St, N) :- ck_state(St, N, S), memberchk(S, [live, moved, partial]).
ck_declare(st([fr(Os, Ds)|Frs]), N, st([fr([N-live|Os], Ds)|Frs])).
ck_push(st(Frs), st([fr([], [])|Frs])).
ck_declare_borrow(st([fr(Os, Ds)|Frs]), N, P, st([fr([N-borrow(P)|Os], Ds)|Frs])).
%% a plain pointer assigned again: a borrow of something else, or of nothing
ck_rebind(St0, N, none, St) :- !, ( ck_state(St0, N, S), ( S = borrow(_) ; S = dangling(_) ) -> ck_set(St0, N, none, St) ; St = St0 ).
ck_rebind(St0, N, S, St) :- ( ck_state(St0, N, _) -> ck_set(St0, N, S, St) ; ck_declare_borrow(St0, N, P, St), S = borrow(P) ).
%% what an expression borrows from: an owner named, through arithmetic, a
%% cast, the address of an element or a member, another borrow
ck_borrows_from(id(N), St, P) :- ck_state(St, N, S), !, ( memberchk(S, [live, moved, partial]) -> P = N ; S = borrow(P) -> true ; S = dangling(P) ).
ck_borrows_from(bin(Op, A, _), St, P) :- memberchk(Op, ['+', '-']), !, ck_borrows_from(A, St, P).
ck_borrows_from(cast(_, A), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(index(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(member(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(addr(arrow(A, _)), St, P) :- !, ck_borrows_from(A, St, P).
ck_borrows_from(cond(_, A, B), St, P) :- !, ( ck_borrows_from(A, St, P) -> true ; ck_borrows_from(B, St, P) ).
ck_borrows_from(comma(_, B), St, P) :- !, ck_borrows_from(B, St, P).
%% a borrow may not leave the function: its owner is consumed by then
ck_no_escape(E, St) :- ( E \= id(_), ck_borrows_from(E, St, P) -> ck_fail(borrow_escapes, P, E) ; E = id(N), ck_state(St, N, borrow(P)) -> ck_fail(borrow_escapes, N, borrowed_from(P)) ; E = id(N), ck_state(St, N, dangling(P)) -> ck_fail(borrow_after_move, N, borrowed_from(P)) ; true ).
ck_pop(st([_|Frs]), st(Frs)).
ck_defer(st([fr(Os, Ds)|Frs]), Body, st([fr(Os, [Body|Ds])|Frs])).

%% a join: the same owner live on both sides is live, moved on both is moved, else partial
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
ck_merge_state(_, _, partial).

%% ---- statements: ck_stmt(+S, +St0, -St), St dead when the path ends here --------------
ck_stmt(_, dead, dead) :- !.
ck_stmt(block(Is), St0, St) :- !, ck_push(St0, St1), ck_stmts(Is, St1, St2), ck_scope_end(St2, St).
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
    ck_push(St0, St1),
    ( Init = decl(_, Vs) -> ck_decls(Vs, St1, St2) ; Init == none -> St2 = St1 ; ck_expr(Init, St1, St2) ),
    ( C == none -> St3 = St2 ; ck_expr(C, St2, St3) ),
    ck_loop_with_step(S, Step, St3, St4),
    ck_scope_end(St4, St).
ck_stmt(return(L), St0, dead) :- !, ck_line(L), ck_exit_all(St0, return).
ck_stmt(return(L, E), St0, dead) :- !, ck_line(L), ck_no_escape(E, St0), ck_consume_or_use(E, St0, St1), ck_exit_all(St1, return(E)).
ck_stmt(break(L), St0, dead) :- !, ck_line(L), ck_exit_to_loop(St0, break).
ck_stmt(continue(L), St0, dead) :- !, ck_line(L), ck_exit_to_loop(St0, continue).
ck_stmt(goto(Ln, L), St, dead) :- !, ck_line(Ln), ( ck_any_owner(St) -> ck_fail(goto_with_owners, L, goto(L)) ; true ).
ck_stmt(label(_, _, S), St0, St) :- !, ck_stmt(S, St0, St).
ck_stmt(switch(L, E, S), St0, St) :- !, ck_line(L),
    ck_expr(E, St0, St1),
    ( S = block(Is) -> true ; Is = [S] ),
    ck_push(St1, St2), ck_loop_enter(St2, switch), ck_switch_items(Is, St2, St2, St3), ck_loop_leave(Brk),
    ck_merge_all([St3|Brk], St4), ( ck_has_default(Is) -> St5 = St4 ; ck_merge(St4, St2, St5) ),
    ck_scope_end(St5, St).
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

%% declarations: an own variable is an owner from here
ck_decls([], St, St).
%% an owner's initializer takes an owner over; anyone else's only uses it (a borrow)
ck_decls([var(N, T, Init)|Vs], St0, St) :-
    ( Init == none -> St1 = St0 ; Init = init(Items) -> ck_init_items(Items, St0, St1)
    ; ck_own_type(T) -> ck_consume_or_use(Init, St0, St1) ; ck_expr(Init, St0, St1) ),
    (   ck_own_type(T) -> ck_declare(St1, N, St2)
    ;   Init \== none, ck_borrows_from(Init, St1, P) -> ck_declare_borrow(St1, N, P, St2)
    ;   St2 = St1 ),
    ck_decls(Vs, St2, St).
ck_init_items([], St, St).
ck_init_items([item(_, V)|Is], St0, St) :- ( V = init(Sub) -> ck_init_items(Sub, St0, St1) ; ck_consume_or_use(V, St0, St1) ), ck_init_items(Is, St1, St).

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
ck_leaks([N-S|Os], Form) :- ( ( S == moved ; S == none ; S = borrow(_) ; S = dangling(_) ) -> true ; ck_fail(owner_leaked, N, Form) ), ck_leaks(Os, Form).
ck_any_owner(st(Frs)) :- member(fr(Os, _), Frs), Os \== [], !.
ck_merge_all([S], S) :- !.
ck_merge_all([A, B|T], S) :- ck_merge(A, B, C), ck_merge_all([C|T], S).

%% ---- expressions --------------------------------------------------------------------------------
%% a value that is consumed if it is an owner (a return, an initializer), else used
ck_consume_or_use(id(N), St0, St) :- ck_is_owner(St0, N), !, ck_consume(N, id(N), St0, St).
ck_consume_or_use(move(E), St0, St) :- !, ck_expr(move(E), St0, St).
ck_consume_or_use(E, St0, St) :- ck_expr(E, St0, St).
ck_consume(N, Form, St0, St) :-
    ck_state(St0, N, S), ( S == live -> true ; ck_fail(use_after_move, N, Form) ), ck_set(St0, N, moved, St1), ck_dangle(St1, N, St).
%% the borrows of a consumed owner dangle, in every frame
ck_dangle(st(Frs), P, st(Frs1)) :- ck_dangle_frames(Frs, P, Frs1).
ck_dangle_frames([], _, []).
ck_dangle_frames([fr(Os, D)|T], P, [fr(Os1, D)|T1]) :- ck_dangle_owners(Os, P, Os1), ck_dangle_frames(T, P, T1).
ck_dangle_owners([], _, []).
ck_dangle_owners([N-borrow(P)|T], P, [N-dangling(P)|T1]) :- !, ck_dangle_owners(T, P, T1).
ck_dangle_owners([X|T], P, [X|T1]) :- ck_dangle_owners(T, P, T1).

ck_expr(_, dead, dead) :- !.
ck_expr(id(N), St, St) :- !,
    (   ck_state(St, N, S)
    ->  ( S == live -> true ; S == none -> true ; S = borrow(_) -> true ; S = dangling(P) -> ck_fail(borrow_after_move, N, borrowed_from(P)) ; ck_fail(use_after_move, N, id(N)) )
    ;   true ).
ck_expr(move(id(N)), St0, St) :- !, ( ck_is_owner(St0, N) -> ck_consume(N, move(id(N)), St0, St) ; ck_fail(move_of_non_owner, N, move(id(N))) ).
ck_expr(move(E), _, _) :- !, ck_fail(move_of_non_owner, E, move(E)).
ck_expr(call(id(F), Args), St0, St) :- !, ck_args(Args, F, 1, St0, St).
ck_expr(call(F, Args), St0, St) :- !, ck_expr(F, St0, St1), ck_exprs(Args, St1, St).
ck_expr(assign('=', id(N), R), St0, St) :- ck_is_owner(St0, N), !,
    ck_consume_or_use(R, St0, St1),
    ( ck_state(St1, N, live) -> ck_fail(owner_overwritten, N, assign('=', id(N), R)) ; ck_set(St1, N, live, St) ).
ck_expr(assign('=', id(N), R), St0, St) :- !,
    ck_expr(R, St0, St1),
    (   ck_borrows_from(R, St1, P) -> ck_rebind(St1, N, borrow(P), St)
    ;   ck_state(St1, N, S), ( S = borrow(_) ; S = dangling(_) ) -> ck_rebind(St1, N, none, St)
    ;   St = St1 ).
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
ck_expr(compound_lit(_, init(Items)), St0, St) :- !, ck_init_items(Items, St0, St).
ck_expr(E, St0, St) :- compound(E), !, E =.. [_|Args], ck_exprs(Args, St0, St).
ck_expr(_, St, St).
ck_exprs([], St, St).
ck_exprs([A|As], St0, St) :- ( is_list(A) -> ck_exprs(A, St0, St1) ; ck_expr(A, St0, St1) ), ck_exprs(As, St1, St).
%% an assignment target: its base is used, not consumed
ck_lval_use(id(_), St, St) :- !.
ck_lval_use(E, St0, St) :- ck_expr(E, St0, St).

%% arguments: the i-th is consumed when the callee consumes it, else used
ck_args([], _, _, St, St).
ck_args([A|As], F, I, St0, St) :-
    ( ck_consumes(F, I) -> ( A = id(N), ck_is_owner(St0, N) -> ck_consume(N, call(id(F), [A|As]), St0, St1) ; A = move(_) -> ck_expr(A, St0, St1) ; ck_expr(A, St0, St1) )
    ; ck_expr(A, St0, St1) ),
    I1 is I + 1, ck_args(As, F, I1, St1, St).
ck_consumes(free, 1) :- !.
ck_consumes(fclose, 1) :- !.
ck_consumes(F, I) :- ccl_declared(F, fn(_, Ps, _)), ccl_nth(I, Ps, param(T, _)), ck_own_type(T).
