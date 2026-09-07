%% cicili-lang -- a census of a C++ header's flattened read: every construct
%% the reader gave, counted by functor, with the template shapes apart, so the
%% road to compiling libc++ is measured, not guessed.
%%
%%   CCL_CENSUS_FILE=inv.cpp cocolog --local query "ensure_loaded('test/census.pl'), census_main"
%%
%% inv.cpp is a file of #include lines; each include's unit is walked (a summary
%% is not: run under a fresh HOME so the header is read flattened).
:- use_module(library(cicili)).

census_main :- os_env('CCL_CENSUS_FLAT', F), !, census_flat(F).
census_main :-
    os_env('CCL_CENSUS_FILE', F),
    cicili_ast(F, unit(Is)),
    forall(member(include(_, Spec, X), Is), census_include(Spec, X)).

%% a flattened file (cicili++ -E): read as far as it reads, the stop and the farthest point shown with their tokens
census_flat(F) :-
    cicili_ast(F, unit(Is), Rest), length(Is, K), ccl_farthest(Far),
    (   Rest == [] -> format("== ~w: read WHOLE, ~w items~n", [F, K])
    ;   Rest = [tok(_, _, L)|_], format("== ~w: PARTIAL, ~w items; stopped at line ~w, farthest line ~w~n", [F, K, L, Far]),
        format("   from the stop: "), census_toks(Rest, 30), nl,
        (   append(Before, [tok(Kf, Vf, Far)|After], Rest) -> length(Before, NB), Skip is max(0, NB - 14), census_drop(Skip, Before, Tail),
            format("   around the farthest line ~w: ", [Far]), census_toks(Tail, 14), format(" <<HERE>> "), census_toks([tok(Kf, Vf, Far)|After], 30), nl
        ;   true ) ),
    census_count(Is).
census_drop(0, L, L) :- !.
census_drop(N, [_|L], R) :- N1 is N - 1, census_drop(N1, L, R).
census_count(Items) :-
    findall(Key, ( member(I, Items), census_sub(I, S), census_key(S, Key) ), Keys),
    msort(Keys, Sorted), census_runs(Sorted, Runs), sort(Runs, Asc), reverse(Asc, Desc),
    census_print(Desc, 90).

census_include(Spec, file(Path, How, U)) :- !,
    ( U = partial(unit(Items), line(L), near(N)) -> format("== ~w (~w, ~w) PARTIAL: stopped at line ~w near ~w~n", [Spec, Path, How, L, N]), census_where(Path, L)
    ; U = unit(Items) -> format("== ~w (~w, ~w) whole~n", [Spec, Path, How]) ),
    length(Items, K), format("   ~w top-level items~n", [K]), census_count(Items).
census_include(Spec, X) :- functor(X, F, A), format("== ~w: not a unit in memory (~w/~w)~n", [Spec, F, A]).

%% every subterm, lists walked element by element
census_sub(T, T).
census_sub([H|T], S) :- !, ( census_sub(H, S) ; census_sub(T, S) ).
census_sub(T, S) :- compound(T), T =.. [_|As], member(A, As), census_sub(A, S).

%% the key a subterm counts under: its functor, refined where the road cares
census_key(T, Key) :- compound(T), \+ T = [_|_], census_key_(T, Key).
census_key_(template(_, TPs, I), Key) :- !, functor(I, F, _), length(TPs, N),
    ( ccl_template_name(I, Nm), \+ atom(Nm) -> Key = 'template SPECIALIZATION' ; N =:= 0 -> Key = 'template <> explicit' ; atom_concat('template ', F, Key) ).
census_key_(class(_, N, Bs, _), Key) :- !, ( atom(N) -> ( Bs == [] -> Key = 'class' ; Key = 'class with bases' ) ; Key = 'class SPECIALIZED (template-id name)' ).
census_key_(method(_, Qs, _, N, _, _, B), Key) :- !,
    ( N = operator('=') -> Key = 'method operator=' ; N = operator(_) -> Key = 'method operator' ; memberchk(static, Qs) -> Key = 'method static' ; B == none -> Key = 'method declared only' ; Key = 'method with body' ).
census_key_(ctor(_, _, Ps, _, B), Key) :- !,
    ( Ps = [param(ref(_, _), _)] -> Key = 'ctor (const T &): copy' ; Ps = [param(rref(_, _), _)] -> Key = 'ctor (T &&): move' ; B == none -> Key = 'ctor declared only' ; Key = 'ctor' ).
census_key_(typedef(scoped(_, _)), 'type: dependent name T::x') :- !.
census_key_(typedef(tmpl(N, _)), Key) :- !, atom_concat('type: template-id ', N, Key).
census_key_(tmpl(N, _), Key) :- !, atom_concat('template-id ', N, Key).
census_key_(scoped(_, _), 'scoped name') :- !.
census_key_(decltype(_), 'type: decltype') :- !.
census_key_(base(_, [auto]), 'type: auto') :- !.
census_key_(param(_, _, _), 'param with default') :- !.
census_key_(param(_, _), 'param') :- !.
census_key_(tparam(K, _, D), Key) :- !, ( D == none -> atom_concat('tparam ', K, Key) ; atom_concat('tparam with default ', K, Key) ).
census_key_(using(_), 'member using (SKIPPED by the reader)') :- !.
census_key_(friend(_), 'member friend (skipped)') :- !.
census_key_(T, Key) :- functor(T, F, A), atomic_list_concat([F, '/', A], Key).

census_runs([], []).
census_runs([K|Ks], [N-K|Rs]) :- census_run(Ks, K, 1, N, Rest), census_runs(Rest, Rs).
census_run([K|Ks], K, N0, N, Rest) :- !, N1 is N0 + 1, census_run(Ks, K, N1, N, Rest).
census_run(Ks, _, N, N, Ks).
census_print(_, 0) :- !.
census_print([], _) :- !.
census_print([N-K|Rs], Left) :- format("~w  ~w~n", [N, K]), L1 is Left - 1, census_print(Rs, L1).

%% the tokens around where the read stopped: the first sixty from the first token on that line
census_where(Path, L) :-
    ccl_pp_file(Path, Tokens, _), length(Tokens, N), format("   ~w tokens in the flattened stream~n", [N]),
    ( append(_, [tok(K, V, L)|Rest], Tokens) -> census_toks([tok(K, V, L)|Rest], 60) ; true ), nl.
census_toks(_, 0) :- !.
census_toks([], _) :- !.
census_toks([tok(_, V, L)|Ts], N) :- format("~w@~w ", [V, L]), N1 is N - 1, census_toks(Ts, N1).
