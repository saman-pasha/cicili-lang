// MULTIPLE INHERITANCE where a base after the first has storage of its own
// ([class.derived]: the non-virtual bases in declaration order, then the class's
// own members; an empty one takes no bytes). std::tuple is built this way -- one
// __tuple_leaf base per element -- and std::bind stores its bound arguments in one.
#include <cstdio>
struct A { int a; A(int x) : a(x) {} int ga() const { return a; } };
struct B { int b; B(int x) : b(x * 2) {} int gb() const { return b; } };
struct E { int tag() const { return 7; } };                       // empty: no sub-object
struct C : A, B, E {
    int c;
    C(int x) : A(x), B(x), c(x * 3) {}
    int sum() const { return ga() + gb() + c + tag(); }
};
struct Tag { int t; Tag(int v) : t(v * 100) {} int gt() const { return t; } };
struct D : C, Tag {
    D(int x, int v) : C(x), Tag(v) {}
};
int main() {
    C c(5);
    printf("%d %d %d %d\n", c.a, c.b, c.c, c.sum());
    A *pa = &c; B *pb = &c;                                       // each base at its own offset
    printf("%d %d\n", pa->ga(), pb->gb());
    printf("%d\n", (int) sizeof(C));                             // the empty base takes no bytes
    D d(2, 9);
    printf("%d %d %d\n", d.a, d.sum(), d.gt());
    C c2 = c;                                                     // the memberwise copy takes every base
    printf("%d %d %d\n", c2.a, c2.b, c2.c);
    return 0;
}
