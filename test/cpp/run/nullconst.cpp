// A NULL POINTER CONSTANT CONVERTS TO ANY POINTER ([conv.ptr]/1): libc++'s stable_partition writes
// `pair<value_type *, ptrdiff_t> __p(0, 0);' and the pair's (const _T1 &, const _T2 &) constructor
// was refused for the literal 0. The three roads: a plain call, a class TEMPLATE's constructor
// written over `const A &', and a function template's parameter.
#include <cstdio>
static int two(int *p, long n) { return (p == 0) + (int) n; }
template <class A, class B> struct T2 {
    int n;
    T2(const A &a, const B &b) : n((a == 0) + (int) b) { }
};
template <class A, class B> int tmpl(A a, B b) { return (a == 0) + (int) b; }
struct Plain { int n; Plain(int *p, long k) : n((p == 0) + (int) k) { } };
int main() {
    setvbuf(stdout, 0, _IONBF, 0);
    printf("%d\n", two(0, 5));
    T2<int *, long> t(0, 4);
    printf("%d\n", t.n);
    int v = 7;
    T2<int *, long> u(&v, 3);
    printf("%d\n", u.n);
    printf("%d\n", tmpl<int *, long>(0, 9));
    Plain p(0, 1);
    printf("%d\n", p.n);
    return 0;
}
