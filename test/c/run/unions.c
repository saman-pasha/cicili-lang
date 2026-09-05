#include <stdio.h>
/* unions: every member at the union's address; a scalar of its alignment, padded to its size */
union num { int i; double d; unsigned char b[8]; };
struct tagged { int kind; union num v; };
union num g = { 7 };                                    /* a global: the first member, padded */
int main(void) {
    union num u;
    u.d = 1.5;
    printf("%g %lu %lu\n", u.d, sizeof(union num), sizeof u);
    u.i = 1094861636;                                   /* 'A' 'B' 'C' 'D', little-endian */
    printf("%c%c%c%c\n", u.b[0], u.b[1], u.b[2], u.b[3]);
    struct tagged t = { 1, { 42 } };
    printf("%d %d %d %lu\n", t.kind, t.v.i, g.i, sizeof(struct tagged));
    union num w = u;                                    /* copied whole */
    t.v.d = 2.5;
    printf("%d %g\n", w.i, t.v.d);
    return 0;
}
