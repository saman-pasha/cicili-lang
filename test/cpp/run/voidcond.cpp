// a conditional over two void arms: evaluated for its effects, no value ([expr.cond]/2)
#include <cstdio>
static int n = 0;
static void inc() { n += 1; }
static void dec() { n -= 1; }
struct S { void up() { n += 10; } void down() { n -= 10; } };
int main() {
    for (int i = 0; i < 5; i++) (i % 2 == 0) ? inc() : dec();
    printf("%d\n", n);
    S s;
    bool up = true;
    up ? s.up() : s.down();
    up = false;
    up ? s.up() : s.down();
    printf("%d\n", n);
    int k = 3;
    k > 2 ? (void) (k = 7) : (void) (k = 9);
    printf("%d\n", k);
    return 0;
}
