// AN EMPTY CLASS HAS SIZE ONE ([class]/4) and an empty BASE takes no bytes (the empty
// base optimization): the two rules are one rule. libc++'s allocators, comparators,
// tuple leaves and __weak_result_type are empty bases everywhere.
#include <cstdio>
struct E { };
struct E2 { };
struct D : E { int x; };                       // an empty base takes no bytes
struct DD : E, E2 { int x; };
struct Holds { E e; int x; };                  // a MEMBER of empty class type takes one
struct Counted { static int made; Counted() { made++; } int tag() const { return 7; } };
int Counted::made = 0;
struct UsesC : Counted { int y; UsesC(int v) : y(v) {} };
int main() {
    printf("%d %d %d\n", (int) sizeof(E), (int) sizeof(D), (int) sizeof(DD));
    printf("%d %d\n", (int) sizeof(Holds), (int) sizeof(UsesC));
    E a[3];
    printf("%d %d\n", (int) sizeof(a), (int) (&a[1] != &a[0]));
    UsesC u(5);
    Counted *pc = &u;                           // converting to an empty base: offset 0
    printf("%d %d %d\n", u.y, u.tag(), Counted::made);
    printf("%d %d\n", (int) ((void *) pc == (void *) &u), pc->tag());
    return 0;
}
