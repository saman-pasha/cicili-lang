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
ccl_pp_file(Path, Tokens, Files) :-
    ccl_ensure_globals, pp_reset, pp_predefine,
    nb_setval('$ccl_hash', punct),                                                   % the run lexes in the preprocessor's mode: `#' a punctuator, a number as spelled
    ( once(catch(pp_include_file(Path, Out, []), E, true)) -> true ; E = failed ),
    nb_setval('$ccl_hash', line),
    ( var(E) -> true ; E == failed -> fail ; throw(E) ),
    pp_finish(Out, Tokens),
    nb_getval('$pp_files', Fs), reverse(Fs, Files).
ccl_pp_macros(Macros) :-
    nb_getval('$pp_names', Ns), sort(Ns, Names), pp_macro_terms(Names, Macros).
pp_macro_terms([], []).
pp_macro_terms([N|Ns], Ms) :- pp_macro_terms(Ns, Ms1), ( pp_macro(N, Ps, B) -> Ms = [macro(N, Ps, B)|Ms1] ; Ms = Ms1 ).

pp_reset :-
    ( catch(nb_getval('$pp_names', Old), _, fail) -> pp_undefine_all(Old) ; true ),
    nb_setval('$pp_names', []), nb_setval('$pp_files', []), nb_setval('$pp_once', []), nb_setval('$pp_stack', []),
    nb_setval('$pp_counter', 0), nb_setval('$pp_errors', []), nb_setval('$pp_paste', no).
pp_undefine_all([]).
pp_undefine_all([N|Ns]) :- pp_key(N, K), nb_setval(K, none), pp_undefine_all(Ns).
pp_key(N, K) :- atom_concat('$pp:', N, K).
%% a macro: its parameters (obj for an object-like one; va(N) the variadic
%% one) and its body -- the codes as defined, the tokens once used
pp_define(N, Ps, Cs) :- pp_key(N, K), nb_setval(K, mac(Ps, codes(Cs))), nb_getval('$pp_names', Ns), nb_setval('$pp_names', [N|Ns]).   % a name twice is harmless: sorted where read
pp_undefine(N) :- pp_key(N, K), nb_setval(K, none).
pp_macro(N, Ps, Body) :-
    pp_key(N, K), catch(nb_getval(K, V), _, fail), V = mac(Ps, B0),
    ( B0 = codes(Cs) -> pp_lex_body(Cs, Body), nb_setval(K, mac(Ps, Body)) ; Body = B0 ).
pp_defined(N) :- ( pp_builtin_name(N) -> true ; pp_key(N, K), catch(nb_getval(K, V), _, fail), V = mac(_, _) ).
pp_builtin_name(N) :- memberchk(N, ['__has_include', '__has_include_next', '__has_feature', '__has_extension', '__has_attribute', '__has_cpp_attribute',
    '__has_c_attribute', '__has_declspec_attribute', '__has_builtin', '__has_warning', '__is_identifier', '__building_module', '__FILE__', '__LINE__',
    '__COUNTER__', '__DATE__', '__TIME__', '__is_target_arch', '__is_target_vendor', '__is_target_os', '__is_target_environment']).

%% the predefined macros: the architecture's and the language's
pp_predefine :-
    pp_arch(A), ccl_lang(L),
    forall(pp_predef(any, N, T), pp_predefine_one(N, T)),
    forall(pp_predef(A, N, T), pp_predefine_one(N, T)),
    ( L == cpp -> forall(pp_predef(cpp, N, T), pp_predefine_one(N, T)) ; true ).
pp_predefine_one(Name, Text) :-
    atom_codes(Name, NCs),
    (   append(N1, [0'(|PCs], NCs) -> atom_codes(N, N1), append(PCs0, [0')], PCs), pp_param_names(PCs0, Ps)
    ;   N = Name, Ps = obj ),
    atom_codes(Text, TCs), pp_define(N, Ps, TCs).
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
pp_lex_line(N, A, Toks) :- ( ccl_lex_atom(A, N, T, _) -> Toks = T ; Toks = [] ).
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
pp_norm(tok(num, Cs, L), T) :- !, nb_getval('$ccl_hash', M), nb_setval('$ccl_hash', line), atom_codes(A, Cs), ( ccl_lex_atom(A, 0, [tok(K, V, _)], []) -> T = tok(K, V, L) ; T = tok(int, 0, L) ), nb_setval('$ccl_hash', M).
pp_norm(T, T).

%% ---- directives -------------------------------------------------------------
pp_directive(Body, L, Ls, Ls1, Out0, Out) :-
    pp_ws(Body, B1), pp_word(B1, W, Rest), atom_codes(D, W),
    pp_directive_(D, Rest, Body, L, Ls, Ls1, Out0, Out).
pp_directive_(define, Rest, _, _, Ls, Ls, Out, Out) :- !, ( pp_do_define(Rest) -> true ; true ).
pp_directive_(undef, Rest, _, _, Ls, Ls, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), pp_undefine(N).
pp_directive_(include, Rest, Body, _, Ls, Ls, Out0, Out) :- !, pp_do_include(Rest, plain, Body, Out0, Out).
pp_directive_(include_next, Rest, Body, _, Ls, Ls, Out0, Out) :- !, pp_do_include(Rest, next, Body, Out0, Out).
pp_directive_(if, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_lex_body(Rest, Ts), ( pp_eval(Ts) -> Ls1 = Ls ; pp_skip_false(Ls, Ls1) ).
pp_directive_(ifdef, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), ( pp_defined(N) -> Ls1 = Ls ; pp_skip_false(Ls, Ls1) ).
pp_directive_(ifndef, Rest, _, _, Ls, Ls1, Out, Out) :- !, pp_ws(Rest, R1), pp_word(R1, W, _), atom_codes(N, W), ( pp_defined(N) -> pp_skip_false(Ls, Ls1) ; Ls1 = Ls ).
pp_directive_(elif, _, _, _, Ls, Ls1, Out, Out) :- !, pp_skip_to_endif(Ls, Ls1).          % a taken group ended: the branches left go
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
pp_do_include(Rest, How, Body, Out0, Out) :-
    pp_ws(Rest, R1),
    (   pp_inc_name(R1, Spec0) -> true
    ;   pp_lex_body(R1, Ts), pp_expand_all(Ts, Es), pp_spell_all(Es, ECs), pp_inc_name(ECs, Spec0) ),
    !,
    ( How == next -> Spec = next(Spec0) ; Spec = Spec0 ),
    pp_current_file(From),
    (   ccl_resolve_include(Spec, From, Path)
    ->  (   sub_atom(Path, _, 3, 0, '.pl') -> atom_codes(Text, [35|Body]), Out0 = [tok(pp, Text, 0)|Out]
        ;   nb_getval('$pp_once', O), memberchk(Path, O) -> Out0 = Out
        ;   pp_include_file(Path, Out0, Out) )
    ;   Out0 = Out ).
pp_do_include(_, _, _, Out, Out).
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
        ;   D =:= 0 -> Found = else, Rest = Ls
        ;   pp_skip_group(Ls, D, Found, Rest) )
    ;   pp_skip_group(Ls, D, Found, Rest) ).
pp_cond_word(if, open). pp_cond_word(ifdef, open). pp_cond_word(ifndef, open).
pp_cond_word(elif, elif). pp_cond_word(else, else). pp_cond_word(endif, endif).
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
pp_normalize([], []).
pp_normalize([tok(kw, true, L)|Ts], [tok(int, 1, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([tok(id, _, L)|Ts], [tok(int, 0, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([tok(kw, _, L)|Ts], [tok(int, 0, L)|Os]) :- !, pp_normalize(Ts, Os).
pp_normalize([T|Ts], [T1|Os]) :- pp_norm(T, T1), pp_normalize(Ts, Os).
pp_predef(any, 'TARGET_IPHONE_SIMULATOR', '0').
pp_predef(any, 'TARGET_OS_DRIVERKIT', '0').
pp_predef(any, 'TARGET_OS_EMBEDDED', '0').
pp_predef(any, 'TARGET_OS_FIRMWARE', '0').
pp_predef(any, 'TARGET_OS_IOS', '0').
pp_predef(any, 'TARGET_OS_IPHONE', '0').
pp_predef(any, 'TARGET_OS_LINUX', '0').
pp_predef(any, 'TARGET_OS_MAC', '1').
pp_predef(any, 'TARGET_OS_MACCATALYST', '0').
pp_predef(any, 'TARGET_OS_NANO', '0').
pp_predef(any, 'TARGET_OS_OSX', '1').
pp_predef(any, 'TARGET_OS_SIMULATOR', '0').
pp_predef(any, 'TARGET_OS_TV', '0').
pp_predef(any, 'TARGET_OS_UEFI', '0').
pp_predef(any, 'TARGET_OS_UIKITFORMAC', '0').
pp_predef(any, 'TARGET_OS_UNIX', '0').
pp_predef(any, 'TARGET_OS_VISION', '0').
pp_predef(any, 'TARGET_OS_WATCH', '0').
pp_predef(any, 'TARGET_OS_WIN32', '0').
pp_predef(any, 'TARGET_OS_WINDOWS', '0').
pp_predef(any, '_LP64', '1').
pp_predef(any, '__APPLE_CC__', '6000').
pp_predef(any, '__APPLE__', '1').
pp_predef(any, '__ATOMIC_ACQUIRE', '2').
pp_predef(any, '__ATOMIC_ACQ_REL', '4').
pp_predef(any, '__ATOMIC_CONSUME', '1').
pp_predef(any, '__ATOMIC_RELAXED', '0').
pp_predef(any, '__ATOMIC_RELEASE', '3').
pp_predef(any, '__ATOMIC_SEQ_CST', '5').
pp_predef(any, '__BLOCKS__', '1').
pp_predef(any, '__BOOL_WIDTH__', '1').
pp_predef(any, '__BYTE_ORDER__', '__ORDER_LITTLE_ENDIAN__').
pp_predef(any, '__CHAR16_TYPE__', 'unsigned short').
pp_predef(any, '__CHAR32_TYPE__', 'unsigned int').
pp_predef(any, '__CHAR_BIT__', '8').
pp_predef(any, '__CLANG_ATOMIC_BOOL_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_CHAR16_T_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_CHAR32_T_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_CHAR_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_INT_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_LLONG_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_LONG_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_POINTER_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_SHORT_LOCK_FREE', '2').
pp_predef(any, '__CLANG_ATOMIC_WCHAR_T_LOCK_FREE', '2').
pp_predef(any, '__CONSTANT_CFSTRINGS__', '1').
pp_predef(any, '__DBL_DECIMAL_DIG__', '17').
pp_predef(any, '__DBL_DENORM_MIN__', '4.9406564584124654e-324').
pp_predef(any, '__DBL_DIG__', '15').
pp_predef(any, '__DBL_EPSILON__', '2.2204460492503131e-16').
pp_predef(any, '__DBL_HAS_DENORM__', '1').
pp_predef(any, '__DBL_HAS_INFINITY__', '1').
pp_predef(any, '__DBL_HAS_QUIET_NAN__', '1').
pp_predef(any, '__DBL_MANT_DIG__', '53').
pp_predef(any, '__DBL_MAX_10_EXP__', '308').
pp_predef(any, '__DBL_MAX_EXP__', '1024').
pp_predef(any, '__DBL_MAX__', '1.7976931348623157e+308').
pp_predef(any, '__DBL_MIN_10_EXP__', '(-307)').
pp_predef(any, '__DBL_MIN_EXP__', '(-1021)').
pp_predef(any, '__DBL_MIN__', '2.2250738585072014e-308').
pp_predef(any, '__DBL_NORM_MAX__', '1.7976931348623157e+308').
pp_predef(any, '__DECIMAL_DIG__', '__LDBL_DECIMAL_DIG__').
pp_predef(any, '__DYNAMIC__', '1').
pp_predef(any, '__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__', '260000').
pp_predef(any, '__ENVIRONMENT_OS_VERSION_MIN_REQUIRED__', '260000').
pp_predef(any, '__FINITE_MATH_ONLY__', '0').
pp_predef(any, '__FLT16_DECIMAL_DIG__', '5').
pp_predef(any, '__FLT16_DENORM_MIN__', '5.9604644775390625e-8F16').
pp_predef(any, '__FLT16_DIG__', '3').
pp_predef(any, '__FLT16_EPSILON__', '9.765625e-4F16').
pp_predef(any, '__FLT16_HAS_DENORM__', '1').
pp_predef(any, '__FLT16_HAS_INFINITY__', '1').
pp_predef(any, '__FLT16_HAS_QUIET_NAN__', '1').
pp_predef(any, '__FLT16_MANT_DIG__', '11').
pp_predef(any, '__FLT16_MAX_10_EXP__', '4').
pp_predef(any, '__FLT16_MAX_EXP__', '16').
pp_predef(any, '__FLT16_MAX__', '6.5504e+4F16').
pp_predef(any, '__FLT16_MIN_10_EXP__', '(-4)').
pp_predef(any, '__FLT16_MIN_EXP__', '(-13)').
pp_predef(any, '__FLT16_MIN__', '6.103515625e-5F16').
pp_predef(any, '__FLT16_NORM_MAX__', '6.5504e+4F16').
pp_predef(any, '__FLT_DECIMAL_DIG__', '9').
pp_predef(any, '__FLT_DENORM_MIN__', '1.40129846e-45F').
pp_predef(any, '__FLT_DIG__', '6').
pp_predef(any, '__FLT_EPSILON__', '1.19209290e-7F').
pp_predef(any, '__FLT_HAS_DENORM__', '1').
pp_predef(any, '__FLT_HAS_INFINITY__', '1').
pp_predef(any, '__FLT_HAS_QUIET_NAN__', '1').
pp_predef(any, '__FLT_MANT_DIG__', '24').
pp_predef(any, '__FLT_MAX_10_EXP__', '38').
pp_predef(any, '__FLT_MAX_EXP__', '128').
pp_predef(any, '__FLT_MAX__', '3.40282347e+38F').
pp_predef(any, '__FLT_MIN_10_EXP__', '(-37)').
pp_predef(any, '__FLT_MIN_EXP__', '(-125)').
pp_predef(any, '__FLT_MIN__', '1.17549435e-38F').
pp_predef(any, '__FLT_NORM_MAX__', '3.40282347e+38F').
pp_predef(any, '__FLT_RADIX__', '2').
pp_predef(any, '__FPCLASS_NEGINF', '0x0004').
pp_predef(any, '__FPCLASS_NEGNORMAL', '0x0008').
pp_predef(any, '__FPCLASS_NEGSUBNORMAL', '0x0010').
pp_predef(any, '__FPCLASS_NEGZERO', '0x0020').
pp_predef(any, '__FPCLASS_POSINF', '0x0200').
pp_predef(any, '__FPCLASS_POSNORMAL', '0x0100').
pp_predef(any, '__FPCLASS_POSSUBNORMAL', '0x0080').
pp_predef(any, '__FPCLASS_POSZERO', '0x0040').
pp_predef(any, '__FPCLASS_QNAN', '0x0002').
pp_predef(any, '__FPCLASS_SNAN', '0x0001').
pp_predef(any, '__GCC_ASM_FLAG_OUTPUTS__', '1').
pp_predef(any, '__GCC_ATOMIC_BOOL_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_CHAR16_T_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_CHAR32_T_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_CHAR_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_INT_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_LLONG_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_LONG_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_POINTER_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_SHORT_LOCK_FREE', '2').
pp_predef(any, '__GCC_ATOMIC_TEST_AND_SET_TRUEVAL', '1').
pp_predef(any, '__GCC_ATOMIC_WCHAR_T_LOCK_FREE', '2').
pp_predef(any, '__GCC_CONSTRUCTIVE_SIZE', '64').
pp_predef(any, '__GCC_HAVE_DWARF2_CFI_ASM', '1').
pp_predef(any, '__GCC_HAVE_SYNC_COMPARE_AND_SWAP_1', '1').
pp_predef(any, '__GCC_HAVE_SYNC_COMPARE_AND_SWAP_16', '1').
pp_predef(any, '__GCC_HAVE_SYNC_COMPARE_AND_SWAP_2', '1').
pp_predef(any, '__GCC_HAVE_SYNC_COMPARE_AND_SWAP_4', '1').
pp_predef(any, '__GCC_HAVE_SYNC_COMPARE_AND_SWAP_8', '1').
pp_predef(any, '__GNUC_MINOR__', '2').
pp_predef(any, '__GNUC_PATCHLEVEL__', '1').
pp_predef(any, '__GNUC_STDC_INLINE__', '1').
pp_predef(any, '__GNUC__', '4').
pp_predef(any, '__GXX_ABI_VERSION', '1002').
pp_predef(any, '__INT16_C(c)', 'c').
pp_predef(any, '__INT16_C_SUFFIX__', '').
pp_predef(any, '__INT16_FMTd__', '"hd"').
pp_predef(any, '__INT16_FMTi__', '"hi"').
pp_predef(any, '__INT16_MAX__', '32767').
pp_predef(any, '__INT16_TYPE__', 'short').
pp_predef(any, '__INT32_C(c)', 'c').
pp_predef(any, '__INT32_C_SUFFIX__', '').
pp_predef(any, '__INT32_FMTd__', '"d"').
pp_predef(any, '__INT32_FMTi__', '"i"').
pp_predef(any, '__INT32_MAX__', '2147483647').
pp_predef(any, '__INT32_TYPE__', 'int').
pp_predef(any, '__INT64_C(c)', 'c##LL').
pp_predef(any, '__INT64_C_SUFFIX__', 'LL').
pp_predef(any, '__INT64_FMTd__', '"lld"').
pp_predef(any, '__INT64_FMTi__', '"lli"').
pp_predef(any, '__INT64_MAX__', '9223372036854775807LL').
pp_predef(any, '__INT64_TYPE__', 'long long int').
pp_predef(any, '__INT8_C(c)', 'c').
pp_predef(any, '__INT8_C_SUFFIX__', '').
pp_predef(any, '__INT8_FMTd__', '"hhd"').
pp_predef(any, '__INT8_FMTi__', '"hhi"').
pp_predef(any, '__INT8_MAX__', '127').
pp_predef(any, '__INT8_TYPE__', 'signed char').
pp_predef(any, '__INTMAX_C(c)', 'c##L').
pp_predef(any, '__INTMAX_C_SUFFIX__', 'L').
pp_predef(any, '__INTMAX_FMTd__', '"ld"').
pp_predef(any, '__INTMAX_FMTi__', '"li"').
pp_predef(any, '__INTMAX_MAX__', '9223372036854775807L').
pp_predef(any, '__INTMAX_TYPE__', 'long int').
pp_predef(any, '__INTMAX_WIDTH__', '64').
pp_predef(any, '__INTPTR_FMTd__', '"ld"').
pp_predef(any, '__INTPTR_FMTi__', '"li"').
pp_predef(any, '__INTPTR_MAX__', '9223372036854775807L').
pp_predef(any, '__INTPTR_TYPE__', 'long int').
pp_predef(any, '__INTPTR_WIDTH__', '64').
pp_predef(any, '__INT_FAST16_FMTd__', '"hd"').
pp_predef(any, '__INT_FAST16_FMTi__', '"hi"').
pp_predef(any, '__INT_FAST16_MAX__', '32767').
pp_predef(any, '__INT_FAST16_TYPE__', 'short').
pp_predef(any, '__INT_FAST16_WIDTH__', '16').
pp_predef(any, '__INT_FAST32_FMTd__', '"d"').
pp_predef(any, '__INT_FAST32_FMTi__', '"i"').
pp_predef(any, '__INT_FAST32_MAX__', '2147483647').
pp_predef(any, '__INT_FAST32_TYPE__', 'int').
pp_predef(any, '__INT_FAST32_WIDTH__', '32').
pp_predef(any, '__INT_FAST64_FMTd__', '"lld"').
pp_predef(any, '__INT_FAST64_FMTi__', '"lli"').
pp_predef(any, '__INT_FAST64_MAX__', '9223372036854775807LL').
pp_predef(any, '__INT_FAST64_TYPE__', 'long long int').
pp_predef(any, '__INT_FAST64_WIDTH__', '64').
pp_predef(any, '__INT_FAST8_FMTd__', '"hhd"').
pp_predef(any, '__INT_FAST8_FMTi__', '"hhi"').
pp_predef(any, '__INT_FAST8_MAX__', '127').
pp_predef(any, '__INT_FAST8_TYPE__', 'signed char').
pp_predef(any, '__INT_FAST8_WIDTH__', '8').
pp_predef(any, '__INT_LEAST16_FMTd__', '"hd"').
pp_predef(any, '__INT_LEAST16_FMTi__', '"hi"').
pp_predef(any, '__INT_LEAST16_MAX__', '32767').
pp_predef(any, '__INT_LEAST16_TYPE__', 'short').
pp_predef(any, '__INT_LEAST16_WIDTH__', '16').
pp_predef(any, '__INT_LEAST32_FMTd__', '"d"').
pp_predef(any, '__INT_LEAST32_FMTi__', '"i"').
pp_predef(any, '__INT_LEAST32_MAX__', '2147483647').
pp_predef(any, '__INT_LEAST32_TYPE__', 'int').
pp_predef(any, '__INT_LEAST32_WIDTH__', '32').
pp_predef(any, '__INT_LEAST64_FMTd__', '"lld"').
pp_predef(any, '__INT_LEAST64_FMTi__', '"lli"').
pp_predef(any, '__INT_LEAST64_MAX__', '9223372036854775807LL').
pp_predef(any, '__INT_LEAST64_TYPE__', 'long long int').
pp_predef(any, '__INT_LEAST64_WIDTH__', '64').
pp_predef(any, '__INT_LEAST8_FMTd__', '"hhd"').
pp_predef(any, '__INT_LEAST8_FMTi__', '"hhi"').
pp_predef(any, '__INT_LEAST8_MAX__', '127').
pp_predef(any, '__INT_LEAST8_TYPE__', 'signed char').
pp_predef(any, '__INT_LEAST8_WIDTH__', '8').
pp_predef(any, '__INT_MAX__', '2147483647').
pp_predef(any, '__INT_WIDTH__', '32').
pp_predef(any, '__LDBL_HAS_DENORM__', '1').
pp_predef(any, '__LDBL_HAS_INFINITY__', '1').
pp_predef(any, '__LDBL_HAS_QUIET_NAN__', '1').
pp_predef(any, '__LITTLE_ENDIAN__', '1').
pp_predef(any, '__LLONG_WIDTH__', '64').
pp_predef(any, '__LONG_LONG_MAX__', '9223372036854775807LL').
pp_predef(any, '__LONG_MAX__', '9223372036854775807L').
pp_predef(any, '__LONG_WIDTH__', '64').
pp_predef(any, '__LP64__', '1').
pp_predef(any, '__MACH__', '1').
pp_predef(any, '__MEMORY_SCOPE_CLUSTR', '5').
pp_predef(any, '__MEMORY_SCOPE_DEVICE', '1').
pp_predef(any, '__MEMORY_SCOPE_SINGLE', '4').
pp_predef(any, '__MEMORY_SCOPE_SYSTEM', '0').
pp_predef(any, '__MEMORY_SCOPE_WRKGRP', '2').
pp_predef(any, '__MEMORY_SCOPE_WVFRNT', '3').
pp_predef(any, '__NO_INLINE__', '1').
pp_predef(any, '__NO_MATH_ERRNO__', '1').
pp_predef(any, '__OPENCL_MEMORY_SCOPE_ALL_SVM_DEVICES', '3').
pp_predef(any, '__OPENCL_MEMORY_SCOPE_DEVICE', '2').
pp_predef(any, '__OPENCL_MEMORY_SCOPE_SUB_GROUP', '4').
pp_predef(any, '__OPENCL_MEMORY_SCOPE_WORK_GROUP', '1').
pp_predef(any, '__OPENCL_MEMORY_SCOPE_WORK_ITEM', '0').
pp_predef(any, '__ORDER_BIG_ENDIAN__', '4321').
pp_predef(any, '__ORDER_LITTLE_ENDIAN__', '1234').
pp_predef(any, '__ORDER_PDP_ENDIAN__', '3412').
pp_predef(any, '__PIC__', '2').
pp_predef(any, '__POINTER_WIDTH__', '64').
pp_predef(any, '__PRAGMA_REDEFINE_EXTNAME', '1').
pp_predef(any, '__PTRDIFF_FMTd__', '"ld"').
pp_predef(any, '__PTRDIFF_FMTi__', '"li"').
pp_predef(any, '__PTRDIFF_MAX__', '9223372036854775807L').
pp_predef(any, '__PTRDIFF_TYPE__', 'long int').
pp_predef(any, '__PTRDIFF_WIDTH__', '64').
pp_predef(any, '__REGISTER_PREFIX__', '').
pp_predef(any, '__SCHAR_MAX__', '127').
pp_predef(any, '__SHRT_MAX__', '32767').
pp_predef(any, '__SHRT_WIDTH__', '16').
pp_predef(any, '__SIG_ATOMIC_MAX__', '2147483647').
pp_predef(any, '__SIG_ATOMIC_MIN__', '(-__SIG_ATOMIC_MAX__ - 1)').
pp_predef(any, '__SIG_ATOMIC_TYPE__', 'int').
pp_predef(any, '__SIG_ATOMIC_WIDTH__', '32').
pp_predef(any, '__SIZEOF_DOUBLE__', '8').
pp_predef(any, '__SIZEOF_FLOAT__', '4').
pp_predef(any, '__SIZEOF_INT128__', '16').
pp_predef(any, '__SIZEOF_INT__', '4').
pp_predef(any, '__SIZEOF_LONG_LONG__', '8').
pp_predef(any, '__SIZEOF_LONG__', '8').
pp_predef(any, '__SIZEOF_POINTER__', '8').
pp_predef(any, '__SIZEOF_PTRDIFF_T__', '8').
pp_predef(any, '__SIZEOF_SHORT__', '2').
pp_predef(any, '__SIZEOF_SIZE_T__', '8').
pp_predef(any, '__SIZEOF_WCHAR_T__', '4').
pp_predef(any, '__SIZEOF_WINT_T__', '4').
pp_predef(any, '__SIZE_FMTX__', '"lX"').
pp_predef(any, '__SIZE_FMTo__', '"lo"').
pp_predef(any, '__SIZE_FMTu__', '"lu"').
pp_predef(any, '__SIZE_FMTx__', '"lx"').
pp_predef(any, '__SIZE_MAX__', '18446744073709551615UL').
pp_predef(any, '__SIZE_TYPE__', 'long unsigned int').
pp_predef(any, '__SIZE_WIDTH__', '64').
pp_predef(any, '__SSP__', '1').
pp_predef(any, '__STDC_EMBED_EMPTY__', '2').
pp_predef(any, '__STDC_EMBED_FOUND__', '1').
pp_predef(any, '__STDC_EMBED_NOT_FOUND__', '0').
pp_predef(any, '__STDC_HOSTED__', '1').
pp_predef(any, '__STDC_NO_THREADS__', '1').
pp_predef(any, '__STDC_UTF_16__', '1').
pp_predef(any, '__STDC_UTF_32__', '1').
pp_predef(any, '__STDC_VERSION__', '201710L').
pp_predef(any, '__STDC__', '1').
pp_predef(any, '__UINT16_C(c)', 'c').
pp_predef(any, '__UINT16_C_SUFFIX__', '').
pp_predef(any, '__UINT16_FMTX__', '"hX"').
pp_predef(any, '__UINT16_FMTo__', '"ho"').
pp_predef(any, '__UINT16_FMTu__', '"hu"').
pp_predef(any, '__UINT16_FMTx__', '"hx"').
pp_predef(any, '__UINT16_MAX__', '65535').
pp_predef(any, '__UINT16_TYPE__', 'unsigned short').
pp_predef(any, '__UINT32_C(c)', 'c##U').
pp_predef(any, '__UINT32_C_SUFFIX__', 'U').
pp_predef(any, '__UINT32_FMTX__', '"X"').
pp_predef(any, '__UINT32_FMTo__', '"o"').
pp_predef(any, '__UINT32_FMTu__', '"u"').
pp_predef(any, '__UINT32_FMTx__', '"x"').
pp_predef(any, '__UINT32_MAX__', '4294967295U').
pp_predef(any, '__UINT32_TYPE__', 'unsigned int').
pp_predef(any, '__UINT64_C(c)', 'c##ULL').
pp_predef(any, '__UINT64_C_SUFFIX__', 'ULL').
pp_predef(any, '__UINT64_FMTX__', '"llX"').
pp_predef(any, '__UINT64_FMTo__', '"llo"').
pp_predef(any, '__UINT64_FMTu__', '"llu"').
pp_predef(any, '__UINT64_FMTx__', '"llx"').
pp_predef(any, '__UINT64_MAX__', '18446744073709551615ULL').
pp_predef(any, '__UINT64_TYPE__', 'long long unsigned int').
pp_predef(any, '__UINT8_C(c)', 'c').
pp_predef(any, '__UINT8_C_SUFFIX__', '').
pp_predef(any, '__UINT8_FMTX__', '"hhX"').
pp_predef(any, '__UINT8_FMTo__', '"hho"').
pp_predef(any, '__UINT8_FMTu__', '"hhu"').
pp_predef(any, '__UINT8_FMTx__', '"hhx"').
pp_predef(any, '__UINT8_MAX__', '255').
pp_predef(any, '__UINT8_TYPE__', 'unsigned char').
pp_predef(any, '__UINTMAX_C(c)', 'c##UL').
pp_predef(any, '__UINTMAX_C_SUFFIX__', 'UL').
pp_predef(any, '__UINTMAX_FMTX__', '"lX"').
pp_predef(any, '__UINTMAX_FMTo__', '"lo"').
pp_predef(any, '__UINTMAX_FMTu__', '"lu"').
pp_predef(any, '__UINTMAX_FMTx__', '"lx"').
pp_predef(any, '__UINTMAX_MAX__', '18446744073709551615UL').
pp_predef(any, '__UINTMAX_TYPE__', 'long unsigned int').
pp_predef(any, '__UINTMAX_WIDTH__', '64').
pp_predef(any, '__UINTPTR_FMTX__', '"lX"').
pp_predef(any, '__UINTPTR_FMTo__', '"lo"').
pp_predef(any, '__UINTPTR_FMTu__', '"lu"').
pp_predef(any, '__UINTPTR_FMTx__', '"lx"').
pp_predef(any, '__UINTPTR_MAX__', '18446744073709551615UL').
pp_predef(any, '__UINTPTR_TYPE__', 'long unsigned int').
pp_predef(any, '__UINTPTR_WIDTH__', '64').
pp_predef(any, '__UINT_FAST16_FMTX__', '"hX"').
pp_predef(any, '__UINT_FAST16_FMTo__', '"ho"').
pp_predef(any, '__UINT_FAST16_FMTu__', '"hu"').
pp_predef(any, '__UINT_FAST16_FMTx__', '"hx"').
pp_predef(any, '__UINT_FAST16_MAX__', '65535').
pp_predef(any, '__UINT_FAST16_TYPE__', 'unsigned short').
pp_predef(any, '__UINT_FAST32_FMTX__', '"X"').
pp_predef(any, '__UINT_FAST32_FMTo__', '"o"').
pp_predef(any, '__UINT_FAST32_FMTu__', '"u"').
pp_predef(any, '__UINT_FAST32_FMTx__', '"x"').
pp_predef(any, '__UINT_FAST32_MAX__', '4294967295U').
pp_predef(any, '__UINT_FAST32_TYPE__', 'unsigned int').
pp_predef(any, '__UINT_FAST64_FMTX__', '"llX"').
pp_predef(any, '__UINT_FAST64_FMTo__', '"llo"').
pp_predef(any, '__UINT_FAST64_FMTu__', '"llu"').
pp_predef(any, '__UINT_FAST64_FMTx__', '"llx"').
pp_predef(any, '__UINT_FAST64_MAX__', '18446744073709551615ULL').
pp_predef(any, '__UINT_FAST64_TYPE__', 'long long unsigned int').
pp_predef(any, '__UINT_FAST8_FMTX__', '"hhX"').
pp_predef(any, '__UINT_FAST8_FMTo__', '"hho"').
pp_predef(any, '__UINT_FAST8_FMTu__', '"hhu"').
pp_predef(any, '__UINT_FAST8_FMTx__', '"hhx"').
pp_predef(any, '__UINT_FAST8_MAX__', '255').
pp_predef(any, '__UINT_FAST8_TYPE__', 'unsigned char').
pp_predef(any, '__UINT_LEAST16_FMTX__', '"hX"').
pp_predef(any, '__UINT_LEAST16_FMTo__', '"ho"').
pp_predef(any, '__UINT_LEAST16_FMTu__', '"hu"').
pp_predef(any, '__UINT_LEAST16_FMTx__', '"hx"').
pp_predef(any, '__UINT_LEAST16_MAX__', '65535').
pp_predef(any, '__UINT_LEAST16_TYPE__', 'unsigned short').
pp_predef(any, '__UINT_LEAST32_FMTX__', '"X"').
pp_predef(any, '__UINT_LEAST32_FMTo__', '"o"').
pp_predef(any, '__UINT_LEAST32_FMTu__', '"u"').
pp_predef(any, '__UINT_LEAST32_FMTx__', '"x"').
pp_predef(any, '__UINT_LEAST32_MAX__', '4294967295U').
pp_predef(any, '__UINT_LEAST32_TYPE__', 'unsigned int').
pp_predef(any, '__UINT_LEAST64_FMTX__', '"llX"').
pp_predef(any, '__UINT_LEAST64_FMTo__', '"llo"').
pp_predef(any, '__UINT_LEAST64_FMTu__', '"llu"').
pp_predef(any, '__UINT_LEAST64_FMTx__', '"llx"').
pp_predef(any, '__UINT_LEAST64_MAX__', '18446744073709551615ULL').
pp_predef(any, '__UINT_LEAST64_TYPE__', 'long long unsigned int').
pp_predef(any, '__UINT_LEAST8_FMTX__', '"hhX"').
pp_predef(any, '__UINT_LEAST8_FMTo__', '"hho"').
pp_predef(any, '__UINT_LEAST8_FMTu__', '"hhu"').
pp_predef(any, '__UINT_LEAST8_FMTx__', '"hhx"').
pp_predef(any, '__UINT_LEAST8_MAX__', '255').
pp_predef(any, '__UINT_LEAST8_TYPE__', 'unsigned char').
pp_predef(any, '__USER_LABEL_PREFIX__', '_').
pp_predef(any, '__WCHAR_MAX__', '2147483647').
pp_predef(any, '__WCHAR_MIN__', '(-__WCHAR_MAX__ - 1)').
pp_predef(any, '__WCHAR_TYPE__', 'int').
pp_predef(any, '__WCHAR_WIDTH__', '32').
pp_predef(any, '__WINT_MAX__', '2147483647').
pp_predef(any, '__WINT_MIN__', '(-__WINT_MAX__ - 1)').
pp_predef(any, '__WINT_TYPE__', 'int').
pp_predef(any, '__WINT_WIDTH__', '32').
pp_predef(any, '__block', '__attribute__((__blocks__(byref)))').
pp_predef(any, '__clang__', '1').
pp_predef(any, '__clang_major__', '23').
pp_predef(any, '__clang_minor__', '1').
pp_predef(any, '__clang_patchlevel__', '0').
pp_predef(any, '__llvm__', '1').
pp_predef(any, '__nonnull', '_Nonnull').
pp_predef(any, '__null_unspecified', '_Null_unspecified').
pp_predef(any, '__nullable', '_Nullable').
pp_predef(any, '__pic__', '2').
pp_predef(any, '__strong', '').
pp_predef(any, '__unsafe_unretained', '').
pp_predef(any, '__weak', '__attribute__((objc_gc(weak)))').
pp_predef(x86_64, '__BIGGEST_ALIGNMENT__', '16').
pp_predef(x86_64, '__BITINT_MAXWIDTH__', '8388608').
pp_predef(x86_64, '__FXSR__', '1').
pp_predef(x86_64, '__GCC_DESTRUCTIVE_SIZE', '64').
pp_predef(x86_64, '__LAHF_SAHF__', '1').
pp_predef(x86_64, '__LDBL_DECIMAL_DIG__', '21').
pp_predef(x86_64, '__LDBL_DENORM_MIN__', '3.64519953188247460253e-4951L').
pp_predef(x86_64, '__LDBL_DIG__', '18').
pp_predef(x86_64, '__LDBL_EPSILON__', '1.08420217248550443401e-19L').
pp_predef(x86_64, '__LDBL_MANT_DIG__', '64').
pp_predef(x86_64, '__LDBL_MAX_10_EXP__', '4932').
pp_predef(x86_64, '__LDBL_MAX_EXP__', '16384').
pp_predef(x86_64, '__LDBL_MAX__', '1.18973149535723176502e+4932L').
pp_predef(x86_64, '__LDBL_MIN_10_EXP__', '(-4931)').
pp_predef(x86_64, '__LDBL_MIN_EXP__', '(-16381)').
pp_predef(x86_64, '__LDBL_MIN__', '3.36210314311209350626e-4932L').
pp_predef(x86_64, '__LDBL_NORM_MAX__', '1.18973149535723176502e+4932L').
pp_predef(x86_64, '__MMX__', '1').
pp_predef(x86_64, '__NO_MATH_INLINES', '1').
pp_predef(x86_64, '__OBJC_BOOL_IS_BOOL', '0').
pp_predef(x86_64, '__SEG_FS', '1').
pp_predef(x86_64, '__SEG_GS', '1').
pp_predef(x86_64, '__SIZEOF_LONG_DOUBLE__', '16').
pp_predef(x86_64, '__SSE2_MATH__', '1').
pp_predef(x86_64, '__SSE2__', '1').
pp_predef(x86_64, '__SSE3__', '1').
pp_predef(x86_64, '__SSE4_1__', '1').
pp_predef(x86_64, '__SSE_MATH__', '1').
pp_predef(x86_64, '__SSE__', '1').
pp_predef(x86_64, '__SSSE3__', '1').
pp_predef(x86_64, '__amd64', '1').
pp_predef(x86_64, '__amd64__', '1').
pp_predef(x86_64, '__code_model_small__', '1').
pp_predef(x86_64, '__core2', '1').
pp_predef(x86_64, '__core2__', '1').
pp_predef(x86_64, '__seg_fs', '__attribute__((address_space(257)))').
pp_predef(x86_64, '__seg_gs', '__attribute__((address_space(256)))').
pp_predef(x86_64, '__tune_core2__', '1').
pp_predef(x86_64, '__x86_64', '1').
pp_predef(x86_64, '__x86_64__', '1').
pp_predef(arm64, '__AARCH64EL__', '1').
pp_predef(arm64, '__AARCH64_CMODEL_SMALL__', '1').
pp_predef(arm64, '__AARCH64_SIMD__', '1').
pp_predef(arm64, '__ARM64_ARCH_8__', '1').
pp_predef(arm64, '__ARM_64BIT_STATE', '1').
pp_predef(arm64, '__ARM_ACLE', '202420').
pp_predef(arm64, '__ARM_ACLE_VERSION(year,quarter,patch)', '(100 * (year) + 10 * (quarter) + (patch))').
pp_predef(arm64, '__ARM_ALIGN_MAX_STACK_PWR', '4').
pp_predef(arm64, '__ARM_ARCH', '8').
pp_predef(arm64, '__ARM_ARCH_ISA_A64', '1').
pp_predef(arm64, '__ARM_ARCH_PROFILE', '\'A\'').
pp_predef(arm64, '__ARM_FEATURE_AES', '1').
pp_predef(arm64, '__ARM_FEATURE_ATOMICS', '1').
pp_predef(arm64, '__ARM_FEATURE_CLZ', '1').
pp_predef(arm64, '__ARM_FEATURE_COMPLEX', '1').
pp_predef(arm64, '__ARM_FEATURE_CRC32', '1').
pp_predef(arm64, '__ARM_FEATURE_CRYPTO', '1').
pp_predef(arm64, '__ARM_FEATURE_DIRECTED_ROUNDING', '1').
pp_predef(arm64, '__ARM_FEATURE_DIV', '1').
pp_predef(arm64, '__ARM_FEATURE_DOTPROD', '1').
pp_predef(arm64, '__ARM_FEATURE_FMA', '1').
pp_predef(arm64, '__ARM_FEATURE_FP16_FML', '1').
pp_predef(arm64, '__ARM_FEATURE_FP16_SCALAR_ARITHMETIC', '1').
pp_predef(arm64, '__ARM_FEATURE_FP16_VECTOR_ARITHMETIC', '1').
pp_predef(arm64, '__ARM_FEATURE_IDIV', '1').
pp_predef(arm64, '__ARM_FEATURE_JCVT', '1').
pp_predef(arm64, '__ARM_FEATURE_LDREX', '0xF').
pp_predef(arm64, '__ARM_FEATURE_NUMERIC_MAXMIN', '1').
pp_predef(arm64, '__ARM_FEATURE_PAUTH', '1').
pp_predef(arm64, '__ARM_FEATURE_QRDMX', '1').
pp_predef(arm64, '__ARM_FEATURE_RCPC', '1').
pp_predef(arm64, '__ARM_FEATURE_SHA2', '1').
pp_predef(arm64, '__ARM_FEATURE_SHA3', '1').
pp_predef(arm64, '__ARM_FEATURE_SHA512', '1').
pp_predef(arm64, '__ARM_FEATURE_UNALIGNED', '1').
pp_predef(arm64, '__ARM_FP', '0xE').
pp_predef(arm64, '__ARM_FP16_ARGS', '1').
pp_predef(arm64, '__ARM_FP16_FORMAT_IEEE', '1').
pp_predef(arm64, '__ARM_NEON', '1').
pp_predef(arm64, '__ARM_NEON_FP', '0xE').
pp_predef(arm64, '__ARM_NEON_SVE_BRIDGE', '1').
pp_predef(arm64, '__ARM_NEON__', '1').
pp_predef(arm64, '__ARM_PCS_AAPCS64', '1').
pp_predef(arm64, '__ARM_PREFETCH_RANGE', '1').
pp_predef(arm64, '__ARM_SIZEOF_MINIMAL_ENUM', '4').
pp_predef(arm64, '__ARM_SIZEOF_WCHAR_T', '4').
pp_predef(arm64, '__ARM_STATE_ZA', '1').
pp_predef(arm64, '__ARM_STATE_ZT0', '1').
pp_predef(arm64, '__BIGGEST_ALIGNMENT__', '8').
pp_predef(arm64, '__BITINT_MAXWIDTH__', '128').
pp_predef(arm64, '__FP_FAST_FMA', '1').
pp_predef(arm64, '__FP_FAST_FMAF', '1').
pp_predef(arm64, '__FUNCTION_MULTI_VERSIONING_SUPPORT_LEVEL', '202430').
pp_predef(arm64, '__GCC_DESTRUCTIVE_SIZE', '128').
pp_predef(arm64, '__HAVE_FUNCTION_MULTI_VERSIONING', '1').
pp_predef(arm64, '__LDBL_DECIMAL_DIG__', '17').
pp_predef(arm64, '__LDBL_DENORM_MIN__', '4.9406564584124654e-324L').
pp_predef(arm64, '__LDBL_DIG__', '15').
pp_predef(arm64, '__LDBL_EPSILON__', '2.2204460492503131e-16L').
pp_predef(arm64, '__LDBL_MANT_DIG__', '53').
pp_predef(arm64, '__LDBL_MAX_10_EXP__', '308').
pp_predef(arm64, '__LDBL_MAX_EXP__', '1024').
pp_predef(arm64, '__LDBL_MAX__', '1.7976931348623157e+308L').
pp_predef(arm64, '__LDBL_MIN_10_EXP__', '(-307)').
pp_predef(arm64, '__LDBL_MIN_EXP__', '(-1021)').
pp_predef(arm64, '__LDBL_MIN__', '2.2250738585072014e-308L').
pp_predef(arm64, '__LDBL_NORM_MAX__', '1.7976931348623157e+308L').
pp_predef(arm64, '__OBJC_BOOL_IS_BOOL', '1').
pp_predef(arm64, '__SIZEOF_LONG_DOUBLE__', '8').
pp_predef(arm64, '__aarch64__', '1').
pp_predef(arm64, '__arm64', '1').
pp_predef(arm64, '__arm64__', '1').
pp_predef(cpp, '__DEPRECATED', '1').
pp_predef(cpp, '__EXCEPTIONS', '1').
pp_predef(cpp, '__GLIBCXX_BITSIZE_INT_N_0', '128').
pp_predef(cpp, '__GLIBCXX_TYPE_INT_N_0', '__int128').
pp_predef(cpp, '__GNUC_GNU_INLINE__', '1').
pp_predef(cpp, '__GNUG__', '4').
pp_predef(cpp, '__GXX_EXPERIMENTAL_CXX0X__', '1').
pp_predef(cpp, '__GXX_RTTI', '1').
pp_predef(cpp, '__GXX_WEAK__', '1').
pp_predef(cpp, '__STDCPP_DEFAULT_NEW_ALIGNMENT__', '16UL').
pp_predef(cpp, '__STDCPP_THREADS__', '1').
pp_predef(cpp, '__cplusplus', '201703L').
pp_predef(cpp, '__cpp_aggregate_bases', '201603L').
pp_predef(cpp, '__cpp_aggregate_nsdmi', '201304L').
pp_predef(cpp, '__cpp_alias_templates', '200704L').
pp_predef(cpp, '__cpp_aligned_new', '201606L').
pp_predef(cpp, '__cpp_attributes', '200809L').
pp_predef(cpp, '__cpp_binary_literals', '201304L').
pp_predef(cpp, '__cpp_capture_star_this', '201603L').
pp_predef(cpp, '__cpp_constexpr', '201603L').
pp_predef(cpp, '__cpp_constexpr_in_decltype', '201711L').
pp_predef(cpp, '__cpp_decltype', '200707L').
pp_predef(cpp, '__cpp_decltype_auto', '201304L').
pp_predef(cpp, '__cpp_deduction_guides', '201703L').
pp_predef(cpp, '__cpp_delegating_constructors', '200604L').
pp_predef(cpp, '__cpp_deleted_function', '202403L').
pp_predef(cpp, '__cpp_digit_separators', '201309L').
pp_predef(cpp, '__cpp_enumerator_attributes', '201411L').
pp_predef(cpp, '__cpp_exceptions', '199711L').
pp_predef(cpp, '__cpp_fold_expressions', '201603L').
pp_predef(cpp, '__cpp_generic_lambdas', '201304L').
pp_predef(cpp, '__cpp_guaranteed_copy_elision', '201606L').
pp_predef(cpp, '__cpp_hex_float', '201603L').
pp_predef(cpp, '__cpp_if_constexpr', '201606L').
pp_predef(cpp, '__cpp_impl_destroying_delete', '201806L').
pp_predef(cpp, '__cpp_inheriting_constructors', '201511L').
pp_predef(cpp, '__cpp_init_captures', '201304L').
pp_predef(cpp, '__cpp_initializer_lists', '200806L').
pp_predef(cpp, '__cpp_inline_variables', '201606L').
pp_predef(cpp, '__cpp_lambdas', '200907L').
pp_predef(cpp, '__cpp_named_character_escapes', '202606L').
pp_predef(cpp, '__cpp_namespace_attributes', '201411L').
pp_predef(cpp, '__cpp_nested_namespace_definitions', '201411L').
pp_predef(cpp, '__cpp_noexcept_function_type', '201510L').
pp_predef(cpp, '__cpp_nontype_template_args', '201411L').
pp_predef(cpp, '__cpp_nontype_template_parameter_auto', '201606L').
pp_predef(cpp, '__cpp_nsdmi', '200809L').
pp_predef(cpp, '__cpp_pack_indexing', '202311L').
pp_predef(cpp, '__cpp_placeholder_variables', '202306L').
pp_predef(cpp, '__cpp_range_based_for', '201603L').
pp_predef(cpp, '__cpp_raw_strings', '200710L').
pp_predef(cpp, '__cpp_ref_qualifiers', '200710L').
pp_predef(cpp, '__cpp_return_type_deduction', '201304L').
pp_predef(cpp, '__cpp_rtti', '199711L').
pp_predef(cpp, '__cpp_rvalue_references', '200610L').
pp_predef(cpp, '__cpp_sized_deallocation', '201309L').
pp_predef(cpp, '__cpp_static_assert', '202306L').
pp_predef(cpp, '__cpp_static_call_operator', '202207L').
pp_predef(cpp, '__cpp_structured_bindings', '202411L').
pp_predef(cpp, '__cpp_template_auto', '201606L').
pp_predef(cpp, '__cpp_template_template_args', '201611L').
pp_predef(cpp, '__cpp_threadsafe_static_init', '200806L').
pp_predef(cpp, '__cpp_trivial_relocatability', '202502L').
pp_predef(cpp, '__cpp_unicode_characters', '200704L').
pp_predef(cpp, '__cpp_unicode_literals', '200710L').
pp_predef(cpp, '__cpp_user_defined_literals', '200809L').
pp_predef(cpp, '__cpp_variable_templates', '201304L').
pp_predef(cpp, '__cpp_variadic_friend', '202403L').
pp_predef(cpp, '__cpp_variadic_templates', '200704L').
pp_predef(cpp, '__cpp_variadic_using', '201611L').
pp_predef(cpp, '__private_extern__', 'extern').
