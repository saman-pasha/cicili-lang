%% cicili-lang -- the road to libc++: the gate that says how far the compiler goes
%% with the standard library as it ships. One check per header: flattened by
%% cocolog's preprocessor and read WHOLE by the reader, under a fresh HOME so no
%% summary stands in (the summaries it writes are this run's).
%%
%%   HOME=$D CCL_TEST_TMP=$D cocolog --local query "ensure_loaded('test/libcxx.pl'), libcxx_main"
:- use_module(library(cicili)).

libcxx_main :-
    nb_setval('$lx_fail', 0),
    forall(member(H-Min, [vector-400, string-400]), libcxx_header(H, Min)),
    nb_getval('$lx_fail', N),
    ( N =:= 0 -> write('GREEN: libc++ (the reader)') ; write('RED: '), write(N), write(' failure(s)') ), nl.

libcxx_header(H, Min) :-
    os_env('CCL_TEST_TMP', D), atomic_list_concat([D, '/inc_', H, '.cpp'], F),
    atomic_list_concat(['#include <', H, '>\n'], Text), atom_codes(Text, Cs), write_file_from_codes(F, Cs),
    (   catch(cicili_ast(F, unit(Is)), E, (print_message(error, E), fail)),
        member(include(_, system(H), file(_, preprocessed, U)), Is)
    ->  (   U = unit(Items) -> length(Items, K),
            ( K >= Min -> format("ok   <~w> flattened and read whole: ~w items~n", [H, K]) ; format("FAIL <~w> read whole but only ~w items~n", [H, K]), libcxx_fail )
        ;   U = partial(unit(Items), line(L), near(Far)) -> length(Items, K), format("FAIL <~w> read PARTIAL: ~w items, stopped at line ~w, farthest ~w~n", [H, K, L, Far]), libcxx_fail
        ;   format("FAIL <~w>: ~w~n", [H, U]), libcxx_fail )
    ;   format("FAIL <~w> could not be read~n", [H]), libcxx_fail ).
libcxx_fail :- nb_getval('$lx_fail', N), N1 is N + 1, nb_setval('$lx_fail', N1).
