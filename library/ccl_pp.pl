%% cicili-lang -- library(ccl_pp): the preprocessor, in cocolog. Owner's rule:
%% no clang and no LLVM binary, the embedded LLVM alone -- so what `clang -E'
%% did for a header the reader could not read raw is done here: the directives,
%% the conditional groups (#if with its constant expression, #ifdef, #elif,
%% #else, #endif), macro expansion (object-like and function-like, `#', `##',
%% __VA_ARGS__, hide sets against recursion, rescanning), #include and
%% #include_next resolved on the reader's own path, #pragma once, and the
%% built-ins a header asks (__has_include, __has_feature, __has_attribute,
%% __has_builtin ...). The target's predefined macros are data at the end of
%% this file, taken once from the reference compiler for both architectures
%% and for C++: the ABI's facts, no tool run.
%%
%%   ccl_pp_file(+Path, -Tokens, -Files)   Path preprocessed standalone -- the predefined
%%                                         macros and its own -- into the reader's tokens
%%                                         tok(Kind, Value, Line), and every file it pulled
%%   ccl_pp_macros(-Macros)                the macros defined when the last run ended,
%%                                         macro(Name, Params, Body), for a header's summary
%%
%% A file is worked LINE BY LINE: one pass strips its comments and joins its
%% continuations (pp_source/2, kept per process), then only the lines of the
%% groups taken are lexed, a false group being skipped by its `#' lines
%% alone, and a macro's body is lexed the first time it is used -- the SDK's
%% headers are mostly groups for other configurations and macros never
%% called. A header's own #error stops that file where it stands. An unknown
%% __has_feature, __has_attribute or __has_builtin answers 0, so a header
%% takes its plainest path, the one the reader reads best; __has_include is
%% answered for real. Every token a macro expands to carries the line of the
%% invocation.

%% ---- a run --------------------------------------------------------------------
ccl_pp_file(Path, Tokens, Files) :- ccl_pp_run(Path, no, Tokens, Files).
%% THE USER'S OWN FILE (Top = yes): its directives run and its macros expanded
%% like a header's, but an #include is passed on as the directive token for
%% the reader to resolve and read (the declarations come from the reader's
%% cache, the summaries and the store), with the header's MACROS loaded at
%% that point (ccl_header_macros/2 in ccl_include: from the summary, the
%% store, or one standalone run, made ready before this run begins, since a
%% run is not re-entrant); a #define or #undef is done and kept as a
%% directive item; a `#cocolog ... #end' block is the reader's, one token of
%% its raw lines; a `.pl' include is the reader's macro file. A line that
%% does not lex whole is the lexical error it always was.
ccl_pp_top(Path, Tokens, Files) :- ccl_pp_prescan(Path), ccl_pp_run(Path, yes, Tokens, Files).
ccl_pp_run(Path, Top, Tokens, Files) :-
    ccl_ensure_globals, pp_reset, nb_setval('$pp_top', Top),
    nb_setval('$ccl_hash', punct),                                                   % the run lexes in the preprocessor's mode: `#' a punctuator, a number as spelled
    ( once(catch(pp_include_file(Path, Out, []), E, true)) -> true ; E = failed ),
    nb_setval('$ccl_hash', line), nb_setval('$pp_top', no),
    ( var(E) -> true ; E == failed -> fail ; throw(E) ),
    pp_finish(Out, Tokens),
    nb_getval('$pp_files', Fs), reverse(Fs, Files).
%% the includes a file names, their headers read and their macros made ready
ccl_pp_prescan(Path) :- pp_source(Path, Lines), pp_prescan_lines(Lines, Path).
pp_prescan_lines([], _).
pp_prescan_lines([line(_, A)|Ls], Path) :-
    (   pp_directive_line(A, Body), pp_ws(Body, B1), pp_word(B1, W, Rest), atom_codes(D, W), ( D == include ; D == include_next ),
        pp_ws(Rest, R1), pp_inc_name(R1, Spec0)
    ->  ( D == include_next -> Spec = next(Spec0) ; Spec = Spec0 ), ( catch(ccl_header_macros_ready(Spec, Path), _, true) -> true ; true )
    ;   true ),
    pp_prescan_lines(Ls, Path).
%% the macros defined when the run ended, macro(Name, Params, text(Body)) --
%% the run's own, not the predefined: what a header's summary or store keeps
ccl_pp_macros(Macros) :-
    nb_getval('$pp_names', Ns), sort(Ns, Names), nb_getval('$pp_gen', G), pp_macro_terms(Names, G, Macros).
pp_macro_terms([], _, []).
pp_macro_terms([N|Ns], G, Ms) :-
    pp_macro_terms(Ns, G, Ms1),
    ( pp_key(N, K), catch(nb_getval(K, V), _, fail), V = mac(G, Ps, codes(Cs), _) -> atom_codes(A, Cs), Ms = [macro(N, Ps, text(A))|Ms1] ; Ms = Ms1 ).
%% a header's macros reach the run on their first use (pp_header_macro/3):
%% <stdio.h> brings 1200 and a file names a dozen

%% a run is a GENERATION: a macro is mac(Gen, Params, codes(Cs), Tokens), and
%% one from an earlier run is simply not this run's -- no walk undefines them
pp_reset :-
    ( catch(nb_getval('$pp_gen', G0), _, fail) -> G is G0 + 1 ; G = 1 ), nb_setval('$pp_gen', G),
    nb_setval('$pp_names', []), nb_setval('$pp_files', []), nb_setval('$pp_once', []), nb_setval('$pp_stack', []),
    nb_setval('$pp_counter', 0), nb_setval('$pp_errors', []), nb_setval('$pp_paste', no), nb_setval('$pp_top', no), nb_setval('$pp_hdrs', []), nb_setval('$pp_ninc', 0).
pp_key(N, K) :- atom_concat('$pp:', N, K).
%% a macro: its parameters (obj for an object-like one; va(N) the variadic
%% one) and its body -- the codes as defined, the tokens once used
pp_define(N, Ps, Cs) :- pp_set_macro(N, Ps, Cs), nb_getval('$pp_names', Ns), nb_setval('$pp_names', [N|Ns]).   % a name twice is harmless: sorted where read
pp_set_macro(N, Ps, Cs) :- nb_getval('$pp_gen', G), pp_key(N, K), nb_setval(K, mac(G, Ps, codes(Cs), none)).
pp_undefine(N) :- nb_getval('$pp_gen', G), pp_key(N, K), nb_setval(K, undef(G)).
%% a name's macro: this run's, or, in the user's file, one of its headers'
%% (the tables made ready before the run; '$pp_hdrs' the headers passed
%% through, the last first), defined into the run on that first use; one
%% undefined in this run stays so
pp_macro(N, Ps, Body) :- pp_key(N, K), nb_getval('$pp_gen', G), ( catch(nb_getval(K, V), _, fail) -> true ; V = none ), pp_macro_(V, G, N, K, Ps, Body).
pp_macro_(mac(G, Ps, C, T0), G, _, K, Ps, Body) :- !, ( T0 == none -> C = codes(Cs), pp_lex_body(Cs, Body), nb_setval(K, mac(G, Ps, C, Body)) ; Body = T0 ).
pp_macro_(undef(G), G, _, _, _, _) :- !, fail.
pp_macro_(nomac(G, I), G, _, _, _, _) :- nb_getval('$pp_ninc', I), !, fail.                 % a miss remembered, good until the next include
pp_macro_(_, G, N, K, Ps, Body) :- ( pp_outer_macro(N, Ps, Cs) -> pp_macro_(mac(G, Ps, codes(Cs), none), G, N, K, Ps, Body) ; pp_note_miss(K, G), fail ).
pp_note_miss(K, G) :- nb_getval('$pp_ninc', I), nb_setval(K, nomac(G, I)).
pp_defined(N) :- ( pp_builtin_name(N) -> true ; pp_key(N, K), nb_getval('$pp_gen', G), ( catch(nb_getval(K, V), _, fail) -> true ; V = none ), pp_defined_(V, G, N) ).
pp_defined_(mac(G, _, _, _), G, _) :- !.
pp_defined_(undef(G), G, _) :- !, fail.
pp_defined_(nomac(G, I), G, _) :- nb_getval('$pp_ninc', I), !, fail.
pp_defined_(_, G, N) :- ( pp_outer_macro(N, _, _) -> true ; pp_key(N, K), pp_note_miss(K, G), fail ).
%% a macro from outside the run, defined into it: a header's (the run's own
%% name list takes it, as a #define would) or a predefined one (never listed:
%% a header's table is the header's own)
pp_outer_macro(N, Ps, Cs) :-                                                       % the predefined first: no header redefines one
    (   pp_predef_macro(N, Ps, Cs) -> pp_set_macro(N, Ps, Cs)
    ;   pp_header_macro(N, Ps, Cs), pp_define(N, Ps, Cs) ).
pp_predef_macro(N, obj, Cs) :-
    (   ccl_lang(cpp), ccl_std(S), pp_std_table(S, Tab), pp_predef(N, Tab, T) -> true   % the level's own value first (__cplusplus, __cpp_constexpr ...)
    ;   pp_predef(N, any, T) -> true
    ;   pp_arch(A), pp_predef(N, A, T) -> true
    ;   ccl_lang(cpp), pp_predef(N, cpp, T) ),
    atom_codes(T, Cs).
%% the tables a level sees beyond cpp's (C++17's): the newest first
pp_std_table(S, cpp26) :- S >= 26.
pp_std_table(S, cpp23) :- S >= 23.
pp_std_table(S, cpp20) :- S >= 20.
%% the headers' tables, the last included first, by the table's kind
%% (ccl_header_macros/2): the summary's facts, the store's rows, or a list
pp_header_macro(N, Ps, Cs) :- nb_getval('$pp_hdrs', Hs), Hs \== [], pp_header_macro_(Hs, N, Ps, Cs).
pp_header_macro_([H|Hs], N, Ps, Cs) :-
    (   ccl_header_macros_known(H, Kind), pp_header_macro_in(Kind, H, N, Ps, A) -> atom_codes(A, Cs)
    ;   pp_header_macro_(Hs, N, Ps, Cs) ).
pp_header_macro_in(indexed, H, N, Ps, A) :- '$ccl_hml'(N, H, raw(L)), !, pp_raw_macro(L, N, Ps, A).
pp_header_macro_in(store(K), H, N, Ps, A) :- ccl_kb_macro(H, K, N, Ps, A).
pp_header_macro_in(list, H, N, Ps, A) :- ccl_hml_list(H, N, Ps, A).
pp_raw_macro(L, N, Ps, A) :-                                                       % the line as written, its `.' off; parsed into a FRESH term: term_to_atom given a bound one compares
    atom_length(L, Len), L1 is Len - 1, sub_atom(L, 0, L1, 1, A0), term_to_atom(T, A0), T = macro(N, Ps, text(A)).
pp_builtin_name(N) :- memberchk(N, ['__has_include', '__has_include_next', '__has_feature', '__has_extension', '__has_attribute', '__has_cpp_attribute',
    '__has_c_attribute', '__has_declspec_attribute', '__has_builtin', '__has_warning', '__is_identifier', '__building_module', '__FILE__', '__LINE__',
    '__COUNTER__', '__DATE__', '__TIME__', '__is_target_arch', '__is_target_vendor', '__is_target_os', '__is_target_environment']).

%% the predefined macros, pp_predef(Name, any | Arch | cpp, Text) at the end of
%% the file, are answered by name on a miss (pp_predef_macro/3): 580 of them,
%% defined at every run they cost 25 ms, and a file names ten
pp_arch(A) :-                                                                    % the module's compile-time arch; uname only without the module
    (   catch(nb_getval('$pp_arch', A0), _, fail) -> A = A0
    ;   once(catch(ccl_host_arch(A1), _, fail)) -> A = A1, nb_setval('$pp_arch', A)
    ;   ( once(catch(proc_run('uname -m', 5000, Out, _), _, fail)), atom_codes(A1, Out), sub_atom(A1, 0, _, _, arm) -> A = arm64 ; A = x86_64 ),
        nb_setval('$pp_arch', A) ).

%% ---- a file as lines --------------------------------------------------------------
%% line(N, Atom): a logical line -- continuations joined, comments gone (a
%% block comment's lines counted), strings and character constants kept as
%% they stand -- kept per process by path. The physical lines come from
%% atomic_list_concat/3, and only a line holding a slash or ending in a
%% backslash is walked code by code: a walk in cocolog costs about a
%% microsecond a character, and the SDK's closure of <stdio.h> is 700,000.
%% (sub_atom/5 with a free position enumerates, 150 us a call: a line is
%% tested through atom_codes/2 and memberchk/2, builtins both.)
pp_source(Path, Lines) :-
    atom_concat('$pp_src:', Path, K),
    (   catch(nb_getval(K, L0), _, fail), L0 \== none -> Lines = L0
    ;   ( catch(read_file_to_codes(Path, Codes), _, fail) -> atom_codes(A, Codes), atomic_list_concat(Phys, '\n', A), pp_lines(Phys, 1, out, Lines) ; Lines = [] ),
        nb_setval(K, Lines) ).
pp_lines([], _, _, []).
pp_lines([P|Ps], N, in, Lines) :- !,                                              % inside a block comment: to its end
    (   atom_codes(P, Cs), pp_close(Cs, R1) -> atom_codes(Rest, R1), pp_lines([Rest|Ps], N, out, Lines)
    ;   N1 is N + 1, pp_lines(Ps, N1, in, Lines) ).
pp_lines([P|Ps], N, out, Lines) :-
    atom_codes(P, Cs),
    (   \+ memberchk(47, Cs), \+ pp_ends_backslash(P) -> Lines = [line(N, P)|Lines1], N1 is N + 1, St1 = out, Ps1 = Ps
    ;   pp_join(Cs, P, Ps, N, Joined, Ps1, N1), pp_clean(Joined, Out, St1),
        atom_codes(OA, Out), Lines = [line(N, OA)|Lines1] ),
    pp_lines(Ps1, N1, St1, Lines1).
pp_ends_backslash(P) :- atom_length(P, L), L > 0, L1 is L - 1, sub_atom(P, L1, 1, 0, '\\').
%% a line ending in a backslash continues on the next
pp_join(Cs, P, Ps, N, Joined, Ps1, N1) :-
    (   pp_ends_backslash(P), Ps = [Q|Qs] -> append(C1, [92], Cs), !, N0 is N + 1, atom_codes(Q, QCs), pp_join(QCs, Q, Qs, N0, J1, Ps1, N1), append(C1, J1, Joined)
    ;   Joined = Cs, Ps1 = Ps, N1 is N + 1 ).
%% one line's codes without its comments; `in' when a block comment stays open
pp_clean([], [], out).
pp_clean([C|R], Out, St) :- pp_cc(C, R, Out, St).
pp_cc(47, [47|_], [], out) :- !.
pp_cc(47, [42|R], [32|Out], St) :- !, ( pp_close(R, R1) -> pp_clean(R1, Out, St) ; Out = [], St = in ).
pp_cc(34, R, [34|Out], St) :- !, pp_quoted(R, 34, R1, S), pp_clean(R1, Out1, St), append(S, Out1, Out).
pp_cc(39, R, [39|Out], St) :- !, pp_quoted(R, 39, R1, S), pp_clean(R1, Out1, St), append(S, Out1, Out).
pp_cc(C, R, [C|Out], St) :- pp_clean(R, Out, St).
pp_close([42, 47|R], R) :- !.
pp_close([_|R], R1) :- pp_close(R, R1).
pp_quoted([], _, [], []) :- !.
pp_quoted([Q|R], Q, R, [Q]) :- !.
pp_quoted([92, C|R], Q, R1, [92, C|S]) :- !, pp_quoted(R, Q, R1, S).
pp_quoted([C|R], Q, R1, [C|S]) :- pp_quoted(R, Q, R1, S).
%% a directive line: `#' first, blanks before it allowed; Body the codes after
%% it (atom_codes/2 and a walk over the blanks: sub_atom/5 costs 70 us here)
pp_directive_line(A, Body) :- atom_codes(A, Cs), pp_ws(Cs, [35|Body]).
%% a text line's tokens, at its line; a macro body or a directive's tail --
%% all in the preprocessor's mode: `#' and `##' punctuators, a number as spelled
pp_lex_line(N, A, Toks) :-
    (   ccl_lex_atom(A, N, T, Rest) -> Toks = T, ( Rest \== [], nb_getval('$pp_top', yes) -> throw(lexical(N)) ; true )
    ;   Toks = [] ).
pp_lex_body(Codes, Toks) :- atom_codes(A, Codes), ( ccl_lex_atom(A, 0, T, _) -> Toks = T ; Toks = [] ).

%% ---- the run: files, lines, tokens ----------------------------------------------
%% a file whose whole text is one `#ifndef X ... #endif' with X defined by
%% its end is guarded: a later #include of it, X still defined, is nothing --
%% the SDK's headers include sys/cdefs.h ten times over, 760 lines each
pp_include_file(Path, Out0, Out) :-
    nb_getval('$pp_files', Fs), ( memberchk(Path, Fs) -> true ; nb_setval('$pp_files', [Path|Fs]) ),
    nb_getval('$pp_stack', St), length(St, Depth),
    (   Depth > 120 -> Out0 = Out
    ;   pp_guarded(Path) -> Out0 = Out
    ;   pp_source(Path, Lines), nb_setval('$pp_stack', [Path|St]),
        pp_run(Lines, Out0, Out),
        nb_getval('$pp_stack', [_|St1]), nb_setval('$pp_stack', St1),
        pp_note_guard(Path, Lines) ).
pp_guarded(Path) :- atom_concat('$pp_guard:', Path, K), catch(nb_getval(K, G), _, fail), G \== none, pp_defined(G).
pp_note_guard(Path, Lines) :-
    atom_concat('$pp_guard:', Path, K),
    (   catch(nb_getval(K, _), _, fail) -> true
    ;   Lines = [line(_, First)|_], pp_directive_line(First, B), pp_ws(B, B1), pp_word(B1, W, R), atom_codes(ifndef, W),
        pp_ws(R, R1), pp_word(R1, GW, _), GW \== [], atom_codes(G, GW), pp_defined(G),
        pp_last(Lines, line(_, Last)), pp_directive_line(Last, LB), pp_ws(LB, LB1), pp_word(LB1, LW, _), atom_codes(endif, LW)
    ->  nb_setval(K, G)
    ;   nb_setval(K, none) ).
pp_last([X], X) :- !.
pp_last([_|Xs], X) :- pp_last(Xs, X).
pp_current_file(F) :- nb_getval('$pp_stack', [F|_]), !.
pp_current_file(none).
pp_run([], Out, Out).
pp_run([line(N, A)|Ls], Out0, Out) :-
    (   pp_directive_line(A, Body) -> pp_directive(Body, N, Ls, Ls1, Out0, Out1), pp_run(Ls1, Out1, Out)
    ;   pp_lex_line(N, A, Toks), pp_toks(Toks, Ls, Ls1, Out0, Out1), pp_run(Ls1, Out1, Out) ).
%% the stream: tokens, or h(Token, HideSet) from an expansion
pp_unwrap(h(T, HS), T, HS) :- !.
pp_unwrap(T, T, []).
pp_strip([], []).
pp_strip([X|Xs], [T|Ts]) :- pp_unwrap(X, T, _), pp_strip(Xs, Ts).
%% the tokens of a line (or of an argument), expanded into the output; a
%% function-like macro's arguments may run on to the following lines, pulled
%% as needed
pp_toks([], Ls, Ls, Out, Out).
pp_toks([X|Xs], Ls, Ls1, Out0, Out) :-
    pp_unwrap(X, T, HS),
    (   T = tok(id, '_Pragma', _), pp_pragma_op(Xs, Ls, Xs1, Ls2) -> pp_toks(Xs1, Ls2, Ls1, Out0, Out)          % _Pragma("...") is a #pragma: nothing
    ;   T = tok(K, N, L), ( K == id ; K == kw ), \+ memberchk(N, HS), pp_expand(N, L, HS, Xs, Ls, Xs1, Ls2) -> pp_toks(Xs1, Ls2, Ls1, Out0, Out)
    ;   Out0 = [T|Out1], pp_toks(Xs, Ls, Ls1, Out1, Out) ).
%% its operand, the parenthesized group as it stands -- a macro's #x is still unexpanded there
pp_pragma_op(Xs, Ls, Rest, Ls1) :- pp_paren_next(Xs, Ls, Xs0, Ls0), pp_collect_args(Xs0, Ls0, _, Rest, Ls1).
%% a name that is a macro: its expansion, hidden from itself, pushed back for the rescan
pp_expand(N, L, HS, Xs, Ls, Xs1, Ls) :- pp_builtin_obj(N, L, Body), !, pp_wrap(Body, [N|HS], L, W), append(W, Xs, Xs1).
pp_expand(N, L, HS, Xs, Ls, Xs1, Ls1) :-
    pp_macro(N, Ps, Body),
    (   Ps == obj -> pp_wrap(Body, [N|HS], L, W), append(W, Xs, Xs1), Ls1 = Ls
    ;   pp_paren_next(Xs, Ls, Xs0, Ls0) -> pp_collect_args(Xs0, Ls0, Args0, Rest, Ls1), pp_fit_args(Ps, Args0, Args), pp_subst(Body, Ps, Args, Subst), pp_wrap(Subst, [N|HS], L, W), append(W, Rest, Xs1) ).
pp_builtin_obj('__LINE__', L, [tok(int, L, L)]).
pp_builtin_obj('__FILE__', L, [tok(str, Cs, L)]) :- pp_current_file(F), atom_codes(F, Cs).
pp_builtin_obj('__COUNTER__', L, [tok(int, C, L)]) :- nb_getval('$pp_counter', C), C1 is C + 1, nb_setval('$pp_counter', C1).
pp_builtin_obj('__DATE__', L, [tok(str, Cs, L)]) :- atom_codes('Jan  1 2026', Cs).
pp_builtin_obj('__TIME__', L, [tok(str, Cs, L)]) :- atom_codes('00:00:00', Cs).
pp_wrap([], _, _, []).
pp_wrap([T|Ts], HS, L, [h(T1, HS)|Ws]) :- pp_reline(T, L, T1), pp_wrap(Ts, HS, L, Ws).
pp_reline(tok(K, V, _), L, tok(K, V, L)).
%% `(' next -- on this line, or on the next text line
pp_paren_next([X|Xs], Ls, [X|Xs], Ls) :- pp_unwrap(X, tok(p, '(', _), _), !.
pp_paren_next([], Ls, Xs, Ls1) :- pp_pull(Ls, Xs, Ls1), Xs = [X|_], pp_unwrap(X, tok(p, '(', _), _).
pp_pull([line(N, A)|Ls], Toks, Ls) :- \+ pp_directive_line(A, _), pp_lex_line(N, A, Toks).
%% the arguments: balanced, split at the commas of depth one; an argument keeps its wrappers
pp_collect_args([_|Xs], Ls, Args, Rest, Ls1) :- pp_args(Xs, Ls, 1, [], [], Args, Rest, Ls1).
pp_args([], Ls, D, Cur, Acc, Args, Rest, Ls1) :- pp_pull(Ls, Toks, Ls0), !, pp_args(Toks, Ls0, D, Cur, Acc, Args, Rest, Ls1).
pp_args([], Ls, _, Cur, Acc, Args, [], Ls) :- !, reverse(Cur, A), reverse([A|Acc], Args).          % a directive, or the file's end: the arguments close here
pp_args([X|Xs], Ls, D, Cur, Acc, Args, Rest, Ls1) :-
    pp_unwrap(X, T, _),
    (   T = tok(p, '(', _) -> D1 is D + 1, pp_args(Xs, Ls, D1, [X|Cur], Acc, Args, Rest, Ls1)
    ;   T = tok(p, ')', _), D =:= 1 -> reverse(Cur, A), reverse([A|Acc], Args), Rest = Xs, Ls1 = Ls
    ;   T = tok(p, ')', _) -> D1 is D - 1, pp_args(Xs, Ls, D1, [X|Cur], Acc, Args, Rest, Ls1)
    ;   T = tok(p, ',', _), D =:= 1 -> reverse(Cur, A), pp_args(Xs, Ls, D, [], [A|Acc], Args, Rest, Ls1)
    ;   pp_args(Xs, Ls, D, [X|Cur], Acc, Args, Rest, Ls1) ).
%% as many arguments as parameters: `f()' for no parameter is none; the rest to the variadic one
pp_fit_args([], [[]], []) :- !.
pp_fit_args(Ps, Args, Args1) :-
    length(Ps, NP), ( append(_, [va(_)], Ps) -> NF is NP - 1, pp_split_at(NF, Args, Fixed, Va), pp_join_commas(Va, VaArg), append(Fixed, [VaArg], Args1) ; Args1 = Args ).
pp_split_at(0, As, [], As) :- !.
pp_split_at(N, [A|As], [A|Fs], Va) :- !, N1 is N - 1, pp_split_at(N1, As, Fs, Va).
pp_split_at(N, [], Fs, []) :- N1 is N - 1, ( N1 >= 0 -> pp_split_at(N1, [], Fs0, _), Fs = [[]|Fs0] ; Fs = [] ).
pp_join_commas([], []).
pp_join_commas([A], A) :- !.
pp_join_commas([A|As], J) :- pp_join_commas(As, J1), append(A, [tok(p, ',', 0)|J1], J).
%% substitution: a parameter by its argument -- expanded, unless `#' stringizes
%% it or `##' pastes it -- then the pastes
pp_subst(Body, Ps, Args, Out) :- pp_subst_(Body, Ps, Args, S0), pp_paste(S0, Out).
pp_subst_([], _, _, []).
pp_subst_([tok(p, '#', L), tok(K, P, _)|Bs], Ps, Args, [tok(str, Cs, L)|Out]) :- ( K == id ; K == kw ), pp_param(P, Ps, Args, Arg), !, pp_stringize(Arg, Cs), pp_subst_(Bs, Ps, Args, Out).
pp_subst_([tok(K, P, L)|Bs], Ps, Args, Out) :- ( K == id ; K == kw ), pp_param(P, Ps, Args, Arg), !,
    (   ( Bs = [tok(p, '##', _)|_] ; pp_last_was_paste ) -> pp_strip(Arg, Raw), pp_reline_all(Raw, L, Ins),
        ( Ins == [], memberchk(va(P), Ps) -> Out = [vamarker|Out1] ; Ins == [] -> Out = [placemarker|Out1] ; append(Ins, Out1, Out) )
    ;   pp_expand_all(Arg, Exp), pp_reline_all(Exp, L, Ins), append(Ins, Out1, Out) ),
    nb_setval('$pp_paste', no), pp_subst_(Bs, Ps, Args, Out1).
pp_subst_([tok(p, '##', L)|Bs], Ps, Args, [tok(p, '##', L)|Out]) :- !, nb_setval('$pp_paste', yes), pp_subst_(Bs, Ps, Args, Out).
pp_subst_([T|Bs], Ps, Args, [T|Out]) :- nb_setval('$pp_paste', no), pp_subst_(Bs, Ps, Args, Out).
pp_last_was_paste :- nb_getval('$pp_paste', yes).
pp_param(P, Ps, Args, Arg) :- Ps \== obj, pp_param_index(Ps, P, 0, I), nth0(I, Args, Arg).
pp_param_index([va(P)|_], P, I, I) :- !.
pp_param_index([P|_], P, I, I) :- !.
pp_param_index([_|Ps], P, I0, I) :- I1 is I0 + 1, pp_param_index(Ps, P, I1, I).
pp_reline_all([], _, []).
pp_reline_all([T|Ts], L, [T1|Ts1]) :- pp_reline(T, L, T1), pp_reline_all(Ts, L, Ts1).
%% a token list of its own, expanded whole (an argument, an #if line)
pp_expand_all(Toks, Out) :- pp_toks(Toks, [], _, Out0, []), pp_strip(Out0, Out).
%% `##': the two sides spelled together and read as one token (or as they come)
pp_paste([], []).
pp_paste([tok(p, ',', _), tok(p, '##', _), vamarker|Ts], Out) :- !, pp_paste(Ts, Out).     % GNU's `, ## __VA_ARGS__' with none: the comma goes
pp_paste([A, tok(p, '##', _), B|Ts], Out) :- !, pp_paste_two(A, B, AB), append(AB, Ts, Ts1), pp_paste(Ts1, Out).
pp_paste([placemarker|Ts], Out) :- !, pp_paste(Ts, Out).
pp_paste([vamarker|Ts], Out) :- !, pp_paste(Ts, Out).
pp_paste([T|Ts], [T|Out]) :- pp_paste(Ts, Out).
pp_paste_two(placemarker, B, [B]) :- !.
pp_paste_two(A, placemarker, [A]) :- !.
pp_paste_two(vamarker, B, [B]) :- !.
pp_paste_two(A, vamarker, [A]) :- !.
pp_paste_two(A, B, Toks) :- pp_spell(A, Ca), pp_spell(B, Cb), append(Ca, Cb, C), pp_lex_body(C, T0), ( T0 = [_|_], arg(3, A, L) -> pp_reline_all(T0, L, Toks) ; Toks = [A, B] ).
pp_stringize(Arg, Cs) :- pp_strip(Arg, Raw), pp_spell_all(Raw, Cs0), pp_escape(Cs0, Cs).
pp_spell_all([], []).
pp_spell_all([T], Cs) :- !, pp_spell(T, Cs).
pp_spell_all([T|Ts], Cs) :- pp_spell(T, C1), pp_spell_all(Ts, C2), append(C1, [0' |C2], Cs).
pp_spell(tok(id, N, _), Cs) :- !, atom_codes(N, Cs).
pp_spell(tok(kw, N, _), Cs) :- !, atom_codes(N, Cs).
pp_spell(tok(num, Cs, _), Cs) :- !.
pp_spell(tok(int, N, _), Cs) :- !, number_codes(N, Cs).
pp_spell(tok(float, N, _), Cs) :- !, number_codes(N, Cs).
pp_spell(tok(str, S, _), Cs) :- !, pp_escape(S, E), append([34|E], [34], Cs).
pp_spell(tok(chr, C, _), [39, C, 39]) :- !.
pp_spell(tok(p, P, _), Cs) :- !, atom_codes(P, Cs).
pp_spell(tok(_, V, _), Cs) :- ( atom(V) -> atom_codes(V, Cs) ; number(V) -> number_codes(V, Cs) ; Cs = [] ).
pp_spell(_, []).
pp_escape([], []).
pp_escape([34|Cs], [92, 34|Es]) :- !, pp_escape(Cs, Es).
pp_escape([92|Cs], [92, 92|Es]) :- !, pp_escape(Cs, Es).
pp_escape([10|Cs], [92, 0'n|Es]) :- !, pp_escape(Cs, Es).
pp_escape([C|Cs], [C|Es]) :- pp_escape(Cs, Es).
%% the output: bare tokens, a number from a macro body read as the reader has it
pp_finish([], []).
pp_finish([X|Xs], [T|Ts]) :- pp_unwrap(X, T0, _), pp_norm(T0, T), pp_finish(Xs, Ts).
pp_norm(tok(num, Cs, L), tok(int, V, L)) :- pp_plain_int(Cs), !, number_codes(V, Cs).   % a plain decimal, most of them: no lexer run
pp_norm(tok(num, Cs, L), T) :- !, nb_getval('$ccl_hash', M), nb_setval('$ccl_hash', line), atom_codes(A, Cs), ( ccl_lex_atom(A, 0, [tok(K, V, _)], []) -> T = tok(K, V, L) ; T = tok(int, 0, L) ), nb_setval('$ccl_hash', M).
pp_norm(T, T).

%% ---- directives -------------------------------------------------------------
pp_directive(Body, L, Ls, Ls1, Out0, Out) :-
    pp_ws(Body, B1), pp_word(B1, W, Rest), atom_codes(D, W),
    pp_directive_(D, Rest, Body, L, Ls, Ls1, Out0, Out).
pp_directive_(define, Rest, Body, L, Ls, Ls, Out0, Out) :- !, ( pp_do_define(Rest) -> true ; true ), pp_pass(Body, L, Out0, Out).
pp_directive_(undef, Rest, Body, L, Ls, Ls, Out0, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), pp_undefine(N), pp_pass(Body, L, Out0, Out).
pp_directive_(include, Rest, Body, L, Ls, Ls, Out0, Out) :- !, pp_do_include(Rest, plain, Body, L, Out0, Out).
pp_directive_(include_next, Rest, Body, L, Ls, Ls, Out0, Out) :- !, pp_do_include(Rest, next, Body, L, Out0, Out).
pp_directive_(cocolog, _, _, L, Ls, Ls1, Out0, Out) :- nb_getval('$pp_top', yes), !, pp_cocolog_block(Ls, L, Ls1, Out0, Out).
%% in the user's file a directive is kept as the token the reader has always read
pp_pass(Body, L, Out0, Out) :- ( nb_getval('$pp_top', yes) -> atom_codes(Text, [35|Body]), Out0 = [tok(pp, Text, L)|Out] ; Out0 = Out ).
%% #cocolog ... #end in the user's file: the raw lines between, one token
pp_cocolog_block(Ls, L, Ls1, [tok(cocolog, Text, L)|Out], Out) :-
    pp_block_end(Ls, L, EndN, Ls1), pp_current_file(F), pp_raw_lines(F, Raw), From is L + 1, To is EndN - 1,
    pp_raw_slice(Raw, 1, From, To, Cs), atom_codes(Text, Cs).
pp_block_end([], L, E, []) :- E is L + 1000000.
pp_block_end([line(N, A)|Ls], L, EndN, Ls1) :-
    (   pp_directive_line(A, Body), pp_ws(Body, B1), pp_word(B1, W, _), atom_codes(end, W) -> EndN = N, Ls1 = Ls
    ;   pp_block_end(Ls, L, EndN, Ls1) ).
pp_raw_lines(F, Raw) :- read_file_to_codes(F, Codes), atom_codes(A, Codes), atomic_list_concat(Raw, '\n', A).
pp_raw_slice([], _, _, _, []).
pp_raw_slice([R|Rs], N, From, To, Cs) :-
    N1 is N + 1,
    (   N >= From, N =< To -> atom_codes(R, C1), append(C1, [10|C2], Cs), pp_raw_slice(Rs, N1, From, To, C2)
    ;   N > To -> Cs = []
    ;   pp_raw_slice(Rs, N1, From, To, Cs) ).
pp_directive_(if, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_lex_body(Rest, Ts), ( pp_eval(Ts) -> Ls1 = Ls ; pp_skip_false(Ls, Ls1) ).
pp_directive_(ifdef, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), ( pp_defined(N) -> Ls1 = Ls ; pp_skip_false(Ls, Ls1) ).
pp_directive_(ifndef, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), ( pp_defined(N) -> pp_skip_false(Ls, Ls1) ; Ls1 = Ls ).
pp_directive_(elif, _, _, _, Ls, Ls1, Out, Out) :- !, pp_skip_to_endif(Ls, Ls1).          % a taken group ended: the branches left go
pp_directive_(elifdef, _, _, _, Ls, Ls1, Out, Out) :- !, pp_skip_to_endif(Ls, Ls1).       % C++23 (and C23): #elifdef X, #elifndef X
pp_directive_(elifndef, _, _, _, Ls, Ls1, Out, Out) :- !, pp_skip_to_endif(Ls, Ls1).
pp_directive_(else, _, _, _, Ls, Ls1, Out, Out) :- !, pp_skip_to_endif(Ls, Ls1).
pp_directive_(endif, _, _, _, Ls, Ls, Out, Out) :- !.
pp_directive_(pragma, Rest, _, _, Ls, Ls, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), ( atom_codes(once, W) -> pp_current_file(F), nb_getval('$pp_once', O), nb_setval('$pp_once', [F|O]) ; true ).
pp_directive_(error, Rest, _, L, _, [], Out, Out) :- !, pp_current_file(F), atom_codes(M, Rest), nb_getval('$pp_errors', Es), nb_setval('$pp_errors', [error(F, L, M)|Es]).   % the file stops here
pp_directive_(_, _, _, _, Ls, Ls, Out, Out).                                       % line, warning, ident, an empty #: nothing
pp_ws([C|Cs], R) :- ( C =:= 32 ; C =:= 9 ), !, pp_ws(Cs, R).
pp_ws(Cs, Cs).
pp_word([C|Cs], [C|W], R) :- ( C >= 0'a, C =< 0'z ; C >= 0'A, C =< 0'Z ; C =:= 0'_ ; C >= 0'0, C =< 0'9 ), !, pp_word(Cs, W, R).
pp_word(Cs, [], Cs).
%% #define NAME body | #define NAME(params) body -- function-like when `(' follows the name at once
pp_do_define(Rest) :-
    pp_ws(Rest, R1), pp_word(R1, W, R2), W \== [], atom_codes(N, W),
    (   R2 = [0'(|R3] -> pp_upto_close(R3, PCs, R4), pp_param_names(PCs, Ps), pp_define(N, Ps, R4)
    ;   pp_define(N, obj, R2) ).
pp_upto_close([0')|R], [], R) :- !.
pp_upto_close([C|Cs], [C|Ps], R) :- pp_upto_close(Cs, Ps, R).
pp_upto_close([], [], []).
pp_param_names(Cs, Ps) :- ccl_split(Cs, 0',, Parts), pp_param_names_(Parts, Ps).
pp_param_names_([], []).
pp_param_names_([P|Ps], Names) :-
    pp_ws(P, P1), pp_word(P1, W, R), pp_ws(R, R1), pp_param_names_(Ps, Ns),
    (   W == [], R1 = [0'., 0'., 0'.|_] -> Names = [va('__VA_ARGS__')|Ns]
    ;   W == [] -> Names = Ns
    ;   R1 = [0'., 0'., 0'.|_] -> atom_codes(A, W), Names = [va(A)|Ns]
    ;   atom_codes(A, W), Names = [A|Ns] ).
%% #include: the name as written, or through the macros; resolved on the
%% reader's path from the including file; once per #pragma once; a `.pl'
%% is a macro file, the reader's own: the directive is passed on as a token
pp_do_include(Rest, How, Body, L, Out0, Out) :-
    pp_ws(Rest, R1),
    (   pp_inc_name(R1, Spec0) -> true
    ;   pp_lex_body(R1, Ts), pp_expand_all(Ts, Es), pp_spell_all(Es, ECs), pp_inc_name(ECs, Spec0) ),
    !,
    ( How == next -> Spec = next(Spec0) ; Spec = Spec0 ),
    pp_current_file(From),
    (   ccl_resolve_include(Spec, From, Path)
    ->  (   sub_atom(Path, _, 3, 0, '.pl') -> atom_codes(Text, [35|Body]), Out0 = [tok(pp, Text, L)|Out]
        ;   nb_getval('$pp_top', yes) -> atom_codes(Text, [35|Body]), Out0 = [tok(pp, Text, L)|Out],
                                        ( ccl_header_macros_known(Path, _) -> nb_getval('$pp_hdrs', Hs), nb_setval('$pp_hdrs', [Path|Hs]), nb_getval('$pp_ninc', I0), I1 is I0 + 1, nb_setval('$pp_ninc', I1) ; true )
        ;   nb_getval('$pp_once', O), memberchk(Path, O) -> Out0 = Out
        ;   pp_include_file(Path, Out0, Out) )
    ;   nb_getval('$pp_top', yes) -> atom_codes(Text, [35|Body]), Out0 = [tok(pp, Text, L)|Out]      % nowhere: the reader says `missing'
    ;   Out0 = Out ).
pp_do_include(_, _, _, _, Out, Out).
pp_inc_name([34|R], local(N)) :- pp_upto(R, 34, Cs), atom_codes(N, Cs).
pp_inc_name([0'<|R], system(N)) :- pp_upto(R, 0'>, Cs), atom_codes(N, Cs).
pp_upto([End|_], End, []) :- !.
pp_upto([C|Cs], End, [C|Rs]) :- pp_upto(Cs, End, Rs).
%% a false group: past its lines to the branch that follows, and that branch's fate
pp_skip_false(Ls, Ls1) :-
    pp_skip_group(Ls, 0, Found, Rest),
    (   Found = elif(Ts) -> ( pp_eval(Ts) -> Ls1 = Rest ; pp_skip_false(Rest, Ls1) )
    ;   Ls1 = Rest ).                                                             % else, endif, or the end of the file
pp_skip_group([], _, endif, []).
pp_skip_group([line(_, A)|Ls], D, Found, Rest) :-
    (   pp_directive_line(A, Body), pp_ws(Body, B1), pp_word(B1, W, R), atom_codes(Dn, W), pp_cond_word(Dn, Kind)
    ->  (   Kind == open -> D1 is D + 1, pp_skip_group(Ls, D1, Found, Rest)
        ;   Kind == endif, D =:= 0 -> Found = endif, Rest = Ls
        ;   Kind == endif -> D1 is D - 1, pp_skip_group(Ls, D1, Found, Rest)
        ;   D =:= 0, Kind == elif -> pp_lex_body(R, Ts), Found = elif(Ts), Rest = Ls
        ;   D =:= 0, Kind == elifdef -> pp_defined_body('defined(', R, Ts), Found = elif(Ts), Rest = Ls      % C++23: as #elif defined(X)
        ;   D =:= 0, Kind == elifndef -> pp_defined_body('!defined(', R, Ts), Found = elif(Ts), Rest = Ls
        ;   D =:= 0 -> Found = else, Rest = Ls
        ;   pp_skip_group(Ls, D, Found, Rest) )
    ;   pp_skip_group(Ls, D, Found, Rest) ).
pp_cond_word(if, open). pp_cond_word(ifdef, open). pp_cond_word(ifndef, open).
pp_cond_word(elif, elif). pp_cond_word(else, else). pp_cond_word(endif, endif).
pp_cond_word(elifdef, elifdef). pp_cond_word(elifndef, elifndef).
pp_defined_body(Head, R, Ts) :- atom_codes(Head, H), pp_ws(R, R1), pp_word(R1, W, _), append(H, W, C0), append(C0, [0')], Cs), pp_lex_body(Cs, Ts).
pp_skip_to_endif(Ls, Ls1) :- pp_skip_group(Ls, 0, Found, Rest), ( Found = elif(_) -> pp_skip_to_endif(Rest, Ls1) ; Found == else -> pp_skip_to_endif(Rest, Ls1) ; Ls1 = Rest ).

%% ---- #if: defined, the built-ins, expansion, then the reader's constant expression ----
pp_eval(Ts) :- once(catch(pp_eval_(Ts), _, fail)).
pp_eval_(Ts) :-
    pp_defined_pass(Ts, T1), pp_expand_all(T1, T2), pp_defined_pass(T2, T3), pp_normalize(T3, T4),   % a built-in a macro expanded to is answered too
    phrase(ccl_cond_expr(E), T4, _), ccl_const_eval(E, V), V =\= 0.
pp_defined_pass([], []).
pp_defined_pass([tok(id, defined, L), tok(p, '(', _), tok(K, N, _), tok(p, ')', _)|Ts], [tok(int, V, L)|Os]) :- ( K == id ; K == kw ), !, ( pp_defined(N) -> V = 1 ; V = 0 ), pp_defined_pass(Ts, Os).
pp_defined_pass([tok(id, defined, L), tok(K, N, _)|Ts], [tok(int, V, L)|Os]) :- ( K == id ; K == kw ), !, ( pp_defined(N) -> V = 1 ; V = 0 ), pp_defined_pass(Ts, Os).
pp_defined_pass([tok(id, B, L), tok(p, '(', _)|Ts], [tok(int, V, L)|Os]) :- pp_builtin_name(B), pp_builtin_args(Ts, Args, Rest), !, pp_builtin_answer(B, Args, V), pp_defined_pass(Rest, Os).
pp_defined_pass([T|Ts], [T|Os]) :- pp_defined_pass(Ts, Os).
pp_builtin_args(Ts, Args, Rest) :- pp_builtin_args_(Ts, 1, [], Args, Rest).
pp_builtin_args_([tok(p, '(', L)|Ts], D, Acc, Args, Rest) :- !, D1 is D + 1, pp_builtin_args_(Ts, D1, [tok(p, '(', L)|Acc], Args, Rest).
pp_builtin_args_([tok(p, ')', _)|Ts], 1, Acc, Args, Ts) :- !, reverse(Acc, Args).
pp_builtin_args_([tok(p, ')', L)|Ts], D, Acc, Args, Rest) :- !, D1 is D - 1, pp_builtin_args_(Ts, D1, [tok(p, ')', L)|Acc], Args, Rest).
pp_builtin_args_([T|Ts], D, Acc, Args, Rest) :- pp_builtin_args_(Ts, D, [T|Acc], Args, Rest).
pp_builtin_answer('__has_include', Args, V) :- !, pp_has_include(Args, plain, V).
pp_builtin_answer('__has_include_next', Args, V) :- !, pp_has_include(Args, next, V).
pp_builtin_answer('__is_identifier', _, 1) :- !.
pp_builtin_answer('__has_builtin', _, 1) :- !.                                    % LLVM's builtins are there (libc++'s other branch is an #error)
pp_builtin_answer('__is_target_arch', [tok(_, A, _)], V) :- !, pp_arch(Arch), ( A == Arch -> V = 1 ; V = 0 ).
pp_builtin_answer('__is_target_vendor', [tok(_, apple, _)], 1) :- !.
pp_builtin_answer('__is_target_os', [tok(_, OS, _)], V) :- !, ( memberchk(OS, [macos, darwin, macosx]) -> V = 1 ; V = 0 ).
pp_builtin_answer(_, _, 0).                                                       % features, attributes, warnings, modules: the plainest path
pp_has_include(Args, How, V) :-
    (   Args = [tok(str, S, _)] -> atom_codes(N, S), Spec0 = local(N)
    ;   pp_angle_name(Args, N) -> Spec0 = system(N)
    ;   fail ),
    ( How == next -> Spec = next(Spec0) ; Spec = Spec0 ),
    pp_current_file(From), ( ccl_resolve_include(Spec, From, _) -> V = 1 ; V = 0 ).
pp_has_include(_, _, 0).
pp_angle_name([tok(p, '<', _)|Ts], N) :- pp_angle_(Ts, Cs), atom_codes(N, Cs).
pp_angle_([tok(p, '>', _)], []) :- !.
pp_angle_([T|Ts], Cs) :- pp_spell(T, C1), pp_angle_(Ts, C2), append(C1, C2, Cs).
%% what is left is numbers: an unknown name is 0, true 1, a spelled number its value
pp_plain_int([0'0]) :- !.
pp_plain_int([C|Cs]) :- C >= 0'1, C =< 0'9, pp_digits(Cs).                         % a leading 0 is octal or hex, a suffix or a point the lexer's
pp_digits([]).
pp_digits([C|Cs]) :- C >= 0'0, C =< 0'9, pp_digits(Cs).
pp_normalize([], []).
pp_normalize([tok(kw, true, L)|Ts], [tok(int, 1, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([tok(id, _, L)|Ts], [tok(int, 0, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([tok(kw, _, L)|Ts], [tok(int, 0, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([T|Ts], [T1|Os]) :- pp_norm(T, T1), pp_normalize(Ts, Os).
pp_predef('TARGET_IPHONE_SIMULATOR', any, '0').
pp_predef('TARGET_OS_DRIVERKIT', any, '0').
pp_predef('TARGET_OS_EMBEDDED', any, '0').
pp_predef('TARGET_OS_FIRMWARE', any, '0').
pp_predef('TARGET_OS_IOS', any, '0').
pp_predef('TARGET_OS_IPHONE', any, '0').
pp_predef('TARGET_OS_LINUX', any, '0').
pp_predef('TARGET_OS_MAC', any, '1').
pp_predef('TARGET_OS_MACCATALYST', any, '0').
pp_predef('TARGET_OS_NANO', any, '0').
pp_predef('TARGET_OS_OSX', any, '1').
pp_predef('TARGET_OS_SIMULATOR', any, '0').
pp_predef('TARGET_OS_TV', any, '0').
pp_predef('TARGET_OS_UEFI', any, '0').
pp_predef('TARGET_OS_UIKITFORMAC', any, '0').
pp_predef('TARGET_OS_UNIX', any, '0').
pp_predef('TARGET_OS_VISION', any, '0').
pp_predef('TARGET_OS_WATCH', any, '0').
pp_predef('TARGET_OS_WIN32', any, '0').
pp_predef('TARGET_OS_WINDOWS', any, '0').
pp_predef('_LP64', any, '1').
pp_predef('__APPLE_CC__', any, '6000').
pp_predef('__APPLE__', any, '1').
pp_predef('__ATOMIC_ACQUIRE', any, '2').
pp_predef('__ATOMIC_ACQ_REL', any, '4').
pp_predef('__ATOMIC_CONSUME', any, '1').
pp_predef('__ATOMIC_RELAXED', any, '0').
pp_predef('__ATOMIC_RELEASE', any, '3').
pp_predef('__ATOMIC_SEQ_CST', any, '5').
pp_predef('__BLOCKS__', any, '1').
pp_predef('__BOOL_WIDTH__', any, '1').
pp_predef('__BYTE_ORDER__', any, '__ORDER_LITTLE_ENDIAN__').
pp_predef('__CHAR16_TYPE__', any, 'unsigned short').
pp_predef('__CHAR32_TYPE__', any, 'unsigned int').
pp_predef('__CHAR_BIT__', any, '8').
pp_predef('__CLANG_ATOMIC_BOOL_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_CHAR16_T_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_CHAR32_T_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_CHAR_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_INT_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_LLONG_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_LONG_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_POINTER_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_SHORT_LOCK_FREE', any, '2').
pp_predef('__CLANG_ATOMIC_WCHAR_T_LOCK_FREE', any, '2').
pp_predef('__CONSTANT_CFSTRINGS__', any, '1').
pp_predef('__DBL_DECIMAL_DIG__', any, '17').
pp_predef('__DBL_DENORM_MIN__', any, '4.9406564584124654e-324').
pp_predef('__DBL_DIG__', any, '15').
pp_predef('__DBL_EPSILON__', any, '2.2204460492503131e-16').
pp_predef('__DBL_HAS_DENORM__', any, '1').
pp_predef('__DBL_HAS_INFINITY__', any, '1').
pp_predef('__DBL_HAS_QUIET_NAN__', any, '1').
pp_predef('__DBL_MANT_DIG__', any, '53').
pp_predef('__DBL_MAX_10_EXP__', any, '308').
pp_predef('__DBL_MAX_EXP__', any, '1024').
pp_predef('__DBL_MAX__', any, '1.7976931348623157e+308').
pp_predef('__DBL_MIN_10_EXP__', any, '(-307)').
pp_predef('__DBL_MIN_EXP__', any, '(-1021)').
pp_predef('__DBL_MIN__', any, '2.2250738585072014e-308').
pp_predef('__DBL_NORM_MAX__', any, '1.7976931348623157e+308').
pp_predef('__DECIMAL_DIG__', any, '__LDBL_DECIMAL_DIG__').
pp_predef('__DYNAMIC__', any, '1').
pp_predef('__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__', any, '260000').
pp_predef('__ENVIRONMENT_OS_VERSION_MIN_REQUIRED__', any, '260000').
pp_predef('__FINITE_MATH_ONLY__', any, '0').
pp_predef('__FLT16_DECIMAL_DIG__', any, '5').
pp_predef('__FLT16_DENORM_MIN__', any, '5.9604644775390625e-8F16').
pp_predef('__FLT16_DIG__', any, '3').
pp_predef('__FLT16_EPSILON__', any, '9.765625e-4F16').
pp_predef('__FLT16_HAS_DENORM__', any, '1').
pp_predef('__FLT16_HAS_INFINITY__', any, '1').
pp_predef('__FLT16_HAS_QUIET_NAN__', any, '1').
pp_predef('__FLT16_MANT_DIG__', any, '11').
pp_predef('__FLT16_MAX_10_EXP__', any, '4').
pp_predef('__FLT16_MAX_EXP__', any, '16').
pp_predef('__FLT16_MAX__', any, '6.5504e+4F16').
pp_predef('__FLT16_MIN_10_EXP__', any, '(-4)').
pp_predef('__FLT16_MIN_EXP__', any, '(-13)').
pp_predef('__FLT16_MIN__', any, '6.103515625e-5F16').
pp_predef('__FLT16_NORM_MAX__', any, '6.5504e+4F16').
pp_predef('__FLT_DECIMAL_DIG__', any, '9').
pp_predef('__FLT_DENORM_MIN__', any, '1.40129846e-45F').
pp_predef('__FLT_DIG__', any, '6').
pp_predef('__FLT_EPSILON__', any, '1.19209290e-7F').
pp_predef('__FLT_HAS_DENORM__', any, '1').
pp_predef('__FLT_HAS_INFINITY__', any, '1').
pp_predef('__FLT_HAS_QUIET_NAN__', any, '1').
pp_predef('__FLT_MANT_DIG__', any, '24').
pp_predef('__FLT_MAX_10_EXP__', any, '38').
pp_predef('__FLT_MAX_EXP__', any, '128').
pp_predef('__FLT_MAX__', any, '3.40282347e+38F').
pp_predef('__FLT_MIN_10_EXP__', any, '(-37)').
pp_predef('__FLT_MIN_EXP__', any, '(-125)').
pp_predef('__FLT_MIN__', any, '1.17549435e-38F').
pp_predef('__FLT_NORM_MAX__', any, '3.40282347e+38F').
pp_predef('__FLT_RADIX__', any, '2').
pp_predef('__FPCLASS_NEGINF', any, '0x0004').
pp_predef('__FPCLASS_NEGNORMAL', any, '0x0008').
pp_predef('__FPCLASS_NEGSUBNORMAL', any, '0x0010').
pp_predef('__FPCLASS_NEGZERO', any, '0x0020').
pp_predef('__FPCLASS_POSINF', any, '0x0200').
pp_predef('__FPCLASS_POSNORMAL', any, '0x0100').
pp_predef('__FPCLASS_POSSUBNORMAL', any, '0x0080').
pp_predef('__FPCLASS_POSZERO', any, '0x0040').
pp_predef('__FPCLASS_QNAN', any, '0x0002').
pp_predef('__FPCLASS_SNAN', any, '0x0001').
pp_predef('__GCC_ASM_FLAG_OUTPUTS__', any, '1').
pp_predef('__GCC_ATOMIC_BOOL_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_CHAR16_T_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_CHAR32_T_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_CHAR_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_INT_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_LLONG_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_LONG_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_POINTER_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_SHORT_LOCK_FREE', any, '2').
pp_predef('__GCC_ATOMIC_TEST_AND_SET_TRUEVAL', any, '1').
pp_predef('__GCC_ATOMIC_WCHAR_T_LOCK_FREE', any, '2').
pp_predef('__GCC_CONSTRUCTIVE_SIZE', any, '64').
pp_predef('__GCC_HAVE_DWARF2_CFI_ASM', any, '1').
pp_predef('__GCC_HAVE_SYNC_COMPARE_AND_SWAP_1', any, '1').
pp_predef('__GCC_HAVE_SYNC_COMPARE_AND_SWAP_16', any, '1').
pp_predef('__GCC_HAVE_SYNC_COMPARE_AND_SWAP_2', any, '1').
pp_predef('__GCC_HAVE_SYNC_COMPARE_AND_SWAP_4', any, '1').
pp_predef('__GCC_HAVE_SYNC_COMPARE_AND_SWAP_8', any, '1').
pp_predef('__GNUC_MINOR__', any, '2').
pp_predef('__GNUC_PATCHLEVEL__', any, '1').
pp_predef('__GNUC_STDC_INLINE__', any, '1').
pp_predef('__GNUC__', any, '4').
pp_predef('__GXX_ABI_VERSION', any, '1002').
pp_predef('__INT16_C(c)', any, 'c').
pp_predef('__INT16_C_SUFFIX__', any, '').
pp_predef('__INT16_FMTd__', any, '"hd"').
pp_predef('__INT16_FMTi__', any, '"hi"').
pp_predef('__INT16_MAX__', any, '32767').
pp_predef('__INT16_TYPE__', any, 'short').
pp_predef('__INT32_C(c)', any, 'c').
pp_predef('__INT32_C_SUFFIX__', any, '').
pp_predef('__INT32_FMTd__', any, '"d"').
pp_predef('__INT32_FMTi__', any, '"i"').
pp_predef('__INT32_MAX__', any, '2147483647').
pp_predef('__INT32_TYPE__', any, 'int').
pp_predef('__INT64_C(c)', any, 'c##LL').
pp_predef('__INT64_C_SUFFIX__', any, 'LL').
pp_predef('__INT64_FMTd__', any, '"lld"').
pp_predef('__INT64_FMTi__', any, '"lli"').
pp_predef('__INT64_MAX__', any, '9223372036854775807LL').
pp_predef('__INT64_TYPE__', any, 'long long int').
pp_predef('__INT8_C(c)', any, 'c').
pp_predef('__INT8_C_SUFFIX__', any, '').
pp_predef('__INT8_FMTd__', any, '"hhd"').
pp_predef('__INT8_FMTi__', any, '"hhi"').
pp_predef('__INT8_MAX__', any, '127').
pp_predef('__INT8_TYPE__', any, 'signed char').
pp_predef('__INTMAX_C(c)', any, 'c##L').
pp_predef('__INTMAX_C_SUFFIX__', any, 'L').
pp_predef('__INTMAX_FMTd__', any, '"ld"').
pp_predef('__INTMAX_FMTi__', any, '"li"').
pp_predef('__INTMAX_MAX__', any, '9223372036854775807L').
pp_predef('__INTMAX_TYPE__', any, 'long int').
pp_predef('__INTMAX_WIDTH__', any, '64').
pp_predef('__INTPTR_FMTd__', any, '"ld"').
pp_predef('__INTPTR_FMTi__', any, '"li"').
pp_predef('__INTPTR_MAX__', any, '9223372036854775807L').
pp_predef('__INTPTR_TYPE__', any, 'long int').
pp_predef('__INTPTR_WIDTH__', any, '64').
pp_predef('__INT_FAST16_FMTd__', any, '"hd"').
pp_predef('__INT_FAST16_FMTi__', any, '"hi"').
pp_predef('__INT_FAST16_MAX__', any, '32767').
pp_predef('__INT_FAST16_TYPE__', any, 'short').
pp_predef('__INT_FAST16_WIDTH__', any, '16').
pp_predef('__INT_FAST32_FMTd__', any, '"d"').
pp_predef('__INT_FAST32_FMTi__', any, '"i"').
pp_predef('__INT_FAST32_MAX__', any, '2147483647').
pp_predef('__INT_FAST32_TYPE__', any, 'int').
pp_predef('__INT_FAST32_WIDTH__', any, '32').
pp_predef('__INT_FAST64_FMTd__', any, '"lld"').
pp_predef('__INT_FAST64_FMTi__', any, '"lli"').
pp_predef('__INT_FAST64_MAX__', any, '9223372036854775807LL').
pp_predef('__INT_FAST64_TYPE__', any, 'long long int').
pp_predef('__INT_FAST64_WIDTH__', any, '64').
pp_predef('__INT_FAST8_FMTd__', any, '"hhd"').
pp_predef('__INT_FAST8_FMTi__', any, '"hhi"').
pp_predef('__INT_FAST8_MAX__', any, '127').
pp_predef('__INT_FAST8_TYPE__', any, 'signed char').
pp_predef('__INT_FAST8_WIDTH__', any, '8').
pp_predef('__INT_LEAST16_FMTd__', any, '"hd"').
pp_predef('__INT_LEAST16_FMTi__', any, '"hi"').
pp_predef('__INT_LEAST16_MAX__', any, '32767').
pp_predef('__INT_LEAST16_TYPE__', any, 'short').
pp_predef('__INT_LEAST16_WIDTH__', any, '16').
pp_predef('__INT_LEAST32_FMTd__', any, '"d"').
pp_predef('__INT_LEAST32_FMTi__', any, '"i"').
pp_predef('__INT_LEAST32_MAX__', any, '2147483647').
pp_predef('__INT_LEAST32_TYPE__', any, 'int').
pp_predef('__INT_LEAST32_WIDTH__', any, '32').
pp_predef('__INT_LEAST64_FMTd__', any, '"lld"').
pp_predef('__INT_LEAST64_FMTi__', any, '"lli"').
pp_predef('__INT_LEAST64_MAX__', any, '9223372036854775807LL').
pp_predef('__INT_LEAST64_TYPE__', any, 'long long int').
pp_predef('__INT_LEAST64_WIDTH__', any, '64').
pp_predef('__INT_LEAST8_FMTd__', any, '"hhd"').
pp_predef('__INT_LEAST8_FMTi__', any, '"hhi"').
pp_predef('__INT_LEAST8_MAX__', any, '127').
pp_predef('__INT_LEAST8_TYPE__', any, 'signed char').
pp_predef('__INT_LEAST8_WIDTH__', any, '8').
pp_predef('__INT_MAX__', any, '2147483647').
pp_predef('__INT_WIDTH__', any, '32').
pp_predef('__LDBL_HAS_DENORM__', any, '1').
pp_predef('__LDBL_HAS_INFINITY__', any, '1').
pp_predef('__LDBL_HAS_QUIET_NAN__', any, '1').
pp_predef('__LITTLE_ENDIAN__', any, '1').
pp_predef('__LLONG_WIDTH__', any, '64').
pp_predef('__LONG_LONG_MAX__', any, '9223372036854775807LL').
pp_predef('__LONG_MAX__', any, '9223372036854775807L').
pp_predef('__LONG_WIDTH__', any, '64').
pp_predef('__LP64__', any, '1').
pp_predef('__MACH__', any, '1').
pp_predef('__MEMORY_SCOPE_CLUSTR', any, '5').
pp_predef('__MEMORY_SCOPE_DEVICE', any, '1').
pp_predef('__MEMORY_SCOPE_SINGLE', any, '4').
pp_predef('__MEMORY_SCOPE_SYSTEM', any, '0').
pp_predef('__MEMORY_SCOPE_WRKGRP', any, '2').
pp_predef('__MEMORY_SCOPE_WVFRNT', any, '3').
pp_predef('__NO_INLINE__', any, '1').
pp_predef('__NO_MATH_ERRNO__', any, '1').
pp_predef('__OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES', any, '3').
pp_predef('__OPENCL_MEMORY_SCOPE_DEVICE', any, '2').
pp_predef('__OPENCL_MEMORY_SCOPE_SUB_GROUP', any, '4').
pp_predef('__OPENCL_MEMORY_SCOPE_WORK_GROUP', any, '1').
pp_predef('__OPENCL_MEMORY_SCOPE_WORK_ITEM', any, '0').
pp_predef('__ORDER_BIG_ENDIAN__', any, '4321').
pp_predef('__ORDER_LITTLE_ENDIAN__', any, '1234').
pp_predef('__ORDER_PDP_ENDIAN__', any, '3412').
pp_predef('__PIC__', any, '2').
pp_predef('__POINTER_WIDTH__', any, '64').
pp_predef('__PRAGMA_REDEFINE_EXTNAME', any, '1').
pp_predef('__PTRDIFF_FMTd__', any, '"ld"').
pp_predef('__PTRDIFF_FMTi__', any, '"li"').
pp_predef('__PTRDIFF_MAX__', any, '9223372036854775807L').
pp_predef('__PTRDIFF_TYPE__', any, 'long int').
pp_predef('__PTRDIFF_WIDTH__', any, '64').
pp_predef('__REGISTER_PREFIX__', any, '').
pp_predef('__SCHAR_MAX__', any, '127').
pp_predef('__SHRT_MAX__', any, '32767').
pp_predef('__SHRT_WIDTH__', any, '16').
pp_predef('__SIG_ATOMIC_MAX__', any, '2147483647').
pp_predef('__SIG_ATOMIC_MIN__', any, '(-__SIG_ATOMIC_MAX__ - 1)').
pp_predef('__SIG_ATOMIC_TYPE__', any, 'int').
pp_predef('__SIG_ATOMIC_WIDTH__', any, '32').
pp_predef('__SIZEOF_DOUBLE__', any, '8').
pp_predef('__SIZEOF_FLOAT__', any, '4').
pp_predef('__SIZEOF_INT128__', any, '16').
pp_predef('__SIZEOF_INT__', any, '4').
pp_predef('__SIZEOF_LONG_LONG__', any, '8').
pp_predef('__SIZEOF_LONG__', any, '8').
pp_predef('__SIZEOF_POINTER__', any, '8').
pp_predef('__SIZEOF_PTRDIFF_T__', any, '8').
pp_predef('__SIZEOF_SHORT__', any, '2').
pp_predef('__SIZEOF_SIZE_T__', any, '8').
pp_predef('__SIZEOF_WCHAR_T__', any, '4').
pp_predef('__SIZEOF_WINT_T__', any, '4').
pp_predef('__SIZE_FMTX__', any, '"lX"').
pp_predef('__SIZE_FMTo__', any, '"lo"').
pp_predef('__SIZE_FMTu__', any, '"lu"').
pp_predef('__SIZE_FMTx__', any, '"lx"').
pp_predef('__SIZE_MAX__', any, '18446744073709551615UL').
pp_predef('__SIZE_TYPE__', any, 'long unsigned int').
pp_predef('__SIZE_WIDTH__', any, '64').
pp_predef('__SSP__', any, '1').
pp_predef('__STDC_EMBED_EMPTY__', any, '2').
pp_predef('__STDC_EMBED_FOUND__', any, '1').
pp_predef('__STDC_EMBED_NOT_FOUND__', any, '0').
pp_predef('__STDC_HOSTED__', any, '1').
pp_predef('__STDC_NO_THREADS__', any, '1').
pp_predef('__STDC_UTF_16__', any, '1').
pp_predef('__STDC_UTF_32__', any, '1').
pp_predef('__STDC_VERSION__', any, '201710L').
pp_predef('__STDC__', any, '1').
pp_predef('__UINT16_C(c)', any, 'c').
pp_predef('__UINT16_C_SUFFIX__', any, '').
pp_predef('__UINT16_FMTX__', any, '"hX"').
pp_predef('__UINT16_FMTo__', any, '"ho"').
pp_predef('__UINT16_FMTu__', any, '"hu"').
pp_predef('__UINT16_FMTx__', any, '"hx"').
pp_predef('__UINT16_MAX__', any, '65535').
pp_predef('__UINT16_TYPE__', any, 'unsigned short').
pp_predef('__UINT32_C(c)', any, 'c##U').
pp_predef('__UINT32_C_SUFFIX__', any, 'U').
pp_predef('__UINT32_FMTX__', any, '"X"').
pp_predef('__UINT32_FMTo__', any, '"o"').
pp_predef('__UINT32_FMTu__', any, '"u"').
pp_predef('__UINT32_FMTx__', any, '"x"').
pp_predef('__UINT32_MAX__', any, '4294967295U').
pp_predef('__UINT32_TYPE__', any, 'unsigned int').
pp_predef('__UINT64_C(c)', any, 'c##ULL').
pp_predef('__UINT64_C_SUFFIX__', any, 'ULL').
pp_predef('__UINT64_FMTX__', any, '"llX"').
pp_predef('__UINT64_FMTo__', any, '"llo"').
pp_predef('__UINT64_FMTu__', any, '"llu"').
pp_predef('__UINT64_FMTx__', any, '"llx"').
pp_predef('__UINT64_MAX__', any, '18446744073709551615ULL').
pp_predef('__UINT64_TYPE__', any, 'long long unsigned int').
pp_predef('__UINT8_C(c)', any, 'c').
pp_predef('__UINT8_C_SUFFIX__', any, '').
pp_predef('__UINT8_FMTX__', any, '"hhX"').
pp_predef('__UINT8_FMTo__', any, '"hho"').
pp_predef('__UINT8_FMTu__', any, '"hhu"').
pp_predef('__UINT8_FMTx__', any, '"hhx"').
pp_predef('__UINT8_MAX__', any, '255').
pp_predef('__UINT8_TYPE__', any, 'unsigned char').
pp_predef('__UINTMAX_C(c)', any, 'c##UL').
pp_predef('__UINTMAX_C_SUFFIX__', any, 'UL').
pp_predef('__UINTMAX_FMTX__', any, '"lX"').
pp_predef('__UINTMAX_FMTo__', any, '"lo"').
pp_predef('__UINTMAX_FMTu__', any, '"lu"').
pp_predef('__UINTMAX_FMTx__', any, '"lx"').
pp_predef('__UINTMAX_MAX__', any, '18446744073709551615UL').
pp_predef('__UINTMAX_TYPE__', any, 'long unsigned int').
pp_predef('__UINTMAX_WIDTH__', any, '64').
pp_predef('__UINTPTR_FMTX__', any, '"lX"').
pp_predef('__UINTPTR_FMTo__', any, '"lo"').
pp_predef('__UINTPTR_FMTu__', any, '"lu"').
pp_predef('__UINTPTR_FMTx__', any, '"lx"').
pp_predef('__UINTPTR_MAX__', any, '18446744073709551615UL').
pp_predef('__UINTPTR_TYPE__', any, 'long unsigned int').
pp_predef('__UINTPTR_WIDTH__', any, '64').
pp_predef('__UINT_FAST16_FMTX__', any, '"hX"').
pp_predef('__UINT_FAST16_FMTo__', any, '"ho"').
pp_predef('__UINT_FAST16_FMTu__', any, '"hu"').
pp_predef('__UINT_FAST16_FMTx__', any, '"hx"').
pp_predef('__UINT_FAST16_MAX__', any, '65535').
pp_predef('__UINT_FAST16_TYPE__', any, 'unsigned short').
pp_predef('__UINT_FAST32_FMTX__', any, '"X"').
pp_predef('__UINT_FAST32_FMTo__', any, '"o"').
pp_predef('__UINT_FAST32_FMTu__', any, '"u"').
pp_predef('__UINT_FAST32_FMTx__', any, '"x"').
pp_predef('__UINT_FAST32_MAX__', any, '4294967295U').
pp_predef('__UINT_FAST32_TYPE__', any, 'unsigned int').
pp_predef('__UINT_FAST64_FMTX__', any, '"llX"').
pp_predef('__UINT_FAST64_FMTo__', any, '"llo"').
pp_predef('__UINT_FAST64_FMTu__', any, '"llu"').
pp_predef('__UINT_FAST64_FMTx__', any, '"llx"').
pp_predef('__UINT_FAST64_MAX__', any, '18446744073709551615ULL').
pp_predef('__UINT_FAST64_TYPE__', any, 'long long unsigned int').
pp_predef('__UINT_FAST8_FMTX__', any, '"hhX"').
pp_predef('__UINT_FAST8_FMTo__', any, '"hho"').
pp_predef('__UINT_FAST8_FMTu__', any, '"hhu"').
pp_predef('__UINT_FAST8_FMTx__', any, '"hhx"').
pp_predef('__UINT_FAST8_MAX__', any, '255').
pp_predef('__UINT_FAST8_TYPE__', any, 'unsigned char').
pp_predef('__UINT_LEAST16_FMTX__', any, '"hX"').
pp_predef('__UINT_LEAST16_FMTo__', any, '"ho"').
pp_predef('__UINT_LEAST16_FMTu__', any, '"hu"').
pp_predef('__UINT_LEAST16_FMTx__', any, '"hx"').
pp_predef('__UINT_LEAST16_MAX__', any, '65535').
pp_predef('__UINT_LEAST16_TYPE__', any, 'unsigned short').
pp_predef('__UINT_LEAST32_FMTX__', any, '"X"').
pp_predef('__UINT_LEAST32_FMTo__', any, '"o"').
pp_predef('__UINT_LEAST32_FMTu__', any, '"u"').
pp_predef('__UINT_LEAST32_FMTx__', any, '"x"').
pp_predef('__UINT_LEAST32_MAX__', any, '4294967295U').
pp_predef('__UINT_LEAST32_TYPE__', any, 'unsigned int').
pp_predef('__UINT_LEAST64_FMTX__', any, '"llX"').
pp_predef('__UINT_LEAST64_FMTo__', any, '"llo"').
pp_predef('__UINT_LEAST64_FMTu__', any, '"llu"').
pp_predef('__UINT_LEAST64_FMTx__', any, '"llx"').
pp_predef('__UINT_LEAST64_MAX__', any, '18446744073709551615ULL').
pp_predef('__UINT_LEAST64_TYPE__', any, 'long long unsigned int').
pp_predef('__UINT_LEAST8_FMTX__', any, '"hhX"').
pp_predef('__UINT_LEAST8_FMTo__', any, '"hho"').
pp_predef('__UINT_LEAST8_FMTu__', any, '"hhu"').
pp_predef('__UINT_LEAST8_FMTx__', any, '"hhx"').
pp_predef('__UINT_LEAST8_MAX__', any, '255').
pp_predef('__UINT_LEAST8_TYPE__', any, 'unsigned char').
pp_predef('__USER_LABEL_PREFIX__', any, '_').
pp_predef('__WCHAR_MAX__', any, '2147483647').
pp_predef('__WCHAR_MIN__', any, '(-__WCHAR_MAX__ - 1)').
pp_predef('__WCHAR_TYPE__', any, 'int').
pp_predef('__WCHAR_WIDTH__', any, '32').
pp_predef('__WINT_MAX__', any, '2147483647').
pp_predef('__WINT_MIN__', any, '(-__WINT_MAX__ - 1)').
pp_predef('__WINT_TYPE__', any, 'int').
pp_predef('__WINT_WIDTH__', any, '32').
pp_predef('__block', any, '__attribute__((__blocks__(byref)))').
%% the plainest path through the SDK's string and stdio headers: no fortified
%% forms (strcpy stays the function, not __builtin___strcpy_chk), as with the
%% features and attributes answered 0
pp_predef('_FORTIFY_SOURCE', any, '0').
pp_predef('__clang__', any, '1').
pp_predef('__clang_major__', any, '23').
pp_predef('__clang_minor__', any, '1').
pp_predef('__clang_patchlevel__', any, '0').
pp_predef('__llvm__', any, '1').
pp_predef('__nonnull', any, '_Nonnull').
pp_predef('__null_unspecified', any, '_Null_unspecified').
pp_predef('__nullable', any, '_Nullable').
pp_predef('__pic__', any, '2').
pp_predef('__strong', any, '').
pp_predef('__unsafe_unretained', any, '').
pp_predef('__weak', any, '__attribute__((objc_gc(weak)))').
pp_predef('__BIGGEST_ALIGNMENT__', x86_64, '16').
pp_predef('__BITINT_MAXWIDTH__', x86_64, '8388608').
pp_predef('__FXSR__', x86_64, '1').
pp_predef('__GCC_DESTRUCTIVE_SIZE', x86_64, '64').
pp_predef('__LAHF_SAHF__', x86_64, '1').
pp_predef('__LDBL_DECIMAL_DIG__', x86_64, '21').
pp_predef('__LDBL_DENORM_MIN__', x86_64, '3.64519953188247460253e-4951L').
pp_predef('__LDBL_DIG__', x86_64, '18').
pp_predef('__LDBL_EPSILON__', x86_64, '1.08420217248550443401e-19L').
pp_predef('__LDBL_MANT_DIG__', x86_64, '64').
pp_predef('__LDBL_MAX_10_EXP__', x86_64, '4932').
pp_predef('__LDBL_MAX_EXP__', x86_64, '16384').
pp_predef('__LDBL_MAX__', x86_64, '1.18973149535723176502e+4932L').
pp_predef('__LDBL_MIN_10_EXP__', x86_64, '(-4931)').
pp_predef('__LDBL_MIN_EXP__', x86_64, '(-16381)').
pp_predef('__LDBL_MIN__', x86_64, '3.36210314311209350626e-4932L').
pp_predef('__LDBL_NORM_MAX__', x86_64, '1.18973149535723176502e+4932L').
pp_predef('__MMX__', x86_64, '1').
pp_predef('__NO_MATH_INLINES', x86_64, '1').
pp_predef('__OBJC_BOOL_IS_BOOL', x86_64, '0').
pp_predef('__SEG_FS', x86_64, '1').
pp_predef('__SEG_GS', x86_64, '1').
pp_predef('__SIZEOF_LONG_DOUBLE__', x86_64, '16').
pp_predef('__SSE2_MATH__', x86_64, '1').
pp_predef('__SSE2__', x86_64, '1').
pp_predef('__SSE3__', x86_64, '1').
pp_predef('__SSE4_1__', x86_64, '1').
pp_predef('__SSE_MATH__', x86_64, '1').
pp_predef('__SSE__', x86_64, '1').
pp_predef('__SSSE3__', x86_64, '1').
pp_predef('__amd64', x86_64, '1').
pp_predef('__amd64__', x86_64, '1').
pp_predef('__code_model_small__', x86_64, '1').
pp_predef('__core2', x86_64, '1').
pp_predef('__core2__', x86_64, '1').
pp_predef('__seg_fs', x86_64, '__attribute__((address_space(257)))').
pp_predef('__seg_gs', x86_64, '__attribute__((address_space(256)))').
pp_predef('__tune_core2__', x86_64, '1').
pp_predef('__x86_64', x86_64, '1').
pp_predef('__x86_64__', x86_64, '1').
pp_predef('__AARCH64EL__', arm64, '1').
pp_predef('__AARCH64_CMODEL_SMALL__', arm64, '1').
pp_predef('__AARCH64_SIMD__', arm64, '1').
pp_predef('__ARM64_ARCH_8__', arm64, '1').
pp_predef('__ARM_64BIT_STATE', arm64, '1').
pp_predef('__ARM_ACLE', arm64, '202420').
pp_predef('__ARM_ACLE_VERSION(year,quarter,patch)', arm64, '(100 * (year) + 10 * (quarter) + (patch))').
pp_predef('__ARM_ALIGN_MAX_STACK_PWR', arm64, '4').
pp_predef('__ARM_ARCH', arm64, '8').
pp_predef('__ARM_ARCH_ISA_A64', arm64, '1').
pp_predef('__ARM_ARCH_PROFILE', arm64, '\'A\'').
pp_predef('__ARM_FEATURE_AES', arm64, '1').
pp_predef('__ARM_FEATURE_ATOMICS', arm64, '1').
pp_predef('__ARM_FEATURE_CLZ', arm64, '1').
pp_predef('__ARM_FEATURE_COMPLEX', arm64, '1').
pp_predef('__ARM_FEATURE_CRC32', arm64, '1').
pp_predef('__ARM_FEATURE_CRYPTO', arm64, '1').
pp_predef('__ARM_FEATURE_DIRECTED_ROUNDING', arm64, '1').
pp_predef('__ARM_FEATURE_DIV', arm64, '1').
pp_predef('__ARM_FEATURE_DOTPROD', arm64, '1').
pp_predef('__ARM_FEATURE_FMA', arm64, '1').
pp_predef('__ARM_FEATURE_FP16_FML', arm64, '1').
pp_predef('__ARM_FEATURE_FP16_SCALAR_ARITHMETIC', arm64, '1').
pp_predef('__ARM_FEATURE_FP16_VECTOR_ARITHMETIC', arm64, '1').
pp_predef('__ARM_FEATURE_IDIV', arm64, '1').
pp_predef('__ARM_FEATURE_JCVT', arm64, '1').
pp_predef('__ARM_FEATURE_LDREX', arm64, '0xF').
pp_predef('__ARM_FEATURE_NUMERIC_MAXMIN', arm64, '1').
pp_predef('__ARM_FEATURE_PAUTH', arm64, '1').
pp_predef('__ARM_FEATURE_QRDMX', arm64, '1').
pp_predef('__ARM_FEATURE_RCPC', arm64, '1').
pp_predef('__ARM_FEATURE_SHA2', arm64, '1').
pp_predef('__ARM_FEATURE_SHA3', arm64, '1').
pp_predef('__ARM_FEATURE_SHA512', arm64, '1').
pp_predef('__ARM_FEATURE_UNALIGNED', arm64, '1').
pp_predef('__ARM_FP', arm64, '0xE').
pp_predef('__ARM_FP16_ARGS', arm64, '1').
pp_predef('__ARM_FP16_FORMAT_IEEE', arm64, '1').
pp_predef('__ARM_NEON', arm64, '1').
pp_predef('__ARM_NEON_FP', arm64, '0xE').
pp_predef('__ARM_NEON_SVE_BRIDGE', arm64, '1').
pp_predef('__ARM_NEON__', arm64, '1').
pp_predef('__ARM_PCS_AAPCS64', arm64, '1').
pp_predef('__ARM_PREFETCH_RANGE', arm64, '1').
pp_predef('__ARM_SIZEOF_MINIMAL_ENUM', arm64, '4').
pp_predef('__ARM_SIZEOF_WCHAR_T', arm64, '4').
pp_predef('__ARM_STATE_ZA', arm64, '1').
pp_predef('__ARM_STATE_ZT0', arm64, '1').
pp_predef('__BIGGEST_ALIGNMENT__', arm64, '8').
pp_predef('__BITINT_MAXWIDTH__', arm64, '128').
pp_predef('__FP_FAST_FMA', arm64, '1').
pp_predef('__FP_FAST_FMAF', arm64, '1').
pp_predef('__FUNCTION_MULTI_VERSIONING_SUPPORT_LEVEL', arm64, '202430').
pp_predef('__GCC_DESTRUCTIVE_SIZE', arm64, '128').
pp_predef('__HAVE_FUNCTION_MULTI_VERSIONING', arm64, '1').
pp_predef('__LDBL_DECIMAL_DIG__', arm64, '17').
pp_predef('__LDBL_DENORM_MIN__', arm64, '4.9406564584124654e-324L').
pp_predef('__LDBL_DIG__', arm64, '15').
pp_predef('__LDBL_EPSILON__', arm64, '2.2204460492503131e-16L').
pp_predef('__LDBL_MANT_DIG__', arm64, '53').
pp_predef('__LDBL_MAX_10_EXP__', arm64, '308').
pp_predef('__LDBL_MAX_EXP__', arm64, '1024').
pp_predef('__LDBL_MAX__', arm64, '1.7976931348623157e+308L').
pp_predef('__LDBL_MIN_10_EXP__', arm64, '(-307)').
pp_predef('__LDBL_MIN_EXP__', arm64, '(-1021)').
pp_predef('__LDBL_MIN__', arm64, '2.2250738585072014e-308L').
pp_predef('__LDBL_NORM_MAX__', arm64, '1.7976931348623157e+308L').
pp_predef('__OBJC_BOOL_IS_BOOL', arm64, '1').
pp_predef('__SIZEOF_LONG_DOUBLE__', arm64, '8').
pp_predef('__aarch64__', arm64, '1').
pp_predef('__arm64', arm64, '1').
pp_predef('__arm64__', arm64, '1').
pp_predef('__DEPRECATED', cpp, '1').
pp_predef('__EXCEPTIONS', cpp, '1').
pp_predef('__GLIBCXX_BITSIZE_INT_N_0', cpp, '128').
pp_predef('__GLIBCXX_TYPE_INT_N_0', cpp, '__int128').
pp_predef('__GNUC_GNU_INLINE__', cpp, '1').
pp_predef('__GNUG__', cpp, '4').
pp_predef('__GXX_EXPERIMENTAL_CXX0X__', cpp, '1').
pp_predef('__GXX_RTTI', cpp, '1').
pp_predef('__GXX_WEAK__', cpp, '1').
pp_predef('__STDCPP_DEFAULT_NEW_ALIGNMENT__', cpp, '16UL').
pp_predef('__STDCPP_THREADS__', cpp, '1').
pp_predef('__cplusplus', cpp, '201703L').
pp_predef('__cpp_aggregate_bases', cpp, '201603L').
pp_predef('__cpp_aggregate_nsdmi', cpp, '201304L').
pp_predef('__cpp_alias_templates', cpp, '200704L').
pp_predef('__cpp_aligned_new', cpp, '201606L').
pp_predef('__cpp_attributes', cpp, '200809L').
pp_predef('__cpp_binary_literals', cpp, '201304L').
pp_predef('__cpp_capture_star_this', cpp, '201603L').
pp_predef('__cpp_constexpr', cpp, '201603L').
pp_predef('__cpp_constexpr_in_decltype', cpp, '201711L').
pp_predef('__cpp_decltype', cpp, '200707L').
pp_predef('__cpp_decltype_auto', cpp, '201304L').
pp_predef('__cpp_deduction_guides', cpp, '201703L').
pp_predef('__cpp_delegating_constructors', cpp, '200604L').
pp_predef('__cpp_deleted_function', cpp, '202403L').
pp_predef('__cpp_digit_separators', cpp, '201309L').
pp_predef('__cpp_enumerator_attributes', cpp, '201411L').
pp_predef('__cpp_exceptions', cpp, '199711L').
pp_predef('__cpp_fold_expressions', cpp, '201603L').
pp_predef('__cpp_generic_lambdas', cpp, '201304L').
pp_predef('__cpp_guaranteed_copy_elision', cpp, '201606L').
pp_predef('__cpp_hex_float', cpp, '201603L').
pp_predef('__cpp_if_constexpr', cpp, '201606L').
pp_predef('__cpp_impl_destroying_delete', cpp, '201806L').
pp_predef('__cpp_inheriting_constructors', cpp, '201511L').
pp_predef('__cpp_init_captures', cpp, '201304L').
pp_predef('__cpp_initializer_lists', cpp, '200806L').
pp_predef('__cpp_inline_variables', cpp, '201606L').
pp_predef('__cpp_lambdas', cpp, '200907L').
pp_predef('__cpp_named_character_escapes', cpp, '202606L').
pp_predef('__cpp_namespace_attributes', cpp, '201411L').
pp_predef('__cpp_nested_namespace_definitions', cpp, '201411L').
pp_predef('__cpp_noexcept_function_type', cpp, '201510L').
pp_predef('__cpp_nontype_template_args', cpp, '201411L').
pp_predef('__cpp_nontype_template_parameter_auto', cpp, '201606L').
pp_predef('__cpp_nsdmi', cpp, '200809L').
pp_predef('__cpp_pack_indexing', cpp, '202311L').
pp_predef('__cpp_placeholder_variables', cpp, '202306L').
pp_predef('__cpp_range_based_for', cpp, '201603L').
pp_predef('__cpp_raw_strings', cpp, '200710L').
pp_predef('__cpp_ref_qualifiers', cpp, '200710L').
pp_predef('__cpp_return_type_deduction', cpp, '201304L').
pp_predef('__cpp_rtti', cpp, '199711L').
pp_predef('__cpp_rvalue_references', cpp, '200610L').
pp_predef('__cpp_sized_deallocation', cpp, '201309L').
pp_predef('__cpp_static_assert', cpp, '202306L').
pp_predef('__cpp_static_call_operator', cpp, '202207L').
pp_predef('__cpp_structured_bindings', cpp, '202411L').
pp_predef('__cpp_template_auto', cpp, '201606L').
pp_predef('__cpp_template_template_args', cpp, '201611L').
pp_predef('__cpp_threadsafe_static_init', cpp, '200806L').
pp_predef('__cpp_trivial_relocatability', cpp, '202502L').
pp_predef('__cpp_unicode_characters', cpp, '200704L').
pp_predef('__cpp_unicode_literals', cpp, '200710L').
pp_predef('__cpp_user_defined_literals', cpp, '200809L').
pp_predef('__cpp_variable_templates', cpp, '201304L').
pp_predef('__cpp_variadic_friend', cpp, '202403L').
pp_predef('__cpp_variadic_templates', cpp, '200704L').
pp_predef('__cpp_variadic_using', cpp, '201611L').
pp_predef('__private_extern__', cpp, 'extern').
%% the levels above C++17, from the reference compiler's -dM -E at each (2026-09-06): what appears or changes
pp_predef('__cplusplus', cpp20, '202002L').
pp_predef('__CLANG_ATOMIC_CHAR8_T_LOCK_FREE', cpp20, '2').
pp_predef('__GCC_ATOMIC_CHAR8_T_LOCK_FREE', cpp20, '2').
pp_predef('__cpp_aggregate_paren_init', cpp20, '201902L').
pp_predef('__cpp_char8_t', cpp20, '202207L').
pp_predef('__cpp_concepts', cpp20, '202002').
pp_predef('__cpp_conditional_explicit', cpp20, '201806L').
pp_predef('__cpp_consteval', cpp20, '202211L').
pp_predef('__cpp_constexpr', cpp20, '202002L').
pp_predef('__cpp_constexpr_dynamic_alloc', cpp20, '201907L').
pp_predef('__cpp_constinit', cpp20, '201907L').
pp_predef('__cpp_designated_initializers', cpp20, '201707L').
pp_predef('__cpp_generic_lambdas', cpp20, '201707L').
pp_predef('__cpp_impl_coroutine', cpp20, '201902L').
pp_predef('__cpp_impl_three_way_comparison', cpp20, '201907L').
pp_predef('__cpp_init_captures', cpp20, '201803L').
pp_predef('__cpp_modules', cpp20, '1').
pp_predef('__cpp_using_enum', cpp20, '201907L').
pp_predef('__cplusplus', cpp23, '202302L').
pp_predef('__cpp_auto_cast', cpp23, '202110L').
pp_predef('__cpp_constexpr', cpp23, '202211L').
pp_predef('__cpp_explicit_this_parameter', cpp23, '202110L').
pp_predef('__cpp_if_consteval', cpp23, '202106L').
pp_predef('__cpp_implicit_move', cpp23, '202207L').
pp_predef('__cpp_multidimensional_subscript', cpp23, '202211L').
pp_predef('__cpp_range_based_for', cpp23, '202211L').
pp_predef('__cpp_size_t_suffix', cpp23, '202011L').
pp_predef('__cplusplus', cpp26, '202400L').
pp_predef('__cpp_constexpr', cpp26, '202406L').

%% ---- -E: the flattened stream spelled back as text ------------------------------
%% ccl_pp_spell(+Tokens, -Codes): one token after another, a space between, a
%% newline where the line changes (blank lines where lines were skipped, up to
%% three, so the text keeps some of the shape); a string with its escapes,
%% a char as its code, a number as its value with its suffix
ccl_pp_spell(Tokens, Codes) :- ccl_pp_spell_(Tokens, 0, Codes).
ccl_pp_spell_([], _, [10]).
ccl_pp_spell_([tok(K, V, L)|Ts], L0, Codes) :-
    ( L =:= L0 -> Codes = [32|C1] ; L0 =:= 0 -> Codes = C1 ; L - L0 > 3 -> Codes = [10, 10, 10|C1] ; L - L0 =:= 3 -> Codes = [10, 10|C1] ; Codes = [10|C1] ),   % a smaller line: another file begins
    ccl_pp_spell_tok(K, V, C1, C2), ccl_pp_spell_(Ts, L, C2).
ccl_pp_spell_tok(str, Cs, [34|Out], Rest) :- !, ccl_pp_spell_str(Cs, Out, [34|Rest]).
ccl_pp_spell_tok(chr, C, [39|Out], Rest) :- !, ccl_pp_spell_str([C], Out, [39|Rest]).
ccl_pp_spell_tok(uint, N, Out, Rest) :- !, number_codes(N, Cs), append(Cs, [0'u|Rest], Out).
ccl_pp_spell_tok(long, N, Out, Rest) :- !, number_codes(N, Cs), append(Cs, [0'l|Rest], Out).
ccl_pp_spell_tok(ulong, N, Out, Rest) :- !, number_codes(N, Cs), append(Cs, [0'u, 0'l|Rest], Out).
ccl_pp_spell_tok(pp, A, [35|Out], Rest) :- !, atom_codes(A, Cs), append(Cs, Rest, Out).
ccl_pp_spell_tok(cocolog, A, Out, Rest) :- !, atom_codes('#cocolog', H), atom_codes(A, Cs), atom_codes('#end', E), append(H, [10|Cs], O1), append(O1, [10|E], O2), append(O2, Rest, Out).
ccl_pp_spell_tok(float, F, Out, Rest) :- F > 1.0e308, !, atom_codes('1e999', Cs), append(Cs, Rest, Out).       % past double (a long double literal): infinite again when read
ccl_pp_spell_tok(float, F, Out, Rest) :- F < -1.0e308, !, atom_codes('-1e999', Cs), append(Cs, Rest, Out).
ccl_pp_spell_tok(_, V, Out, Rest) :- ( atom(V) -> atom_codes(V, Cs) ; number_codes(V, Cs) ), append(Cs, Rest, Out).
ccl_pp_spell_str([], R, R).
ccl_pp_spell_str([C|Cs], Out, R) :- ccl_pp_spell_chr(C, Out, O1), ccl_pp_spell_str(Cs, O1, R).
ccl_pp_spell_chr(34, [92, 34|R], R) :- !.
ccl_pp_spell_chr(39, [92, 39|R], R) :- !.
ccl_pp_spell_chr(92, [92, 92|R], R) :- !.
ccl_pp_spell_chr(10, [92, 0'n|R], R) :- !.
ccl_pp_spell_chr(9, [92, 0't|R], R) :- !.
ccl_pp_spell_chr(C, [C|R], R) :- C >= 32, C < 127, !.
ccl_pp_spell_chr(C, [92, O1, O2, O3|R], R) :- C < 256, !, O1 is 0'0 + C // 64, O2 is 0'0 + (C // 8) mod 8, O3 is 0'0 + C mod 8.   % \NNN: three octal digits, which no digit after can extend
ccl_pp_spell_chr(C, Out, R) :- atom_codes('\\u{', H), ccl_pp_hexn(C, Hs), append(H, Hs, O1), append(O1, [125|R], Out).                     % a code point: \u{...}
ccl_pp_hexn(0, [0'0]) :- !.
ccl_pp_hexn(C, Hs) :- ccl_pp_hexn_(C, [], Hs).
ccl_pp_hexn_(0, Acc, Acc) :- !.
ccl_pp_hexn_(C, Acc, Hs) :- D is C mod 16, C1 is C // 16, ccl_pp_hexd(D, H), ccl_pp_hexn_(C1, [H|Acc], Hs).
ccl_pp_hexd(D, H) :- ( D < 10 -> H is 0'0 + D ; H is 0'a + D - 10 ).
