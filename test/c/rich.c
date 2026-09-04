/* one of everything the reader must take: typedefs, structs, enums, a
 * function pointer, arrays, every statement, every operator level, casts,
 * sizeof, initializers with designators, adjacent strings, a label. */
#include <stdio.h>
#define LIMIT 10

typedef unsigned long ulong;
typedef struct point { int x, y; } point_t;
enum color { RED, GREEN = 5, BLUE };
struct node { struct node *next; point_t at; unsigned flags : 3; };

static int square(int n) { return n * n; }
int apply(int (*f)(int), int v);
int apply(int (*f)(int), int v) { return f(v); }

const char *names[] = { "zero", "one", [3] = "three" };
point_t origin = { .x = 0, .y = 0 };
double ratio = 1.5e3;
ulong big = 0xFFul;
char sep = '\n';

int main(int argc, char **argv) {
    int i, total = 0;
    unsigned mask = ~0u;
    point_t p = { 1, 2 };
    struct node n = { 0 };
    for (i = 0; i < LIMIT; i++) {
        if (i % 2 == 0) continue;
        else if (i > 7) break;
        total += square(i);
    }
    while (total > 100) total -= 3;
    do { total++; } while (total < 5);
    switch (argc) {
        case 1: total = apply(square, total); break;
        case 2: default: total = -total;
    }
    total = argc > 1 ? (int) ratio : (int) sizeof(point_t) + sizeof p.x;
    mask = (mask << 2 | 3) & ~(1u << 4) ^ 0x0F;
    n.at = p; n.next = &n; n.next->flags = 5;
    p.x = names[1][0] + argv[0][0];
    i = (total, mask, 3);
    if (!(i && total || !mask)) goto done;
    printf("%d %s\n", total, "a" "b");
done:
    return total >= 0 && total <= 1000 ? 0 : 1;
}
