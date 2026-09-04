#include "macros.pl"
typedef struct point { int x; double y; } point_t;
struct node { struct node *next; point_t at; };
counter(hits);
pair(lo, hi);
int f(int a, long b, point_t p, struct node *n, char *s) {
    const char *t1 = typename(a);
    const char *t2 = typename(a + 1.5);
    const char *t4 = typename(n->at.x);
    const char *t6 = typename(f(1, 2, p, n, s) + b);
    int sz = size(p);
    swap(a, b);
    return square(a) + sum(a, 2, 3);
}
