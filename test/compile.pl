%% cicili-lang -- the compiler's gate, as one cocolog program: every
%% test/c/run/NAME.c read, checked, lowered, compiled and linked to
%% $CCL_TEST_TMP/NAME in ONE process over the store, so the system headers
%% are loaded once; every test/c/safe/NAME.c read and checked, expected to
%% be refused. Each line is `built NAME', `refused NAME ownership(K, N)',
%% `compiled NAME' (a safe one that was not refused), or `FAIL NAME: what'.
%% test/compile.sh runs it, then runs the binaries and compares.
%%
%%   CCL_TEST_ROOT=<repo> CCL_TEST_TMP=<dir> cocolog --embed <store> query "ensure_loaded('test/compile.pl'), compile_main"

:- use_module(library(cicili)).
:- use_module(library(os)).

compile_main :-
    os_env('CCL_TEST_ROOT', Root), os_env('CCL_TEST_TMP', D),
    atom_concat(Root, '/test/c/run', RunDir), atom_concat(Root, '/test/c/safe', SafeDir),
    c_sources(RunDir, Runs), c_sources(SafeDir, Safes),
    build_all(Runs, RunDir, D),
    refuse_all(Safes, SafeDir),
    write('done'), nl.

c_sources(Dir, Names) :-
    directory_files(Dir, Fs), findall(N, ( member(F, Fs), atom_concat(N, '.c', F) ), Ns0), sort(Ns0, Names).

build_all([], _, _).
build_all([N|Ns], Dir, D) :- build_one(N, Dir, D), build_all(Ns, Dir, D).
build_one(N, Dir, D) :-
    atomic_list_concat([Dir, '/', N, '.c'], Src), atomic_list_concat([D, '/', N, '.o'], Obj), atomic_list_concat([D, '/', N], Bin),
    (   catch(( cicili_ast(Src, A), cicili_ir([A], IR), cicili_compile(IR, Obj, ['-O1']), cicili_link([Obj], [], Bin) ), E, (write('FAIL '), write(N), write(': '), write(E), nl, fail))
    ->  write('built '), write(N), nl
    ;   true ).

refuse_all([], _).
refuse_all([N|Ns], Dir) :- refuse_one(N, Dir), refuse_all(Ns, Dir).
refuse_one(N, Dir) :-
    atomic_list_concat([Dir, '/', N, '.c'], Src),
    (   catch(( cicili_ast(Src, A), cicili_ir([A], _) ), E, true)
    ->  (   var(E) -> write('compiled '), write(N), nl
        ;   E = error(ownership(K, V, _), _) -> write('refused '), write(N), write(' ownership('), write(K), write(','), write(V), write(')'), nl
        ;   write('FAIL '), write(N), write(': '), write(E), nl )
    ;   write('FAIL '), write(N), write(': the read or the check failed'), nl ).
