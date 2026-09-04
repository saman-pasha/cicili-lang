%% cicili-lang -- library(ccl_include): an #include, found on the inclusion
%% path and read into an AST of its own, as the including file is parsed.
%%
%% When the parser (library(ccl_syntax)) meets `#include <name>' or
%% `#include "name"' at file scope it calls ccl_include/2 here, which finds
%% the file and reads it with the same reader -- recursively, since that
%% file's includes are met the same way -- and the includer's AST holds
%%
%%   include(Line, Spec, Resolved)
%%     Spec      system(Name) for <name>, local(Name) for "name"
%%     Resolved  file(Path, How, Unit) | macros(Path, Preds) | missing | cyclic(Path)
%%     How       raw           the file as written read whole, and that is its AST
%%               preprocessed  raw did not read whole (a system header is
%%                             conditionals and macros the reader does not expand),
%%                             so THAT FILE was run through `clang -E -dD' and the
%%                             result read; -dD keeps its #defines as directives
%%               unreadable    neither read: a lexical error, or no clang
%%     Unit      unit(Items) | partial(unit(Items), line(L), near(F)) | none
%%
%% and the typedef names the included unit declares are known to the rest
%% of the including file. A header is read once per process (a global by
%% path) and never twice on one path (cyclic).
%%
%% THE INCLUSION PATH, in order: the including file's directory (for a
%% quoted name only), then ccl_include_dir/1 facts, then $CICILI_INCLUDE
%% split on colons, then $COCOLOG_LIBRARY's directories (the macro files
%% this repository ships), then the toolchain's own list -- asked of clang once
%% (`clang -E -x c -v /dev/null', the lines between "search starts here"
%% and "End of search list") and cached; ccl_include_path_reset/0 forgets it.
%%
%% THE CACHE: a file read whole -- the one cicili/2 was given, and every
%% include -- is remembered in the knowledge base keyed by its modification
%% time and the reader's version, one clause per top-level item, so under
%% --embed it is in the store for the next process and is loaded from there
%% instead of re-read while time_file/2 answers the same time (and every
%% header it includes is at its remembered time too). A bare --embed opens
%% ./KB in the working directory: run cocolog with it from the project
%% directory and each system header is parsed once per project.
%%
%% THE SURFACE:
%%   ccl_read_file(+File, -AST, -Rest)      the top of cicili/3
%%   ccl_kb_forget                          drop every remembered file
%%   ccl_kb_forget_file(+Path)              drop one
%%   ccl_include(+Spec, -Resolved)          one include, from the current file
%%   ccl_include_path(-Dirs)                the inclusion path in force
%%   ccl_include_path_reset                 forget the cached toolchain list
%%   ccl_include_dir(?Dir)                  dynamic: assert a -I directory
%%   ccl_load_macros(+PlPath, -Preds)       load a macro file, register its predicates
%%   ccl_standard_macros                    register format/print/println (every unit does)
%%   ccl_declares(+Unit, +Name, -Item)      the function, declaration or typedef
%%                                          of Name, in the unit or any include
%%   ccl_unit_typedefs(+Unit, -Names)       every typedef name, includes too

:- use_module(library(ccl_syntax)).
:- use_module(library(ccl_infer)).
:- use_module(library(process)).
:- use_module(library(os)).
:- dynamic ccl_include_dir/1.

%% ---- what lives only in this process ----------------------------------------
%% A `:- dynamic' here PERSISTS under the store (see CLAUDE.md), so the units
%% read in this process, the files being read (the cycle guard) and the macro
%% files loaded are globals, not clauses: nb_setval/2 is the process's own.
ccl_unit_cached(Path, How, Unit) :- atom_concat('$ccl_unit:', Path, K), once(catch(nb_getval(K, How-Unit), _, fail)).
ccl_unit_cache(Path, How, Unit) :- atom_concat('$ccl_unit:', Path, K), nb_setval(K, How-Unit).
ccl_reading(Path) :- ccl_global('$ccl_reading', L, []), memberchk(Path, L).
ccl_reading_push(Path) :- ccl_global('$ccl_reading', L, []), nb_setval('$ccl_reading', [Path|L]).
ccl_reading_pop(Path) :- ccl_global('$ccl_reading', L, []), ccl_delete_one(L, Path, L1), nb_setval('$ccl_reading', L1).
ccl_delete_one([], _, []).
ccl_delete_one([X|T], X, T) :- !.
ccl_delete_one([Y|T], X, [Y|T1]) :- ccl_delete_one(T, X, T1).
ccl_macro_loaded(Path, Preds) :- ccl_global('$ccl_macro_files', L, []), memberchk(Path-Preds, L).
ccl_macro_note(Path, Preds) :- ccl_global('$ccl_macro_files', L, []), nb_setval('$ccl_macro_files', [Path-Preds|L]).

%% ---- the top ----------------------------------------------------------------
%% THE CACHE, as it must be under cocolog (a finding, in CLAUDE.md): a
%% predicate with ONE clause over about 8 KB loses EVERY clause in the store,
%% silently -- so a unit is stored one clause per top-level item, with its
%% count, and an include inside it as a reference to the header's own cached
%% unit; '$ccl_ast'/3 and '$ccl_item'/4 are declared by ccl_kb_ready/0:
%%      '$ccl_ast'(Path, Key, meta(What, Count, Deps))
%%      '$ccl_item'(Path, Key, Index, Item)     Item's include(L, S, file(P, How, U))
%%                                              stored as include(L, S, ref(P, How))
%%    What is top | included(How) | included_partial(How, Line, Near); Deps is
%%    [DepPath-DepKey ...], each checked against the header's current key on
%%    load; a count that does not match (an item too big to store) is a miss.
ccl_kb_ready :- ( ccl_global('$ccl_kb_ready', yes, no) -> true ; dynamic('$ccl_ast'/3), dynamic('$ccl_item'/4), nb_setval('$ccl_kb_ready', yes) ).
ccl_kb_forget_file(Path) :- ccl_kb_ready, retractall('$ccl_ast'(Path, _, _)), retractall('$ccl_item'(Path, _, _, _)).

ccl_read_file(File, AST, Rest) :-
    ccl_kb_cached(File, top, AST0), !, AST = AST0, Rest = [], nb_setval('$ccl_far', 0).
ccl_read_file(File, AST, Rest) :-
    read_file_to_codes(File, Codes),
    ccl_tokens(Codes, Tokens, RestCodes),
    ( RestCodes == [] -> true
    ; ccl_line_of(Codes, RestCodes, L), throw(error(syntax_error(cicili(File, lexical, line(L))), cicili(File))) ),
    ccl_with_file(File, ( ccl_unit(Tokens, AST, Rest), ccl_farthest(F) )),
    nb_setval('$ccl_far', F),
    ( Rest == [] -> ccl_kb_remember(File, top, AST) ; true ).

ccl_kb_key(Path, key(T, V)) :- once(catch(time_file(Path, T), _, fail)), ccl_reader_version(V).
ccl_kb_forget :- ccl_kb_ready, retractall('$ccl_ast'(_, _, _)), retractall('$ccl_item'(_, _, _, _)).

%% remember: What and a unit (or a partial one) -> meta + one clause per item
ccl_kb_remember(Path, What0, Unit) :-
    ccl_kb_ready,
    (   ccl_kb_key(Path, K)
    ->  ccl_kb_what(What0, Unit, What, Items),
        retractall('$ccl_ast'(Path, _, _)), retractall('$ccl_item'(Path, _, _, _)),
        ccl_kb_store_items(Items, Path, K, 0, N, [], Deps),
        assertz('$ccl_ast'(Path, K, meta(What, N, Deps)))
    ;   true ).
ccl_kb_what(top, unit(Is), top, Is) :- !.
ccl_kb_what(included(How), unit(Is), included(How), Is) :- !.
ccl_kb_what(included(How), partial(unit(Is), line(L), near(F)), included_partial(How, L, F), Is).
ccl_kb_store_items([], _, _, N, N, Deps, Deps).
ccl_kb_store_items([I|Is], Path, K, N0, N, D0, Deps) :-
    ccl_kb_flatten(I, I1, D0, D1),
    assertz('$ccl_item'(Path, K, N0, I1)),
    N1 is N0 + 1,
    ccl_kb_store_items(Is, Path, K, N1, N, D1, Deps).
ccl_kb_flatten(include(L, S, file(P, How, _)), include(L, S, ref(P, How)), D0, D) :- !,
    ( ccl_kb_key(P, PK) -> D = [P-PK|D0] ; D = D0 ).
ccl_kb_flatten(include(L, S, macros(P, Preds)), include(L, S, macros(P, Preds)), D0, D) :- !,
    ( ccl_kb_key(P, PK) -> D = [P-PK|D0] ; D = D0 ).
ccl_kb_flatten(I, I, D, D).

%% cached: the meta with the same key, every dep at its remembered key, every
%% item present -> the unit, its includes re-linked through ccl_include_read/2
ccl_kb_cached(Path, What, Unit) :-
    ccl_kb_ready, ccl_kb_key(Path, K),
    '$ccl_ast'(Path, K, meta(What0, N, Deps)), !,
    ccl_kb_deps_fresh(Deps),
    findall(I-It, '$ccl_item'(Path, K, I, It), Pairs),
    length(Pairs, N),
    sort(Pairs, Sorted), ccl_kb_values(Sorted, Items0),
    ccl_kb_link(Items0, Items),
    ccl_kb_unit(What0, What, Items, Unit).
ccl_kb_deps_fresh([]).
ccl_kb_deps_fresh([P-PK|Ds]) :- ccl_kb_key(P, PK), ccl_kb_deps_fresh(Ds).
ccl_kb_values([], []).
ccl_kb_values([_-V|T], [V|Vs]) :- ccl_kb_values(T, Vs).
ccl_kb_link([], []).
ccl_kb_link([include(L, S, ref(P, _))|T], [include(L, S, R)|Ls]) :- !, ccl_include_read(P, R), ccl_kb_link(T, Ls).
ccl_kb_link([I|T], [I|Ls]) :- ccl_kb_link(T, Ls).
ccl_kb_unit(top, top, Is, unit(Is)).
ccl_kb_unit(included(How), included(How), Is, unit(Is)).
ccl_kb_unit(included_partial(How, L, F), included(How), Is, partial(unit(Is), line(L), near(F))).

%% the file being read is a global, for the directory a quoted include starts
%% from; a nested read saves and restores it with the outer grammar's other
%% globals (its typedef environment, its farthest line)
ccl_with_file(File, Goal) :-
    ccl_save_globals(Saved),
    nb_setval('$ccl_file', File),
    ( catch(Goal, E, (ccl_restore_globals(Saved), throw(E)))
    -> ccl_restore_globals(Saved)
    ;  ccl_restore_globals(Saved), fail ).
ccl_save_globals(g(F, E, Far, M, Sc, Td, Tg)) :-
    ccl_global('$ccl_file', F, none), ccl_global('$ccl_env', E, []), ccl_global('$ccl_far', Far, 0), ccl_global('$ccl_macros', M, []),
    ccl_global('$ccl_scope', Sc, [[]]), ccl_global('$ccl_typedefs', Td, []), ccl_global('$ccl_tags', Tg, []).
ccl_restore_globals(g(F, E, Far, M, Sc, Td, Tg)) :-
    nb_setval('$ccl_file', F), nb_setval('$ccl_env', E), nb_setval('$ccl_far', Far), nb_setval('$ccl_macros', M),
    nb_setval('$ccl_scope', Sc), nb_setval('$ccl_typedefs', Td), nb_setval('$ccl_tags', Tg).
ccl_global(K, V, D) :- ( catch(nb_getval(K, V0), _, fail), V0 \== '$unset' -> V = V0 ; V = D ).

%% ---- the directive's text -----------------------------------------------------
ccl_include_spec(Text, Spec) :- atom_codes(Text, Cs), phrase(ccl_inc_spec(Spec), Cs).
ccl_inc_spec(Spec) --> [35], ccl_sp, "include", ccl_sp, ccl_inc_name(Spec), ccl_rest_any.
ccl_inc_name(system(N)) --> "<", ccl_upto(0'>, Cs), { atom_codes(N, Cs) }.
ccl_inc_name(local(N)) --> [34], ccl_upto(34, Cs), { atom_codes(N, Cs) }.
ccl_sp --> [C], { C =:= 32 ; C =:= 9 }, !, ccl_sp.
ccl_sp --> [].
ccl_upto(End, []) --> [End], !.
ccl_upto(End, [C|Cs]) --> [C], ccl_upto(End, Cs).
ccl_rest_any --> [_], !, ccl_rest_any.
ccl_rest_any --> [].

%% ---- one include --------------------------------------------------------------
ccl_include(Spec, R) :-
    ccl_global('$ccl_file', From, none),
    (   ccl_resolve_include(Spec, From, Path)
    ->  ( sub_atom(Path, _, 3, 0, '.pl') -> ccl_load_macros(Path, Preds), R = macros(Path, Preds) ; ccl_include_read(Path, R) )
    ;   R = missing ).

%% ---- a .pl included: its predicates are macros ---------------------------------
%% `#include "m.pl"' loads the Prolog file (ensure_loaded/1: a second load
%% replaces, and under the store the clauses stay in the process) and the
%% node is include(L, Spec, macros(Path, [macro(CName, Pred, Arity|dcg) ...])). From then on a
%% call name(a, b) in the C source, where name/3 is one of them, is run AT
%% PARSE TIME as name(ASTa, ASTb, Result) and Result stands in the AST -- in
%% an expression, as a statement (a statement term is unwrapped), or at file
%% scope; a list result is spliced in. The predicates a file defines are
%% what current_predicate/1 gains by loading it.
ccl_load_macros(Path, Preds) :- ccl_macro_loaded(Path, Preds), !, ccl_register_macros(Preds).
ccl_load_macros(Path, Preds) :-
    read_file_to_codes(Path, Codes),
    ccl_pl_clauses(Codes, Texts), ccl_pl_heads(Texts, Preds),
    ensure_loaded(Path),
    ccl_macro_note(Path, Preds),
    ccl_register_macros(Preds).

%% the heads a Prolog file defines -- current_predicate/1 does not list
%% consulted clauses here, so the text is split into clauses (a `.' followed
%% by layout, outside quotes, comments and 0'c) and each is read with
%% term_to_atom/2: name/Arity for a fact or a rule, dcg(name) for `-->'
ccl_pl_clauses(Codes, Texts) :- phrase(ccl_pl_split(Texts), Codes, _).
ccl_pl_split(Ts) --> ccl_pl_layout, ccl_pl_split_(Ts).
ccl_pl_split_([T|Ts]) --> ccl_pl_clause(Cs), { Cs \== [] }, !, { atom_codes(T, Cs) }, ccl_pl_layout, ccl_pl_split_(Ts).
ccl_pl_split_([]) --> [].
ccl_pl_layout --> [C], { ccl_blank(C) ; C =:= 10 }, !, ccl_pl_layout.
ccl_pl_layout --> [0'%], !, ccl_to_eol, ccl_pl_layout.
ccl_pl_layout --> [0'/, 0'*], !, ccl_pl_comment, ccl_pl_layout.
ccl_pl_layout --> [].
ccl_pl_comment --> [0'*, 0'/], !.
ccl_pl_comment --> [_], !, ccl_pl_comment.
ccl_pl_comment --> [].
ccl_pl_clause([0'0, 39, C|T]) --> [0'0, 39, C], !, ccl_pl_clause(T).
ccl_pl_clause([]) --> [0'.], ccl_pl_end, !.
ccl_pl_clause(T) --> [0'%], !, ccl_to_eol, ccl_pl_clause(T).
ccl_pl_clause(T) --> [0'/, 0'*], !, ccl_pl_comment, ccl_pl_clause(T).
ccl_pl_clause([39|T]) --> [39], !, ccl_pl_quoted(39, Q), { append(Q, T1, T) }, ccl_pl_clause(T1).
ccl_pl_clause([34|T]) --> [34], !, ccl_pl_quoted(34, Q), { append(Q, T1, T) }, ccl_pl_clause(T1).
ccl_pl_clause([C|T]) --> [C], ccl_pl_clause(T).
ccl_pl_end(S, S) :- ( S == [] ; S = [C|_], ( ccl_blank(C) ; C =:= 10 ; C =:= 0'% ) ), !.
ccl_pl_quoted(Q, [Q]) --> [Q], !.
ccl_pl_quoted(Q, [92, C|T]) --> [92, C], !, ccl_pl_quoted(Q, T).
ccl_pl_quoted(Q, [C|T]) --> [C], ccl_pl_quoted(Q, T).
%% an entry is macro(CName, Pred, Kind): the name in the C source, the
%% predicate, and its Prolog arity or dcg. A predicate named ccl_macro_X is
%% the macro X -- so a macro may be called what a builtin is called (format)
ccl_pl_heads([], []).
ccl_pl_heads([Text|Ts], Preds) :-
    (   catch(term_to_atom(Term, Text), _, fail), ccl_pl_head(Term, P)
    ->  ccl_pl_heads(Ts, Ps), ( memberchk(P, Ps) -> Preds = Ps ; Preds = [P|Ps] )
    ;   ccl_pl_heads(Ts, Preds) ).
ccl_pl_head((:- _), _) :- !, fail.
ccl_pl_head((H --> _), macro(C, N, dcg)) :- !, ccl_pl_functor(H, N, _), ccl_macro_cname(N, C).
ccl_pl_head((H :- _), macro(C, N, A)) :- !, ccl_pl_functor(H, N, A), ccl_macro_cname(N, C).
ccl_pl_head(H, macro(C, N, A)) :- ccl_pl_functor(H, N, A), ccl_macro_cname(N, C).
ccl_pl_functor(H, N, A) :- ( H = (M, _), callable(M) -> functor(M, N, A) ; functor(H, N, A) ), atom(N).
ccl_macro_cname(N, C) :- ( atom_concat(ccl_macro_, C0, N) -> C = C0 ; C = N ).

ccl_register_macros(Preds) :- ccl_global('$ccl_macros', M0, []), append(Preds, M0, M), nb_setval('$ccl_macros', M).

%% the standard macros -- format, print, println (library/ccl_format.pl) --
%% are global, there in every file without an include, like `:='; the parser
%% registers them at the start of every unit
ccl_standard_macros :-
    (   ccl_global('$ccl_std_macros', P0, none), P0 \== none -> P = P0
    ;   ccl_library_dirs(Ds), ( member(D, Ds), atomic_list_concat([D, '/ccl_format.pl'], P), exists_file(P) -> true ; P = none ),
        nb_setval('$ccl_std_macros', P) ),
    ( P == none -> true ; ccl_load_macros(P, _) ).

%% what an include brings into scope: its declarations, typedef definitions and
%% struct tags (for ccl_type_of/2 and friends, library(ccl_infer)) ...
ccl_include_scope(file(_, _, Unit)) :- !, ccl_unit_note(Unit).
ccl_include_scope(_).
ccl_unit_note(unit(Is)) :- !, ccl_items_note(Is).
ccl_unit_note(partial(U, _, _)) :- !, ccl_unit_note(U).
ccl_unit_note(_).

ccl_items_note([]).
ccl_items_note([include(_, _, R)|T]) :- !, ccl_include_scope(R), ccl_items_note(T).
ccl_items_note([I|T]) :- ccl_note_item(I), ccl_items_note(T).

%% ... and the macros of a .pl
%% it is, or of any .pl a header under it includes (loaded here if need be)
ccl_include_macros(macros(_, _)) :- !.                 % registered by ccl_load_macros
ccl_include_macros(file(_, _, Unit)) :- !, ccl_unit_macros(Unit, Pairs), ccl_load_each(Pairs).
ccl_include_macros(_).
ccl_load_each([]).
ccl_load_each([P-_|T]) :- ccl_load_macros(P, _), ccl_load_each(T).
ccl_unit_macros(unit(Is), Ms) :- !, ccl_items_macros(Is, Ms).
ccl_unit_macros(partial(U, _, _), Ms) :- !, ccl_unit_macros(U, Ms).
ccl_unit_macros(_, []).
ccl_items_macros([], []).
ccl_items_macros([include(_, _, macros(P, Preds))|T], [P-Preds|Ms]) :- !, ccl_items_macros(T, Ms).
ccl_items_macros([include(_, _, file(_, _, U))|T], Ms) :- !, ccl_unit_macros(U, M1), ccl_items_macros(T, M2), append(M1, M2, Ms).
ccl_items_macros([_|T], Ms) :- ccl_items_macros(T, Ms).

%% in order: read already in this process; in the knowledge base with the same
%% modification time; else read it now and remember it both ways
ccl_include_read(Path, cyclic(Path)) :- ccl_reading(Path), !.
ccl_include_read(Path, file(Path, How, Unit)) :- ccl_unit_cached(Path, How, Unit), !.
ccl_include_read(Path, file(Path, How, Unit)) :- ccl_kb_cached(Path, included(How), Unit), !, ccl_unit_cache(Path, How, Unit).
ccl_include_read(Path, file(Path, How, Unit)) :-
    ccl_reading_push(Path),
    ( catch(ccl_read_unit(Path, How0, Unit0), _, fail) -> How = How0, Unit = Unit0 ; How = unreadable, Unit = none ),
    ccl_reading_pop(Path),
    ccl_unit_cache(Path, How, Unit),
    ( How == unreadable -> true ; ccl_kb_remember(Path, included(How), Unit) ).

%% raw first; preprocessed only when raw does not read whole
ccl_read_unit(Path, How, Unit) :-
    ccl_parse_file(Path, U0, Info0),
    (   Info0 == whole -> How = raw, Unit = U0
    ;   ccl_preprocess(Path, PP), ccl_parse_file(PP, U1, Info1) -> How = preprocessed, ccl_partial(U1, Info1, Unit)
    ;   How = raw, ccl_partial(U0, Info0, Unit) ).
ccl_partial(U, whole, U) :- !.
ccl_partial(U, stopped(L, near(F)), partial(U, line(L), near(F))).
ccl_parse_file(Path, unit(Is), Info) :-
    read_file_to_codes(Path, Codes),
    ccl_tokens(Codes, Tokens, RestCodes),
    ( RestCodes == [] -> true ; throw(lexical(Path)) ),
    ccl_with_file(Path, ( ccl_unit(Tokens, unit(Is), Rest), ccl_rest_info(Rest, Info) )).
ccl_rest_info([], whole) :- !.
ccl_rest_info([tok(_, _, L)|_], stopped(L, near(F))) :- ccl_farthest(F).

ccl_preprocess(Path, Out) :-
    tmp_file(ccl_pp, Out0), atom_concat(Out0, '.i', Out),
    atomic_list_concat(['clang -E -dD -x c \'', Path, '\' -o \'', Out, '\' 2>/dev/null'], Cmd),
    once(catch(proc_run(Cmd, 60000, _, Exit), _, fail)), Exit == 0, exists_file(Out).

%% ---- the path ----------------------------------------------------------------
ccl_resolve_include(local(N), From, Path) :-
    From \== none, file_directory_name(From, Dir), atomic_list_concat([Dir, '/', N], P0), exists_file(P0), !, Path = P0.
ccl_resolve_include(Spec, _, Path) :-
    ( Spec = local(N) ; Spec = system(N) ),
    ccl_include_path(Dirs), member(D, Dirs), atomic_list_concat([D, '/', N], P), exists_file(P), !, Path = P.

ccl_include_path(Dirs) :-
    (   ccl_global('$ccl_incpath', D0, none), D0 \== none -> Dirs = D0
    ;   ccl_user_dirs(U), ccl_library_dirs(Ls), ccl_toolchain_dirs(T), append(U, Ls, UL), append(UL, T, Dirs), nb_setval('$ccl_incpath', Dirs) ).
%% the cocolog library directories, so `#include <ccl_format.pl>' finds the
%% macro files this repository ships beside its grammars
ccl_library_dirs(Ds) :-
    ( once(catch(os_env('COCOLOG_LIBRARY', V), _, fail)), V \== '' -> atom_codes(V, Cs), ccl_split(Cs, 0':, Parts), ccl_atoms(Parts, Ds) ; Ds = [] ).
ccl_include_path_reset :- nb_setval('$ccl_incpath', none).
ccl_user_dirs(Ds) :-
    findall(D, ccl_include_dir(D), Ds0),
    ( catch(os_env('CICILI_INCLUDE', V), _, fail), V \== '' -> atom_codes(V, Cs), ccl_split(Cs, 0':, Parts), ccl_atoms(Parts, Es), append(Ds0, Es, Ds) ; Ds = Ds0 ).
ccl_toolchain_dirs(Ds) :-
    ( catch(proc_run('clang -E -x c -v /dev/null 2>&1', 30000, Out, _), _, fail) -> ccl_search_list(Out, Ds) ; Ds = [] ).
ccl_search_list(Codes, Dirs) :- ccl_split(Codes, 10, Lines), ccl_after_marker(Lines, Rest), ccl_until_end(Rest, Dirs).
ccl_after_marker([], []).
ccl_after_marker([L|Ls], R) :- ( atom_codes(A, L), sub_atom(A, _, _, _, 'search starts here') -> R = Ls ; ccl_after_marker(Ls, R) ).
ccl_until_end([], []).
ccl_until_end([L|Ls], Ds) :-
    atom_codes(A, L),
    (   sub_atom(A, _, _, _, 'End of search list') -> Ds = []
    ;   ( sub_atom(A, _, _, _, 'search starts here') ; sub_atom(A, _, _, _, 'framework directory') ) -> ccl_until_end(Ls, Ds)
    ;   ccl_strip(L, S), atom_codes(D, S), ( ( D == '.' ; D == '' ) -> Ds = Ds1 ; Ds = [D|Ds1] ), ccl_until_end(Ls, Ds1) ).
ccl_strip([C|Cs], S) :- ( C =:= 32 ; C =:= 9 ), !, ccl_strip(Cs, S).
ccl_strip(S, S).
ccl_split([], _, [[]]).
ccl_split([C|Cs], Sep, Parts) :- ccl_split(Cs, Sep, [P|Ps]), ( C =:= Sep -> Parts = [[], P|Ps] ; Parts = [[C|P]|Ps] ).
ccl_atoms([], []).
ccl_atoms([[]|T], As) :- !, ccl_atoms(T, As).
ccl_atoms([Cs|T], [A|As]) :- atom_codes(A, Cs), ccl_atoms(T, As).

%% ---- what an included unit declares ----------------------------------------------
ccl_include_typedefs(file(_, _, Unit), Env0, Env) :- !, ccl_unit_typedefs(Unit, Names), append(Names, Env0, Env).
ccl_include_typedefs(_, Env, Env).
ccl_unit_typedefs(unit(Is), Ns) :- !, ccl_items_typedefs(Is, Ns).
ccl_unit_typedefs(partial(U, _, _), Ns) :- !, ccl_unit_typedefs(U, Ns).
ccl_unit_typedefs(_, []).
ccl_items_typedefs([], []).
ccl_items_typedefs([typedef(_, Ds)|T], Ns) :- !, ccl_declared_names(Ds, N1), ccl_items_typedefs(T, N2), append(N1, N2, Ns).
ccl_items_typedefs([include(_, _, R)|T], Ns) :- !, ccl_include_typedefs(R, [], N1), ccl_items_typedefs(T, N2), append(N1, N2, Ns).
ccl_items_typedefs([_|T], Ns) :- ccl_items_typedefs(T, Ns).

%% ccl_declares(+Unit, +Name, -Item): the item declaring Name, here or in an
%% include, depth first in file order
ccl_declares(unit(Is), Name, Item) :- !, ccl_items_declare(Is, Name, Item).
ccl_declares(partial(U, _, _), Name, Item) :- ccl_declares(U, Name, Item).
ccl_items_declare([I|_], Name, I) :- ccl_item_declares(I, Name), !.
ccl_items_declare([include(_, _, file(_, _, U))|_], Name, Item) :- ccl_declares(U, Name, Item), !.
ccl_items_declare([_|T], Name, Item) :- ccl_items_declare(T, Name, Item).
ccl_item_declares(function(_, _, _, Name, _, _, _), Name).
ccl_item_declares(declaration(_, _, _, Ds), Name) :- memberchk(var(Name, _, _), Ds).
ccl_item_declares(typedef(_, Ds), Name) :- memberchk(var(Name, _, _), Ds).
