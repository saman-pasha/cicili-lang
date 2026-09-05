/* #cocolog ... #end: cocolog in place, its predicates macros */
#cocolog
twice(X, bin('*', X, int(2))).
sq(X, R) :- R = bin('*', X, X).
greet(call(id(puts), [str(T)])) --> [str(S)], { append([104, 105, 32], S, T) }.
#end
int f(int a) { return twice(a) + sq(a); }
void g(void) { greet("bob"); }
