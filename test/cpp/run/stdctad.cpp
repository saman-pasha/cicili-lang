#include <cstdio>
template <class P, class N> struct R {
    P p; N n;
    R(P a, N b) : p(a), n(b) {}
};
template <class A> auto make(A q, unsigned long k) { return R{q, k}; }
struct Agg { int a; double b; };
int main() {
    int x = 3;
    auto r = make(x, 2ul);
    printf("%d %d\n", r.p, (int) r.n);
    R s(x, 5ul);
    printf("%d\n", (int) s.n);
    return 0;
}
