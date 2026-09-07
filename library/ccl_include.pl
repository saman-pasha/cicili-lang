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
%%                             so THAT FILE went through the preprocessor,
%%                             library(ccl_pp) -- cocolog's own -- and the result read
%%               unreadable    neither read: a lexical error
%%     Unit      unit(Items) | partial(unit(Items), line(L), near(F)) | none
%%
%% and the typedef names the included unit declares are known to the rest
%% of the including file. A header is read once per process (a global by
%% path) and never twice on one path (cyclic).
%%
%% THE INCLUSION PATH, in order: the including file's directory (for a
%% quoted name only), then ccl_include_dir/1 facts, then $CICILI_INCLUDE
%% split on colons, then $COCOLOG_LIBRARY's directories (the macro files
%% this repository ships), then the toolchain's directories from where the
%% conventions put them (ccl_toolchain_dirs/1: the C++ library, this
%% compiler's own library/include, /usr/local/include, the SDK -- no tool
%% is run), cached; ccl_include_path_reset/0 forgets it.
%%
%% THE CACHE: a file read whole -- the one cicili_ast/2 was given, and every
%% include -- is remembered in the knowledge base keyed by its modification
%% time and the reader's version, one clause per top-level item, so under
%% --embed it is in the store for the next process and is loaded from there
%% instead of re-read while time_file/2 answers the same time (and every
%% header it includes is at its remembered time too). A bare --embed opens
%% ./KB in the working directory: run cocolog with it from the project
%% directory and each system header is parsed once per project.
%%
%% THE SURFACE:
%%   ccl_read_file(+File, -AST, -Rest)      the top of cicili_ast/3
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
:- use_module(library(ccl_pp)).
:- use_module(library(process)).
:- use_module(library(os)).
:- dynamic ccl_include_dir/1.

%% ---- what lives only in this process ----------------------------------------
%% A `:- dynamic' here PERSISTS under the store (see CLAUDE.md), so the units
%% read in this process, the files being read (the cycle guard) and the macro
%% files loaded are globals, not clauses: nb_setval/2 is the process's own.
ccl_unit_cached(Path, How, Unit) :- ccl_global('$ccl_unit_paths', Ps, []), memberchk(Path, Ps), atom_concat('$ccl_unit:', Path, K), nb_getval(K, How-Unit).
ccl_unit_cache(Path, How, Unit) :- atom_concat('$ccl_unit:', Path, K), nb_setval(K, How-Unit), ccl_global('$ccl_unit_paths', Ps, []), nb_setval('$ccl_unit_paths', [Path|Ps]).
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
%% unit; '$ccl_ast'/3 is declared by ccl_kb_ready/0, a file's item predicate
%% by ccl_kb_items/2 (the '$ccl_item'(Path, ...) below reads '$ccl_items:Path'(...)):
%%      '$ccl_ast'(Path, Key, meta(What, Count, Deps))
%%      '$ccl_item'(Path, Key, Index, Item)     Item's include(L, S, file(P, How, U))
%%                                              stored as include(L, S, ref(P, How))
%%    What is top | included(How) | included_partial(How, Line, Near); Deps is
%%    [DepPath-DepKey ...], each checked against the header's current key on
%%    load; a count that does not match (an item too big to store) is a miss.
ccl_kb_ready :- ccl_ensure_globals, ( nb_getval('$ccl_kb_ready', yes) -> true ; dynamic('$ccl_ast'/3), dynamic('$ccl_hmeta'/3), nb_setval('$ccl_kb_ready', yes) ).
%% The items of a file are a predicate of their own, '$ccl_items:<Path>'(Key,
%% Index, Item): the store grows, once per process that writes a predicate, by
%% about 500 bytes per row THAT predicate holds, whatever the write -- one
%% assertz into a 39k-row '$ccl_item'/4 cost 19.5 MB, and forty writing gate
%% processes made the 870 MB store. A source file's rows are written at every
%% change; in their own small predicate that costs one page.
ccl_kb_items(Path, F) :- atom_concat('$ccl_items:', Path, F), dynamic(F/3).
ccl_kb_items_goal(Path, K, I, It, T) :- ccl_kb_items(Path, F), T =.. [F, K, I, It].
ccl_kb_forget_items(Path) :- ccl_kb_items_goal(Path, _, _, _, T), retractall(T).
ccl_kb_forget_file(Path) :- ccl_kb_ready, retractall('$ccl_ast'(Path, _, _)), ccl_kb_forget_items(Path), retractall('$ccl_hmeta'(Path, _, _)), ccl_kb_hm(Path, F), T =.. [F, _, _, _], retractall(T).

ccl_read_file(File, AST, Rest) :- ccl_ensure_globals, ccl_set_lang(File), ccl_read_file_(File, AST, Rest).
%% the language of the file read: C++ by its extension (or forced, cicili++), C by .c
ccl_set_lang(File) :-
    (   nb_getval('$ccl_lang_forced', F), F \== none -> nb_setval('$ccl_lang', F)
    ;   ccl_lang_of_file(File, L) -> nb_setval('$ccl_lang', L)
    ;   true ).
ccl_lang_of_file(F, cpp) :- member(E, ['.cpp', '.cc', '.cxx', '.C', '.hpp', '.hh', '.hxx']), sub_atom(F, _, _, 0, E), !.
ccl_lang_of_file(F, c) :- sub_atom(F, _, _, 0, '.c'), !.
ccl_read_file_(File, AST, Rest) :-
    ccl_kb_cached(File, top, AST0), !, AST = AST0, Rest = [], nb_setval('$ccl_far', 0).
ccl_read_file_(File, AST, Rest) :-
    catch(ccl_pp_top(File, Tokens, _), lexical(L), throw(error(syntax_error(cicili_ast(File, lexical, line(L))), cicili_ast(File)))),   % the user's file through the preprocessor
    ccl_with_file(File, ( ccl_unit(Tokens, AST, Rest), ccl_farthest(F) )),
    nb_setval('$ccl_far', F),
    ( Rest == [] -> ccl_kb_remember(File, top, AST) ; true ).

ccl_kb_key(Path, key(T, V)) :- once(catch(time_file(Path, T), _, fail)), ccl_reader_version(V0), ( ccl_lang(cpp) -> ccl_std(S), V = cpp(V0, S) ; V = V0 ).
ccl_std(S) :- ( catch(nb_getval('$ccl_std', S0), _, fail) -> S = S0 ; S = 17 ).   % a C++ read is not the C read; the time asked every time (0.4 ms): the gate touches a file mid-process and expects the miss
ccl_kb_forget :- ccl_kb_ready, findall(P, '$ccl_ast'(P, _, _), Ps), ccl_kb_forget_each(Ps), retractall('$ccl_ast'(_, _, _)).
ccl_kb_forget_each([]).
ccl_kb_forget_each([P|Ps]) :- ccl_kb_forget_items(P), ccl_kb_forget_each(Ps).

%% remember: What and a unit (or a partial one) -> meta + one clause per item
ccl_kb_remember(Path, What0, Unit) :-
    ccl_kb_ready,
    (   ccl_kb_key(Path, K)
    ->  ccl_kb_what(What0, Unit, What, Items),
        retractall('$ccl_ast'(Path, _, _)), ccl_kb_forget_items(Path),
        ccl_kb_items(Path, F),
        (   catch(ccl_kb_store_items(Items, F, K, 0, N, [], Deps), error(resource_error(clause_length), _), fail)
        ->  assertz('$ccl_ast'(Path, K, meta(What, N, Deps)))
        ;   % an item over the store's clause budget (cocolog 1.2: an error, no
            % longer a silent loss): this file is read again next time, not cached
            ccl_kb_forget_items(Path)
        )
    ;   true ).
ccl_kb_what(top, unit(Is), top, Is) :- !.
ccl_kb_what(included(How), unit(Is), included(How), Is) :- !.
ccl_kb_what(included(How), partial(unit(Is), line(L), near(F)), included_partial(How, L, F), Is).
ccl_kb_store_items([], _, _, N, N, Deps, Deps).
ccl_kb_store_items([I|Is], F, K, N0, N, D0, Deps) :-
    ccl_kb_flatten(I, I1, D0, D1),
    T =.. [F, K, N0, I1], assertz(T),
    N1 is N0 + 1,
    ccl_kb_store_items(Is, F, K, N1, N, D1, Deps).
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
    ccl_kb_items_goal(Path, K, I, It, T), findall(I-It, T, Pairs),
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
ccl_save_globals(g(F, E, Far, M, Sc, Gs, Td, Tg, En, Ex)) :-
    ccl_global('$ccl_file', F, none), ccl_global('$ccl_env', E, []), ccl_global('$ccl_far', Far, 0), ccl_global('$ccl_macros', M, []),
    ccl_global('$ccl_scope', Sc, []), ccl_global('$ccl_gscope', Gs, []), ccl_global('$ccl_typedefs', Td, []), ccl_global('$ccl_tags', Tg, []),
    ccl_global('$ccl_enums', En, []), ccl_global('$ccl_expansions', Ex, []).
ccl_restore_globals(g(F, E, Far, M, Sc, Gs, Td, Tg, En, Ex)) :-
    nb_setval('$ccl_file', F), nb_setval('$ccl_env', E), nb_setval('$ccl_far', Far), nb_setval('$ccl_macros', M),
    nb_setval('$ccl_scope', Sc), nb_setval('$ccl_gscope', Gs), nb_setval('$ccl_typedefs', Td), nb_setval('$ccl_tags', Tg), nb_setval('$ccl_enums', En),
    ccl_tables_changed, nb_setval('$ccl_expansions', Ex).
%% every global is set once per process (ccl_ensure_globals/0), so reads are
%% bare nb_getval/2: a catch/3 costs in proportion to the terms bound inside
%% it, 37 ms with the symbol table -- a finding, in CLAUDE.md
ccl_global(K, V, _) :- ccl_ensure_globals, nb_getval(K, V).
ccl_ensure_globals :-
    ( catch(nb_getval('$ccl_inited', yes), _, fail) -> true
    ; nb_setval('$ccl_file', none), nb_setval('$ccl_env', []), nb_setval('$ccl_far', 0), nb_setval('$ccl_macros', []),
      nb_setval('$ccl_scope', []), nb_setval('$ccl_gscope', []), nb_setval('$ccl_typedefs', []), nb_setval('$ccl_tags', []), nb_setval('$ccl_enums', []), ccl_tables_changed,
      nb_setval('$ccl_expansions', []), nb_setval('$ccl_incpath', none), nb_setval('$ccl_kb_ready', no), nb_setval('$ccl_reading', []),
      nb_setval('$ccl_macro_files', []), nb_setval('$ccl_std_macros', none), nb_setval('$ccl_gensym', 0), nb_setval('$ccl_unit_paths', []),
      nb_setval('$ccl_lang', c), nb_setval('$ccl_lang_forced', none), nb_setval('$ccl_class', []), nb_setval('$ccl_inc_kind', local), nb_setval('$ccl_hash', line),
      nb_setval('$ccl_targ', 0), nb_setval('$ccl_tmpl_depth', 0),
      ( catch(nb_getval('$ccl_std', _), _, fail) -> true ; nb_setval('$ccl_std', 17) ),
      nb_setval('$ccl_templates', [vector, map, set, unordered_map, unordered_set, list, deque, array, pair, tuple, optional, variant,
                                   unique_ptr, shared_ptr, weak_ptr, function, basic_string, initializer_list, allocator, less, greater, hash,
                                   numeric_limits, is_same, enable_if, remove_reference, decay, queue, stack, priority_queue, span,
                                   '__builtin_common_type', '__type_pack_element', '__make_integer_seq', '__integer_pack']),   % the compiler's template-shaped builtins
      ( catch(ccl_lex_native('', 1, line, c, _, _), _, fail) -> nb_setval('$ccl_lexer', native) ; nb_setval('$ccl_lexer', dcg) ),
      nb_setval('$ccl_sumload:names', []),
      nb_setval('$ccl_inited', yes) ).

%% ---- the directive's text -----------------------------------------------------
ccl_include_spec(Text, Spec) :- atom_codes(Text, Cs), phrase(ccl_inc_spec(Spec), Cs).
ccl_inc_spec(next(Spec)) --> [35], ccl_sp, "include_next", ccl_sp, ccl_inc_name(Spec), ccl_rest_any.   % the path after the including file's directory
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
    ->  ( sub_atom(Path, _, 3, 0, '.pl') -> ccl_load_macros(Path, Preds), R = macros(Path, Preds) ; ccl_inc_kind(Spec, Kind), nb_setval('$ccl_inc_kind', Kind), ccl_include_read(Path, R) )
    ;   R = missing ).
ccl_inc_kind(system(_), system) :- !.
ccl_inc_kind(next(_), system) :- !.
ccl_inc_kind(_, local).

%% ---- a .pl included: its predicates are macros ---------------------------------
%% `#include "m.pl"' loads the Prolog file (ensure_loaded/1: a second load
%% replaces, and under the store the clauses stay in the process) and the
%% node is include(L, Spec, macros(Path, [macro(CName, Pred, Arity|dcg) ...])). From then on a
%% call name(a, b) in the C source, where name/3 is one of them, is run AT
%% PARSE TIME as name(ASTa, ASTb, Result) and Result stands in the AST -- in
%% an expression, as a statement (a statement term is unwrapped), or at file
%% scope; a list result is spliced in. The predicates a file defines are
%% what current_predicate/1 gains by loading it.
%% `#cocolog ... #end' in a C file (owner's rule): the lines between are a
%% macro file written in place -- to a temporary .pl, loaded and registered
%% like `#include "m.pl"', so every predicate they define is a macro from
%% that line on; the block stays in the AST as cocolog(Line, Text), which
%% the check and the lowering pass over (the expansion already happened)
ccl_cocolog_block(L, Text) :-
    tmp_file(cocolog, P0), atomic_list_concat([P0, '-', L, '.pl'], P),
    atom_codes(Text, Cs), write_file_from_codes(P, Cs),
    ccl_load_macros(P, _).
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
ccl_unit_note(unit(Is)) :- !, ccl_items_note(Is).                     % the bulk noter, library(ccl_syntax)
ccl_unit_note(partial(U, _, _)) :- !, ccl_unit_note(U).
ccl_unit_note(summary(F)) :- !, ccl_sum_note(F).
ccl_unit_note(_).


%% ... and the macros of a .pl
%% it is, or of any .pl a header under it includes (loaded here if need be)
ccl_include_macros(macros(_, _)) :- !.                 % registered by ccl_load_macros
ccl_include_macros(file(_, _, Unit)) :- !, ccl_unit_macros(Unit, Pairs), ccl_load_each(Pairs).
ccl_include_macros(_).
ccl_load_each([]).
ccl_load_each([P-_|T]) :- ccl_load_macros(P, _), ccl_load_each(T).
ccl_unit_macros(summary(_), []) :- !.                   % a summary carries no macro file
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
    ( How == unreadable -> true ; How == summary -> true ; ccl_lang(cpp), How == preprocessed -> true ; ccl_kb_remember(Path, included(How), Unit) ).
%% a preprocessed C++ header stays in the process: <cstdio> alone is 2700
%% items, and cocolog's store takes a writing process's rows at a cost that
%% follows their count, never reclaiming a dead one -- five minutes and 187 MB
%% for one include chain -- so the C++ system headers are read per run (a
%% bounded 30 s) until a summary cache replaces the AST cache for them

%% raw first; preprocessed only when raw does not read whole -- except a C++
%% library header, <cstdio> and kin: flattened by one run of the preprocessor
%% (library(ccl_pp), cocolog's own), its hundreds of includes resolved there,
%% and read once, as far as it reads; raw, each of those would be attempted,
%% failed and preprocessed in turn, ten minutes for <sstream>
ccl_read_unit(Path, How, Unit) :-
    ccl_lang(cpp), nb_getval('$ccl_inc_kind', system), !,
    nb_setval('$ccl_inc_kind', local),
    ccl_sum_file(Path, F),
    (   ccl_sum_valid(F) -> How = summary, Unit = summary(F)
    ;   ccl_pp_parse(Path, U1, Info1, Files), How = preprocessed, ccl_partial(U1, Info1, Unit),
        ( catch(ccl_sum_write(F, Path, Files, U1), _, fail) -> true ; true ) ).

%% ---- the summary cache: a C++ library header, once ----------------------------
%% What a header contributes downstream is its declarations -- the names and
%% types the noter collects: functions and globals, typedefs, tags with their
%% members (method bodies dropped), enumerators, template names, type names --
%% not its text. So a flattened library header is summarized to ONE FILE,
%% ~/.cicili/cpp/<name>-<fold>.sum, a term per line, keyed by the reader's
%% version and the time of every file the preprocessor pulled (a dep per
%% line, since a line past some tens of KB does not read back); the next run
%% loads the summary instead of preprocessing and reading forty thousand
%% lines. The include node is then
%% include(L, Spec, summary(File)), and every consumer of a unit -- the
%% parser's Env, the symbol table, the bulk noter, the driver's deps -- reads
%% the summary where it would have walked the unit. cocolog's store is not
%% involved: it cannot hold units this size (CLAUDE.md's findings).
ccl_sum_dir(D) :- ( catch(os_env('HOME', H), _, fail) -> true ; H = '/tmp' ), atom_concat(H, '/.cicili/cpp', D).
ccl_sum_file(Path, F) :-
    ccl_sum_dir(D), ccl_std(Std), atomic_list_concat([Path, '@', Std], Keyed), atom_codes(Keyed, Cs), ccl_fold(Cs, 7, 131, S1), ccl_fold(Cs, 13, 137, S2),   % one summary per level
    ( sub_atom(Path, B, _, 0, Base), sub_atom(Path, B1, 1, _, '/'), B1 < B, \+ sub_atom(Base, _, _, _, '/') -> true ; Base = Path ),
    atomic_list_concat([D, '/', Base, '-', S1, '-', S2, '.sum'], F).
ccl_fold([], S, _, S).
ccl_fold([C|Cs], S0, M, S) :- S1 is (S0 * M + C) mod 2147483647, ccl_fold(Cs, S1, M, S).
ccl_sum_valid(F) :-
    exists_file(F), ccl_sum_terms(F, [sum(_, key(V, cpp(S)))|Terms]), ccl_reader_version(V), ccl_std(S),
    findall(P-T, member(dep(P, T), Terms), Deps), Deps \== [], ccl_deps_hold(Deps).
ccl_deps_hold([]).
ccl_deps_hold([P-T|Ds]) :- once(catch(time_file(P, T1), _, fail)), T1 =:= T, ccl_deps_hold(Ds).
ccl_sum_write(F, Path, Files, unit(Is)) :-
    ccl_sum_dir(D), atomic_list_concat(['mkdir -p \'', D, '\''], Mk), once(catch(proc_run(Mk, 10000, _, _), _, true)),
    ( memberchk(Path, Files) -> Fs = Files ; Fs = [Path|Files] ), ccl_dep_times(Fs, Deps), ccl_reader_version(V),
    ccl_collect_items(Is, Ds, [], Ts, [], Gs, [], Es, []),
    ccl_items_typedefs(Is, Names0), ccl_tag_names(Gs, TagNames), append(Names0, TagNames, Names),
    ccl_items_templates(Is, Tmpls),
    ccl_std(S), ccl_sum_terms_out([sum(Path, key(V, cpp(S)))], Out0), ccl_sum_deps(Deps, Out0b), append(Out0, Out0b, Out1),   % a term per dep: a line stays short
    ccl_sum_decls(Ds, Out2), ccl_sum_typedefs(Ts, Out3), ccl_sum_tags(Gs, Out4), ccl_sum_enums(Es, Out5),
    ccl_sum_names(Names, Out6), ccl_sum_tmpls(Tmpls, Out7),
    ccl_concat_codes([Out1, Out2, Out3, Out4, Out5, Out6, Out7], Codes), write_file_from_codes(F, Codes), ccl_sum_forget(F),
    ccl_pp_macros(Ms), ccl_sum_mnames(Ms, Out8), ccl_sum_terms_out(Ms, Out9),   % the macros the run defined, for the user's file, beside it
    ccl_mac_file(F, M), append(Out8, Out9, MCodes), write_file_from_codes(M, MCodes).
ccl_sum_mnames([], []) :- !.
ccl_sum_mnames(Ms, Out) :- ccl_sum_mnames_(Ms, 100, Ns, Rest), ccl_sum_terms_out([mnames(Ns)], O1), ccl_sum_mnames(Rest, O2), append(O1, O2, Out).
ccl_sum_mnames_([], _, [], []) :- !.
ccl_sum_mnames_(Ms, 0, [], Ms) :- !.
ccl_sum_mnames_([macro(N, _, _)|Ms], K, [N|Ns], Rest) :- K1 is K - 1, ccl_sum_mnames_(Ms, K1, Ns, Rest).
ccl_sum_deps([], []).
ccl_sum_deps([P-T|Ds], Out) :- ccl_sum_terms_out([dep(P, T)], O1), ccl_sum_deps(Ds, O2), append(O1, O2, Out).
ccl_sum_decls([], []).
ccl_sum_decls([N-T|Ds], Out) :- ccl_sum_terms_out([decl(N, T)], O1), ccl_sum_decls(Ds, O2), append(O1, O2, Out).
ccl_sum_typedefs([], []).
ccl_sum_typedefs([N-T|Ds], Out) :- ccl_sum_terms_out([typedef(N, T)], O1), ccl_sum_typedefs(Ds, O2), append(O1, O2, Out).
ccl_sum_tags([], []).
ccl_sum_tags([Tag-Ms|Gs], Out) :- ccl_sum_slim(Ms, Ms1), ccl_sum_terms_out([tag(Tag, Ms1)], O1), ccl_sum_tags(Gs, O2), append(O1, O2, Out).
ccl_sum_enums([], []).
ccl_sum_enums([N-V|Es], Out) :- ccl_sum_terms_out([enum(N, V)], O1), ccl_sum_enums(Es, O2), append(O1, O2, Out).
ccl_sum_names([], []).
ccl_sum_names([N|Ns], Out) :- ccl_sum_terms_out([tname(N)], O1), ccl_sum_names(Ns, O2), append(O1, O2, Out).
ccl_sum_tmpls([], []).
ccl_sum_tmpls([N|Ns], Out) :- ccl_sum_terms_out([template(N)], O1), ccl_sum_tmpls(Ns, O2), append(O1, O2, Out).
%% a class's members without their bodies: what a type needs of them
ccl_sum_slim(none, none) :- !.
ccl_sum_slim([], []).
ccl_sum_slim([method(L, Q, R, N, Ps, V, _)|Ms], [method(L, Q, R, N, Ps, V, none)|Ms1]) :- !, ccl_sum_slim(Ms, Ms1).
ccl_sum_slim([ctor(L, Q, Ps, _, _)|Ms], [ctor(L, Q, Ps, [], none)|Ms1]) :- !, ccl_sum_slim(Ms, Ms1).
ccl_sum_slim([dtor(L, Q, _)|Ms], [dtor(L, Q, none)|Ms1]) :- !, ccl_sum_slim(Ms, Ms1).
ccl_sum_slim([template(L, Ps, M)|Ms], [template(L, Ps, M1)|Ms1]) :- !, ccl_sum_slim([M], [M1]), ccl_sum_slim(Ms, Ms1).
ccl_sum_slim([M|Ms], [M|Ms1]) :- ccl_sum_slim(Ms, Ms1).
ccl_sum_terms_out([], []).
ccl_sum_terms_out([T|Ts], Out) :- term_to_atom(T, A), atom_codes(A, Cs), append(Cs, [0'., 10], L1), ccl_sum_terms_out(Ts, O2), append(L1, O2, Out).
ccl_concat_codes([], []).
ccl_concat_codes([C|Cs], Out) :- ccl_concat_codes(Cs, O2), append(C, O2, Out).
ccl_tag_names([], []).
ccl_tag_names([Tag-_|Gs], Ns) :- ccl_tag_names(Gs, Ns1), ( atom(Tag), Tag \== anon -> Ns = [Tag|Ns1] ; Ns = Ns1 ).
ccl_items_templates([], []).
ccl_items_templates([template(_, _, I)|Is], Ns) :- !, ccl_items_templates(Is, Ns1), ( ccl_template_name(I, N), N \== none -> Ns = [N|Ns1] ; Ns = Ns1 ).
ccl_items_templates([namespace(_, _, Js)|Is], Ns) :- !, ccl_items_templates(Js, N1), ccl_items_templates(Is, N2), append(N1, N2, Ns).
ccl_items_templates([extern_c(_, Js)|Is], Ns) :- !, ccl_items_templates(Js, N1), ccl_items_templates(Is, N2), append(N1, N2, Ns).
ccl_items_templates([_|Is], Ns) :- ccl_items_templates(Is, Ns).
%% the files the preprocessor pulled, each with its time
ccl_dep_times([], []).
ccl_dep_times([F|Fs], Ds) :- ccl_dep_times(Fs, Ds1), ( once(catch(time_file(F, T), _, fail)) -> Ds = [F-T|Ds1] ; Ds = Ds1 ).
%% reading a summary: its terms, one per line; the four tables' lists. Parsed
%% ONCE per process (`'$ccl_sum:<F>'`): every consumer of an include --
%% the validity check, the Env, the symbol table, the bulk rebuild, the
%% driver's deps -- asks for the same terms, and a 600-line summary costs
%% 0.15 s to parse (the lines split by atomic_list_concat/3: ccl_split/3 on
%% the codes took 0.26 s by itself)
ccl_sum_terms(F, Terms) :-
    atom_concat('$ccl_sum:', F, K),
    (   catch(nb_getval(K, T0), _, fail), T0 \== none -> Terms = T0
    ;   read_file_to_codes(F, Codes), atom_codes(A, Codes), atomic_list_concat(Lines, '\n', A), ccl_sum_lines(Lines, Terms), nb_setval(K, Terms) ).
ccl_sum_forget(F) :- atom_concat('$ccl_sum:', F, K), nb_setval(K, none), nb_setval('$ccl_sumload:names', []).
ccl_sum_lines([], []).
ccl_sum_lines([L|Ls], Ts) :-                                                  % every position bound: a free one enumerates, 0.7 ms a line
    (   L == '' -> Ts = Ts1
    ;   atom_length(L, N), N1 is N - 1, sub_atom(L, N1, 1, 0, '.'), sub_atom(L, 0, N1, 1, A), catch(term_to_atom(T, A), _, fail) -> Ts = [T|Ts1]
    ;   Ts = Ts1 ),
    ccl_sum_lines(Ls, Ts1).
%% the macros beside the summary, <name>-<fold>.mac: the names by the hundred
%% (mnames lines, parsed), then a line per macro AS WRITTEN, parsed on its
%% first use -- 1200 come with <stdio.h>, 30 us each to parse, a file uses a
%% dozen. Read: the lines split, the mnames taken off the front, the rest raw.
ccl_mac_file(F, M) :- atom_length(F, N), N1 is N - 4, sub_atom(F, 0, N1, 4, B), atom_concat(B, '.mac', M).
ccl_mac_lines(M, Names, Raws) :-
    read_file_to_codes(M, Codes), atom_codes(A, Codes), atomic_list_concat(Lines, '\n', A),
    ccl_mac_names(Lines, Names, Raws0), ( append(Raws, [''], Raws0) -> true ; Raws = Raws0 ).
ccl_mac_names([L|Ls], Names, Raws) :-
    atom_length(L, N), N1 is N - 1, sub_atom(L, 0, 7, _, 'mnames('), sub_atom(L, 0, N1, 1, A), catch(term_to_atom(T, A), _, fail), T = mnames(Ns), !,   % a fresh T: term_to_atom compares a bound one
    ccl_mac_names(Ls, Names1, Raws), append(Ns, Names1, Names).
ccl_mac_names(Ls, [], Ls).
%% a summary's four tables, its templates and its names, split once per process
ccl_sum_load(F, D, T, G, E, Tmpls, Names) :-
    ccl_cached_named('$ccl_sumload:', F, sum(D, T, G, E, Tmpls, Names), ccl_sum_load_nocache(F, D, T, G, E, Tmpls, Names)).
ccl_sum_load_nocache(F, D, T, G, E, Tmpls, Names) :-
    ccl_sum_terms(F, Terms),
    findall(N-Ty, member(decl(N, Ty), Terms), D), findall(N-Ty, member(typedef(N, Ty), Terms), T),
    findall(Tag-Ms, member(tag(Tag, Ms), Terms), G), findall(N-V, member(enum(N, V), Terms), E),
    findall(N, member(template(N), Terms), Tmpls), findall(N, member(tname(N), Terms), Names).
%% a summary in the symbol table, as ccl_items_note puts a unit there
ccl_sum_note(F) :-
    ccl_sum_load(F, D, T, G, E, Tmpls, Names),
    ccl_scope_add(D),
    nb_getval('$ccl_typedefs', T0), append(T, T0, T1), nb_setval('$ccl_typedefs', T1),
    nb_getval('$ccl_tags', G0), append(G, G0, G1), nb_setval('$ccl_tags', G1), ccl_tables_changed,
    nb_getval('$ccl_enums', E0), append(E, E0, E1), nb_setval('$ccl_enums', E1),
    ccl_note_templates(Tmpls), ccl_add_envs(Names).
%% a summary's names into the templates and the Env in ONE read and one write
%% each: one at a time, every addition copied the whole list (nb_setval/2),
%% 190 names against 500 -- 15 ms of every rebuild of the symbol table
ccl_note_templates(Ns) :- nb_getval('$ccl_templates', Ts), ccl_new_names(Ns, Ts, New), ( New == [] -> true ; append(New, Ts, Ts1), nb_setval('$ccl_templates', Ts1) ).
ccl_add_envs(Ns) :- nb_getval('$ccl_env', G), ccl_new_names(Ns, G, New), ( New == [] -> true ; append(New, G, G1), nb_setval('$ccl_env', G1) ).
ccl_new_names([], _, []).
ccl_new_names([N|Ns], Have, New) :- ( atom(N), \+ memberchk(N, Have) -> New = [N|New1] ; New = New1 ), ccl_new_names(Ns, Have, New1).
ccl_read_unit(Path, How, Unit) :-
    ccl_parse_file(Path, U0, Info0),
    (   Info0 == whole -> How = raw, Unit = U0
    ;   ccl_pp_parse(Path, U1, Info1, Files) -> How = preprocessed, ccl_partial(U1, Info1, Unit), ccl_pp_macros(Ms), ccl_kb_remember_macros(Path, Files, Ms)
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

%% the file through the preprocessor (library(ccl_pp)): its directives run,
%% its includes pulled in, its macros expanded -- one token stream, read by
%% the same grammar; Files are every file it pulled, the includer first
ccl_pp_parse(Path, unit(Is), Info, Files) :-
    ccl_pp_file(Path, Tokens, Files),
    ccl_with_file(Path, ( ccl_unit(Tokens, unit(Is), Rest), ccl_rest_info(Rest, Info) )).

%% ---- a header's macros, for the user's file -----------------------------------
%% Made ready before the file's run (ccl_pp_prescan): the header read through
%% the reader's door -- its unit cached, its summary written -- then its macro
%% table from the summary (C++), the store ('$ccl_hmacros:<Path>' rows beside
%% the items, keyed like them), or one standalone run of the preprocessor
%% (a raw-read header, once per store); kept per process in '$ccl_hm:<Path>'.
ccl_header_macros_ready(Spec, From) :-
    (   ccl_resolve_include(Spec, From, Path), \+ sub_atom(Path, _, 3, 0, '.pl')
    ->  ccl_inc_kind(Spec, Kind), nb_setval('$ccl_inc_kind', Kind),
        ( ccl_include_read(Path, _) -> true ; true ),
        ( ccl_header_macros(Path, _) -> true ; true )
    ;   true ).
%% the table's kind: indexed (every name in '$ccl_hml:<Name>', Path-Def) or
%% store(Key) (answered by name from the rows); nothing of a header in neither
ccl_header_macros(Path, Kind) :-
    atom_concat('$ccl_hm:', Path, K),
    (   catch(nb_getval(K, K0), _, fail), K0 \== none -> Kind = K0
    ;   ccl_header_macros_(Path, Kind), nb_setval(K, Kind) ).
ccl_header_macros_known(Path, Kind) :- atom_concat('$ccl_hm:', Path, K), catch(nb_getval(K, Kind), _, fail), Kind \== none.
%% indexed: a summary's, as facts '$ccl_hml'(Name, Path, raw(Line)) -- an
%% assert is 2 us and the lookup by name 3 us, where a global per name cost
%% 25 us each for 1200 names; a fact is a store row under --embed, which the
%% C++ mode never runs over (cicili++ is --no-kb). store(Key): the rows.
%% list: a header the store would not take, its macros in a global, searched.
ccl_header_macros_(Path, indexed) :- ccl_lang(cpp), ccl_sum_file(Path, F), ccl_sum_valid(F), ccl_mac_file(F, M), exists_file(M), !, ccl_mac_lines(M, Names, Raws), dynamic('$ccl_hml'/3), ccl_hml_assert(Names, Raws, Path).
ccl_header_macros_(Path, store(K)) :- ccl_kb_macros_cached(Path, K), !.
ccl_header_macros_(Path, Kind) :-
    ccl_pp_file(Path, _, Files), ccl_pp_macros(Ms), ccl_kb_remember_macros(Path, Files, Ms),
    (   ccl_kb_macros_cached(Path, K) -> Kind = store(K)
    ;   atom_concat('$ccl_hmlist:', Path, KL), nb_setval(KL, Ms), Kind = list ).
ccl_hml_assert([], _, _) :- !.
ccl_hml_assert(_, [], _) :- !.
ccl_hml_assert([N|Ns], [R|Rs], Path) :- assertz('$ccl_hml'(N, Path, raw(R))), ccl_hml_assert(Ns, Rs, Path).
ccl_hml_list(Path, N, Ps, A) :- atom_concat('$ccl_hmlist:', Path, KL), nb_getval(KL, Ms), memberchk(macro(N, Ps, text(A)), Ms).
%% the store's rows for a header's macros: one predicate per header, as the
%% items, a row per macro under its NAME (the lookup is by name) and a dep row
%% per file of the closure under '$dep' (no identifier)
ccl_kb_hm_name(Path, F) :- atom_concat('$ccl_hmacros:', Path, F).
ccl_kb_hm(Path, F) :- ccl_kb_hm_name(Path, F), dynamic(F/3).
ccl_kb_macro(Path, K, N, Ps, A) :- ccl_kb_hm_name(Path, F), T =.. [F, N, K, macro(N, Ps, text(A))], once(T).
%% the deps -- every file of the header's closure, 38 for <stdio.h> -- are rows
%% too, dep(I), since one clause naming them all is over the store's budget
ccl_kb_remember_macros(Path, Files, Ms) :-
    ccl_kb_ready,
    (   ccl_kb_key(Path, K)
    ->  findall(P-PK, ( member(P, Files), ccl_kb_key(P, PK) ), Deps),
        retractall('$ccl_hmeta'(Path, _, _)), ccl_kb_hm(Path, F), T0 =.. [F, _, _, _], retractall(T0),
        (   catch(( ccl_kb_store_macros(Ms, F, K, 0, N), ccl_kb_store_deps(Deps, F, K, 0, ND), assertz('$ccl_hmeta'(Path, K, meta(N, ND))) ),
                  error(resource_error(clause_length), _), fail)
        ->  true
        ;   T1 =.. [F, _, _, _], retractall(T1), retractall('$ccl_hmeta'(Path, _, _)) )
    ;   true ).
ccl_kb_store_macros([], _, _, N, N).
ccl_kb_store_macros([macro(N, Ps, B)|Ms], F, K, C0, C) :- T =.. [F, N, K, macro(N, Ps, B)], assertz(T), C1 is C0 + 1, ccl_kb_store_macros(Ms, F, K, C1, C).
ccl_kb_store_deps([], _, _, N, N).
ccl_kb_store_deps([D|Ds], F, K, N0, N) :- T =.. [F, '$dep', K, D], assertz(T), N1 is N0 + 1, ccl_kb_store_deps(Ds, F, K, N1, N).   % one key for the dep rows: the store indexes an atom, not dep(I)
%% valid when the meta row is there under the header's key and every dep is at
%% its remembered time; the macro rows are not counted (a partial write was
%% retracted where it failed)
ccl_kb_macros_cached(Path, K) :-
    ccl_kb_ready, ccl_kb_key(Path, K), '$ccl_hmeta'(Path, K, meta(_, ND)), !,
    ccl_kb_hm(Path, F), TD =.. [F, '$dep', K, D], findall(D, TD, Deps), length(Deps, ND), ccl_kb_deps_fresh(Deps).

%% ---- the path ----------------------------------------------------------------
ccl_resolve_include(local(N), From, Path) :-
    From \== none, file_directory_name(From, Dir), atomic_list_concat([Dir, '/', N], P0), exists_file(P0), !, Path = P0.
ccl_resolve_include(Spec, _, Path) :-
    ( Spec = local(N) ; Spec = system(N) ),
    ccl_include_path(Dirs), member(D, Dirs), atomic_list_concat([D, '/', N], P), exists_file(P), !, Path = P.
ccl_resolve_include(next(Spec), From, Path) :-
    ( Spec = local(N) ; Spec = system(N) ),
    ccl_include_path(Dirs), ( ccl_dirs_after(Dirs, From, Rest) -> true ; Rest = Dirs ),
    member(D, Rest), atomic_list_concat([D, '/', N], P), exists_file(P), !, Path = P.
ccl_dirs_after([D|Ds], From, Ds) :- atom_concat(D, '/', DP), atom_concat(DP, Base, From), \+ sub_atom(Base, _, _, _, '/'), !.
ccl_dirs_after([_|Ds], From, Rest) :- ccl_dirs_after(Ds, From, Rest).

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
%% the toolchain's directories, in the order a compiler searches them, from
%% where the conventions put them -- no tool is run (owner's rule: the
%% embedded LLVM is the whole toolchain): the C++ library's headers first in
%% C++ ($LLVM, Homebrew's LLVM, else the SDK's own copy), then this compiler's
%% freestanding headers (library/include beside the grammars: stddef.h,
%% stdarg.h, stdbool.h, float.h ...), the local prefix, then the SDK
%% ($SDKROOT, the Command Line Tools' SDK, Xcode's) or /usr/include
ccl_toolchain_dirs(Ds) :-
    ( ccl_lang(cpp) -> ccl_cxx_dirs(Cxx) ; Cxx = [] ),
    ccl_own_include_dirs(Own), ccl_sdk_dirs(Sdk),
    append(Cxx, Own, D1), append(D1, ['/usr/local/include', '/opt/homebrew/include'], D2), append(D2, Sdk, D3),
    ccl_existing_dirs(D3, Ds).

%% ONE C++ library, the first found: two libc++ trees on the path mix their
%% wrappers (the SDK's ctype.h under LLVM's cctype defines _LIBCPP_CTYPE_H
%% and trips an #error)
ccl_cxx_dirs(Ds) :-
    ccl_llvm_roots(Rs), findall(D, ( member(R, Rs), atom_concat(R, '/include/c++/v1', D) ), D0), ccl_sdk_dirs(S), findall(D, ( member(Sd, S), atom_concat(Sd, '/c++/v1', D) ), D1), append(D0, D1, All),
    ( member(D, All), exists_directory(D) -> Ds = [D] ; Ds = [] ).
ccl_llvm_roots(Rs) :- ( catch(os_env('LLVM', L), _, fail), L \== '' -> Rs = [L, '/usr/local/opt/llvm', '/opt/homebrew/opt/llvm'] ; Rs = ['/usr/local/opt/llvm', '/opt/homebrew/opt/llvm'] ).
ccl_own_include_dirs(Ds) :- ccl_library_dirs(Ls), findall(D, ( member(L, Ls), atom_concat(L, '/include', D) ), Ds).
ccl_sdk_dirs(Ds) :-
    ( catch(os_env('SDKROOT', S), _, fail), S \== '' -> atom_concat(S, '/usr/include', D0), Ds = [D0|Ds1] ; Ds = Ds1 ),
    Ds1 = ['/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include',
           '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include',
           '/usr/include'].
ccl_existing_dirs([], []).
ccl_existing_dirs([D|Ds], Es) :- ccl_existing_dirs(Ds, Es1), ( exists_directory(D), \+ memberchk(D, Es1) -> Es = [D|Es1] ; Es = Es1 ).
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
ccl_unit_typedefs(summary(F), Ns) :- !, ccl_sum_load(F, _, _, _, _, _, Ns).           % a C++ library header's summary: its type names
ccl_unit_typedefs(_, []).
ccl_items_typedefs([], []).
ccl_items_typedefs([typedef(_, Ds)|T], Ns) :- !, ccl_declared_names(Ds, N1), ccl_items_typedefs(T, N2), append(N1, N2, Ns).
ccl_items_typedefs([include(_, _, R)|T], Ns) :- !, ccl_include_typedefs(R, [], N1), ccl_items_typedefs(T, N2), append(N1, N2, Ns).
ccl_items_typedefs([declare(_, base(_, [S]))|T], [N|Ns]) :- ccl_lang(cpp), ccl_cpp_type_name(S, N), !, ccl_items_typedefs(T, Ns).   % C++: a class's, a struct's, an enum class's name is a type name
ccl_items_typedefs([template(_, _, declare(_, base(_, [S])))|T], [N|Ns]) :- ccl_lang(cpp), ccl_cpp_type_name(S, N), !, ccl_items_typedefs(T, Ns).
ccl_items_typedefs([namespace(_, _, Js)|T], Ns) :- ccl_lang(cpp), !, ccl_items_typedefs(Js, N1), ccl_items_typedefs(T, N2), append(N1, N2, Ns).
ccl_items_typedefs([_|T], Ns) :- ccl_items_typedefs(T, Ns).
ccl_cpp_type_name(class(_, N, _, _), N) :- atom(N), N \== anon.
ccl_cpp_type_name(struct(N, _), N) :- atom(N), N \== anon.
ccl_cpp_type_name(enum_class(N, _), N) :- atom(N).

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
