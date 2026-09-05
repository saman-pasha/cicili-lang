/* clone(p): a fresh copy of what p points to, a new owner -- so a function
   with an own parameter takes the copy and p stays */
#include <stdio.h>
#include <stdlib.h>
typedef struct point { int x, y; } point;
static int sum(own point *p) { int s = p->x + p->y; free(p); return s; }
int main(void) {
    own point *p = malloc(sizeof(point));
    p->x = 3; p->y = 4;
    printf("%d\n", sum(clone(p)));      /* the copy is consumed, p is not */
    p->x = 10;
    printf("%d\n", sum(clone(p)));
    own point *q = clone(p);            /* a copy kept: an owner of its own */
    q->y = 100;
    printf("%d %d\n", p->y, q->y);
    free(q);
    free(p);
    return 0;
}
