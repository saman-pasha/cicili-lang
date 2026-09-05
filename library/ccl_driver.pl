%% cicili-lang -- library(ccl_driver): what the `cicili' command does, once
%% bin/cicili has read its arguments the way clang reads them.
%%
%%   ccl_drive(+Inputs, +Options)
%%     Inputs   files: .c (read, checked, lowered), .ll (compiled as IR),
%%              .o .a .so .dylib (handed to the linker)
%%     Options  compile_only (-c), assembly (-S), emit_llvm (-emit-llvm),
%%              syntax_only (-fsyntax-only), ast (-ast-dump), out(File) (-o),
%%              opt(Flag) ('-O2' ...), include(Dir) (-I), link(Flag) (-l -L
%%              -shared -framework ...), verbose (-v)
%%
%% Every .c goes through cicili_ast, cicili_ir and cicili_compile; then, unless
%% -c, -S, -emit-llvm or -fsyntax-only, everything links into one output
%% (a.out when -o is not given), as clang does. A diagnostic is printed as
%% clang prints one -- file:line: error: what -- and the run ends `cicili: N
%% error(s)'; a clean run ends `cicili: ok'.

:- use_module(library(process)).

ccl_drive(Inputs, Options) :- once(dr_drive(Inputs, Options)).          % one answer: the query loop would re-run a second
dr_drive(Inputs, Options) :-
    nb_setval('$dr_errors', 0),
    forall(member(include(D), Options), assertz(ccl_include_dir(D))),
    ( memberchk(opt(O), Options) -> Flags = [O] ; Flags = ['-O0'] ),
    ( memberchk(verbose, Options) -> nb_setval('$dr_verbose', yes) ; nb_setval('$dr_verbose', no) ),
    dr_inputs(Inputs, Options, Flags, Objects),
    nb_getval('$dr_errors', N),
    (   N > 0 -> true
    ;   ( dr_no_link(Options) ; Objects == [] ) -> true
    ;   ( memberchk(out(Out), Options) -> true ; Out = 'a.out' ),
        findall(F, member(link(F), Options), LinkFlags),
        dr_say(['link ', Out]),
        catch(cicili_link(Objects, LinkFlags, Out), E, dr_report(Out, E)) ),
    nb_getval('$dr_errors', N1),
    ( N1 =:= 0 -> write('cicili: ok') ; write('cicili: '), write(N1), write(' error(s)') ), nl.
dr_no_link(O) :- ( memberchk(compile_only, O) ; memberchk(assembly, O) ; memberchk(emit_llvm, O) ; memberchk(syntax_only, O) ; memberchk(ast, O) ), !.

dr_inputs([], _, _, []).
dr_inputs([F|Fs], Options, Flags, Objects) :-
    dr_input(F, Options, Flags, Objects, Objects1),
    dr_inputs(Fs, Options, Flags, Objects1).
dr_input(F, Options, Flags, Objs, Objs1) :-
    (   dr_ext(F, c) -> dr_c(F, Options, Flags, Objs, Objs1)
    ;   dr_ext(F, ll) -> dr_ll(F, Options, Flags, Objs, Objs1)
    ;   ( dr_ext(F, o) ; dr_ext(F, a) ; dr_ext(F, so) ; dr_ext(F, dylib) ) -> Objs = [F|Objs1]
    ;   dr_error(F, 0, ['unknown kind of file']), Objs = Objs1 ).
dr_ext(F, E) :- atom_concat('.', E, Dot), sub_atom(F, _, _, 0, Dot).

%% a .c: read (headers, macros, := ...), the safe part, the IR, then what the options ask
dr_c(F, Options, Flags, Objs, Objs1) :-
    dr_say(['read ', F]), nb_setval('$dr_expansions', []),
    (   catch(cicili_ast(F, AST), E1, (dr_report(F, E1), fail))
    ->  dr_remember_expansions(AST),
        (   memberchk(ast, Options) -> writeq(AST), nl, Objs = Objs1
        ;   dr_say(['check and lower ', F]),
            (   catch(cicili_ir([AST], IR), E2, (dr_report(F, E2), fail))
            ->  dr_emit(F, IR, Options, Flags, Objs, Objs1)
            ;   Objs = Objs1 ) )
    ;   Objs = Objs1 ).
dr_ll(F, Options, Flags, Objs, Objs1) :-
    read_file_to_codes(F, Cs), atom_codes(IR, Cs), dr_emit(F, IR, Options, Flags, Objs, Objs1).
dr_emit(F, IR, Options, Flags, Objs, Objs1) :-
    (   memberchk(syntax_only, Options) -> Objs = Objs1
    ;   memberchk(emit_llvm, Options) -> dr_out(F, Options, ll, Out), dr_say(['write ', Out]), atom_codes(IR, Cs), write_file_from_codes(Out, Cs), Objs = Objs1
    ;   memberchk(assembly, Options) -> dr_out(F, Options, s, Out), dr_say(['assemble ', Out]), dr_compile(F, IR, Out, ['-S'|Flags]), Objs = Objs1
    ;   memberchk(compile_only, Options) -> dr_out(F, Options, o, Out), dr_say(['compile ', Out]), dr_compile(F, IR, Out, Flags), Objs = Objs1
    ;   tmp_file(cicili, T), atom_concat(T, '.o', Out), dr_say(['compile ', F]), ( dr_compile(F, IR, Out, Flags) -> Objs = [Out|Objs1] ; Objs = Objs1 ) ).
dr_compile(F, IR, Out, Flags) :- catch(cicili_compile(IR, Out, Flags), E, (dr_report(F, E), fail)).
%% the output name: -o, else the input's basename with the new extension, in the working directory
dr_out(_, Options, _, Out) :- memberchk(out(Out), Options), !.
dr_out(F, _, Ext, Out) :-
    ( sub_atom(F, B, _, 0, Base0), sub_atom(F, B1, 1, _, '/'), B1 < B, \+ sub_atom(Base0, _, _, _, '/') -> true ; Base0 = F ),
    dr_basename(F, Base), ( sub_atom(Base, S, _, 0, '.c') -> sub_atom(Base, 0, S, _, Stem) ; sub_atom(Base, S, _, 0, '.ll') -> sub_atom(Base, 0, S, _, Stem) ; Stem = Base ),
    atomic_list_concat([Stem, '.', Ext], Out).
dr_basename(F, B) :- atom_codes(F, Cs), dr_after_slash(Cs, Bs), atom_codes(B, Bs).
dr_after_slash(Cs, Bs) :- ( append(_, [0'/|R], Cs), \+ memberchk(0'/, R) -> Bs = R ; Bs = Cs ).

%% the unit's expansions, for the note under a diagnostic on an expanded line
dr_remember_expansions(unit(Is)) :- !, ( append(_, ['$expansions'(Es)], Is) -> nb_setval('$dr_expansions', Es) ; nb_setval('$dr_expansions', []) ).
dr_remember_expansions(_).
dr_note_expansion(F, L) :-
    ( nb_getval('$dr_expansions', Es), member(expansion(L, N, As), Es)
    -> write(F), write(':'), write(L), write(': note: expanded from macro \''), write(N), write('\' on '), dr_args(As), nl
    ; true ).
dr_args([]).
dr_args([A]) :- !, writeq(A).
dr_args([A|As]) :- writeq(A), write(', '), dr_args(As).

%% ---- diagnostics, clang's shape ---------------------------------------------------------
%% once: the callers' recovery fails after reporting, and must not report twice
dr_report(F, error(E, W)) :- !, once(dr_diag(F, E, W)).
dr_report(F, E) :- once(dr_error(F, 0, [E])).
dr_diag(_, syntax_error(cicili_ast(File, line(L), near(N))), _) :- !, dr_error(File, L, ['syntax error: could not read this item (gave up near line ', N, ')']).
dr_diag(_, syntax_error(cicili_ast(File, lexical, line(L))), _) :- !, dr_error(File, L, ['lexical error']).
dr_diag(F, cannot_infer(N, E), here(_, L)) :- !, dr_error(F, L, ['cannot infer the type of ', N, ' from ', E]).
dr_diag(F, no_member(What, T), here(_, L)) :- !, dr_error(F, L, ['no member ', What, ' in ', T]).
dr_diag(F, macro_error(M, here(_, L)), _) :- !, dr_error(F, L, ['macro: ', M]).
%% an error inside a macro: the call site, then where it went wrong in the macro
dr_diag(F, macro_error(N, As, E), here(_, L, in_macro(P, MF))) :- !,
    dr_prolog_error(E, Text), dr_error(F, L, ['in the expansion of macro \'', N, '\': ', Text]), dr_note_macro(F, L, P, MF, As).
dr_diag(F, macro_failed(N, As), here(_, L, in_macro(P, MF))) :- !,
    dr_error(F, L, ['macro \'', N, '\' failed: no result for these arguments']), dr_note_macro(F, L, P, MF, As).
dr_diag(F, macro_error(N, As, E), _) :- !, dr_prolog_error(E, Text), dr_error(F, 0, ['in the expansion of macro \'', N, '\' on ', As, ': ', Text]).
dr_diag(F, macro_failed(N, As), _) :- !, dr_error(F, 0, ['macro \'', N, '\' failed on ', As]).
dr_diag(F, ownership(Kind, N, Form), where(Fn, line(L))) :- !, dr_kind(Kind, Text), dr_error(F, L, [Text, ' ''', N, ''' in ', Form, ' (function ', Fn, ')']).
dr_diag(F, not_lowered(What), where(Fn, line(L))) :- !, dr_error(F, L, ['not lowered yet: ', What, ' (function ', Fn, ')']).
dr_diag(F, compile_failed(Msg), _) :- !, dr_error(F, 0, ['LLVM: ', Msg]).
dr_diag(F, cocolog_error(Msg), _) :- !, dr_error(F, 0, ['LLVM: ', Msg]).            % the embedded LLVM's refusal
dr_diag(F, link_failed(Msg), _) :- !, dr_error(F, 0, ['link: ', Msg]).
dr_diag(F, E, W) :- dr_error(F, 0, [E, ' ', W]).
dr_kind(use_after_move, 'use after move of') :- !.
dr_kind(borrow_after_move, 'use of a borrow after its owner was consumed:') :- !.
dr_kind(borrow_escapes, 'a borrow leaves the function:') :- !.
dr_kind(owner_leaked, 'owner leaked:') :- !.
dr_kind(move_in_loop, 'owner consumed inside a loop:') :- !.
dr_kind(move_of_non_owner, 'move of a non-owner:') :- !.
dr_kind(owner_overwritten, 'owner overwritten while live:') :- !.
dr_kind(goto_with_owners, 'goto in a function with owners, at label') :- !.
dr_kind(K, K).
dr_error(F, L, Parts) :-
    nb_getval('$dr_errors', N), N1 is N + 1, nb_setval('$dr_errors', N1),
    write(F), ( L > 0 -> write(':'), write(L) ; true ), write(': error: '), dr_write(Parts), nl,
    ( L > 0 -> dr_note_expansion(F, L) ; true ).
dr_note_macro(F, L, P, MF, As) :-
    write(F), write(':'), write(L), write(': note: the macro is '), write(P), write(' in '), write(MF), write(', called on '), dr_args(As), nl.
%% a Prolog error, said plainly
dr_prolog_error(error(existence_error(procedure, PI), _), T) :- !, dr_join(['the macro calls ', PI, ', which does not exist'], T).
dr_prolog_error(error(type_error(Ty, C), _), T) :- !, dr_join(['expected a ', Ty, ', got ', C], T).
dr_prolog_error(error(instantiation_error, _), T) :- !, T = 'an argument was left unbound'.
dr_prolog_error(error(macro_error(M, _), _), T) :- !, dr_join(['the macro said: ', M], T).
dr_prolog_error(error(E, _), T) :- !, dr_join(['it threw ', E], T).
dr_prolog_error(E, T) :- dr_join(['it threw ', E], T).
dr_join(Parts, A) :- dr_join_codes(Parts, Cs), atom_codes(A, Cs).
dr_join_codes([], []).
dr_join_codes([P|Ps], Cs) :- ( atom(P) -> atom_codes(P, C) ; term_to_atom(P, A), atom_codes(A, C) ), dr_join_codes(Ps, Cs1), append(C, Cs1, Cs).
dr_write([]).
dr_write([P|Ps]) :- ( atomic(P) -> write(P) ; writeq(P) ), dr_write(Ps).
dr_say(Parts) :- ( nb_getval('$dr_verbose', yes) -> write('cicili: '), dr_write(Parts), nl ; true ).
