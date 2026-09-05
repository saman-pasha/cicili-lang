/* #cocolog ... #end: a macro file written in place, its predicates macros
   from that line on; a DCG rule is a variadic one */
#include <stdio.h>
#cocolog
twice(X, bin('*', X, int(2))).
%% sum(a, b, c...): a + b + c ..., folded at read time
sum(R) --> [A], sum_rest(A, R).
sum_rest(A, R) --> [B], !, sum_rest(bin('+', A, B), R).
sum_rest(A, A) --> [].
#end
int main(void) {
    printf("%d %d\n", twice(21), sum(1, 2, 3, 4));
    return 0;
}
