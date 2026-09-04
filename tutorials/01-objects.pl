%% CICILI++ 01 -- objects: a scope with state, methods over it, and a child
%%
%%     COCOLOG_LIBRARY=$PWD/library cocolog run tutorials/01-objects.pl main
%%
%% The whole language in one file. An object is a named scope; `state/1'
%% gives it slots with their starting values; a method is a predicate
%% written inside the object that may read a slot by its name and assign it
%% with `:='. `extends' gives a child the parent's slots and methods;
%% `super::' reaches the parent's version of a method the child redefines.
%% `new/3' makes an instance, `::' sends it a message.
%%
%%     object(+Name)  object(+Name, extends(+Parent))  end_object
%%     state(Slot = Initial)
%%     Slot := Expr                in a method body; Slot alone reads it
%%     new(+Class, +[Slot = V ...], -Instance)
%%     Instance::Message           super::Message   Class::Message (a static call, Self unbound)
%%     instance_of(?Instance, ?Class)   slot(+Instance, ?Slot, ?Value)

:- use_module(library(cicili)).

:- object(counter).
   state(count = 0).
   next(N) :- count := count + 1, N = count.
   reset   :- count := 0.
:- end_object.

:- object(named_counter, extends(counter)).
   state(name = anonymous).
   label(L) :- format(atom(L), "~w: ~w", [name, count]).
   reset    :- super::reset, name := anonymous.
:- end_object.

main :-
    new(named_counter, [name = clicks], C),
    C::next(_), C::next(N),
    show('two messages later, count', N),
    C::label(L), show('label', L),
    C::reset, C::label(L2), show('after reset', L2),
    ( instance_of(C, named_counter) -> Is = yes ; Is = no ), show('an instance of named_counter', Is),
    ( instance_of(C, counter) -> IsP = yes ; IsP = no ), show('and so of counter', IsP),
    slot(C, count, Cnt), show('the slot read from outside', Cnt),
    format("~ndone~n").

show(What, Value) :- format("   ~w = ~w~n", [What, Value]).
