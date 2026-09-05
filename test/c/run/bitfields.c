#include <stdio.h>
/* bitfields: packed as C packs them (SysV), read and written through their run of bytes */
struct flags { unsigned a : 3; unsigned b : 5; int c; signed d : 4; char e; unsigned long big : 40; unsigned tail : 2; };
struct packed { char c; int b : 3; };
struct flags g = { 5, 17, 300, -3, 'x', 123456789012, 2 };     /* a global: packed into its bytes at compile time */
int main(void) {
    struct flags f = { 1, 2, 3, -1, 'y', 4, 1 };
    printf("%u %u %d %d %c %lu %u\n", f.a, f.b, f.c, f.d, f.e, f.big, f.tail);
    f.a = 7; f.b += 30; f.d = -8; f.tail++; f.big = 123456789012;   /* b wraps in its five bits */
    printf("%u %u %d %u %lu\n", f.a, f.b, f.d, f.tail, f.big);
    f.a += 1;                                                       /* wraps to 0 */
    printf("%u %d\n", f.a, f.d);
    printf("%u %u %d %d %c %lu %u\n", g.a, g.b, g.c, g.d, g.e, g.big, g.tail);
    struct packed p = { 'z', -2 };
    printf("%c %d %lu %lu %lu\n", p.c, p.b, sizeof(struct flags), sizeof(struct packed), sizeof g);
    return 0;
}
