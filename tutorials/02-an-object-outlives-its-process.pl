%% CICILI++ 02 -- an object outlives the process that made it
%%
%%     COCOLOG_LIBRARY=$PWD/library cocolog --embed /tmp/cpp02 run tutorials/02-an-object-outlives-its-process.pl make
%%     COCOLOG_LIBRARY=$PWD/library cocolog --embed /tmp/cpp02 run tutorials/02-an-object-outlives-its-process.pl continue
%%     COCOLOG_LIBRARY=$PWD/library cocolog --embed /tmp/cpp02 run tutorials/02-an-object-outlives-its-process.pl main
%%
%% This is what building on cocolog buys. An instance is clauses in the
%% store -- '$instance'/2 and one '$value'/3 per slot -- so under --embed it
%% is there for the next process, with its state as the last process left
%% it. `make' creates an account and deposits; `continue', run later, from
%% another process, withdraws from the same account; `main' runs both in
%% one process so the suite can see the whole story end in `done'.
%%
%% The instance's name is what new/3 answered ('account#1'); a program that
%% needs to find its objects again keeps that name, or asks instances/2.

:- use_module(library(cicili)).

:- object(account).
   state(owner = nobody).
   state(balance = 0).
   deposit(Amount)  :- Amount > 0, balance := balance + Amount.
   withdraw(Amount) :- Amount =< balance, balance := balance - Amount.
   statement(S)     :- format(atom(S), "~w has ~w", [owner, balance]).
:- end_object.

make :-
    new(account, [owner = ada], A),
    A::deposit(100), A::deposit(50),
    A::statement(S), format("made ~w: ~w~n", [A, S]).

continue :-
    ( instances(account, [A|_])
    -> A::withdraw(30), A::statement(S), format("continued ~w: ~w~n", [A, S])
    ;  write('no account in this store: run make first'), nl ).

main :-
    forall(instances(account, Is), forall(member(I, Is), delete(I))),   % a clean start
    make, continue,
    instances(account, [A]), slot(A, balance, B),
    ( B =:= 120 -> write('   the balance is 120: both steps saw one account'), nl ; true ),
    format("~ndone~n").
