#include <stdio.h>
#include <stdlib.h>
point { int x; double y; }

/* an own pointer parameter takes the struct over: the callee must consume it */
static void drop(own point *p) { printf("drop (%d, %g)\n", p->x, p->y); free(p); }

/* a plain pointer parameter only looks: the caller still owns */
static double norm(const point *p) { return p->x * p->x + p->y * p->y; }

/* an own return: the caller receives an owner */
static own point *make(int x, double y) { own point *p = malloc(sizeof *p); p->x = x; p->y = y; return p; }

int main(void) {
    own point *a = make(3, 4.0);
    printf("norm %g\n", norm(a));            /* a is used, not consumed */
    a->x = 6;
    { x, y: yy } := a;                       /* a pattern through the pointer, a use */
    printf("%d %g\n", x, yy);
    drop(a);                                 /* a is consumed here */
    own point *b = make(1, 1.0);
    defer(b) { drop(b); }                    /* consumed at main's exit */
    printf("norm %g\n", norm(b));
    return 0;
}
