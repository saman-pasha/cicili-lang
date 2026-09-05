#include <stdio.h>
#include <stdlib.h>
#include "../macros.pl"
point { int x; double y; }
int main(void) {
    n := 6;
    p := (point){ 2, 1.5 };
    { a, y: b } := p;
    q := &p;
    println("n = {} sq = {} p = {p} a = {a} b = {b}", n, square(n));
    s := format("{}-{}", a, q->x);
    print("{s} {}\n", sum(1, 2, 3));
    free(s);
    swap(a, n);
    println("{a} {n}");
    return a + n;
}
