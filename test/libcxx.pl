%% cicili-lang -- the road to libc++: the gate that says how far the compiler goes
%% with the standard library as it ships. One check per header: flattened by
%% cocolog's preprocessor and read WHOLE by the reader, under a fresh HOME so no
%% summary stands in (the summaries it writes are this run's).
%%
%%   HOME=$D CCL_TEST_TMP=$D cocolog --local query "ensure_loaded('test/libcxx.pl'), libcxx_main"
:- use_module(library(cicili)).

libcxx_main :-
    nb_setval('$lx_fail', 0),
    forall(member(H-Min, [vector-400, string-400, iostream-600, map-400, set-400, unordered_map-300, unordered_set-300, optional-150, memory-300, functional-400,
                          at(set, 20)-450, at(map, 20)-450, at(unordered_map, 20)-350, at(unordered_set, 20)-350, at(optional, 23)-250, at(string, 23)-450, at(optional, 26)-250]),   % the levels: C++20's concepts and ranges, C++23's monadic optional, C++26's optional<T &>
           libcxx_header(H, Min)),
    nb_getval('$lx_fail', N),
    ( N =:= 0 -> write('GREEN: libc++ (the reader)') ; write('RED: '), write(N), write(' failure(s)') ), nl.

libcxx_header(at(H, Std), Min) :- !,                                          % a header at a LEVEL: the read under -std=c++Std (its summary is the level's own)
    nb_setval('$ccl_std', Std), nb_setval('$ccl_unit_paths', []),                            % the units read so far are FORGOTTEN: a header is read once per process by its path (ccl_unit_cached), and the C++17 read would be served to the level's check (it was: the same item counts)
    ( libcxx_header_(H, Std, Min) -> nb_setval('$ccl_std', 17), nb_setval('$ccl_unit_paths', []) ; nb_setval('$ccl_std', 17), nb_setval('$ccl_unit_paths', []), fail ).
libcxx_header(H, Min) :- libcxx_header_(H, 17, Min).
libcxx_header_(H, Std, Min) :-
    os_env('CCL_TEST_TMP', D), atomic_list_concat([D, '/inc_', H, '_', Std, '.cpp'], F),
    atomic_list_concat(['#include <', H, '>\n'], Text), atom_codes(Text, Cs), write_file_from_codes(F, Cs),
    (   catch(cicili_ast(F, unit(Is)), E, (print_message(error, E), fail)),
        member(include(_, system(H), file(_, preprocessed, U)), Is)
    ->  (   U = unit(Items) -> length(Items, K),
            ( K >= Min -> format("ok   <~w> at C++~w flattened and read whole: ~w items~n", [H, Std, K]) ; format("FAIL <~w> at C++~w read whole but only ~w items~n", [H, Std, K]), libcxx_fail )
        ;   U = partial(unit(Items), line(L), near(Far)) -> length(Items, K), format("FAIL <~w> at C++~w read PARTIAL: ~w items, stopped at line ~w, farthest ~w~n", [H, Std, K, L, Far]), libcxx_fail
        ;   format("FAIL <~w> at C++~w: ~w~n", [H, Std, U]), libcxx_fail )
    ;   format("FAIL <~w> at C++~w could not be read~n", [H, Std]), libcxx_fail ).
libcxx_fail :- nb_getval('$lx_fail', N), N1 is N + 1, nb_setval('$lx_fail', N1).
