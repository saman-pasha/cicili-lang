%% CICILI++ 03 -- modules: a scope for objects, and static calls
%%
%%     COCOLOG_LIBRARY=$PWD/library cocolog run tutorials/03-modules.pl main
%%
%% `:- module(Name).' ... `:- end_module.' is a scope: an object declared
%% inside is Name::Object, a parent named inside resolves by its short
%% name, and new/3 takes the full name from outside. (cocolog's own
%% `:- module(Name, Exports).' keeps its meaning; this is the one-argument
%% form.) A class used as a receiver is a static call, Self unbound -- a
%% method that touches no slot works that way, like a static member
%% function.

:- use_module(library(cicili)).

:- module(geometry).

:- object(shape).
   state(name = shape).
   area(0).
   describe(D) :- area(A), format(atom(D), "a ~w of area ~2f", [name, A]).
:- end_object.

:- object(circle, extends(shape)).
   state(name = circle).
   state(r = 1).
   area(A) :- A is pi * r * r.
:- end_object.

:- object(rect, extends(shape)).
   state(name = rectangle).
   state(w = 1).
   state(h = 1).
   area(A) :- A is w * h.
   square(S, R) :- new(rect, [name = square, w = S, h = S], R).   % a factory, static
:- end_object.

:- end_module.

main :-
    objects(Os), show('the objects', Os),
    new(geometry::circle, [r = 2], C), C::describe(D1), show('a circle', D1),
    geometry::rect::square(3, Sq), Sq::describe(D2), show('a square, from a static call', D2),
    findall(N-A, ( instances(geometry::shape, Is), member(I, Is), slot(I, name, N), I::area(A0), A is round(A0) ), L),
    show('every shape, by area', L),
    format("~ndone~n").

show(What, Value) :- format("   ~w = ~w~n", [What, Value]).
