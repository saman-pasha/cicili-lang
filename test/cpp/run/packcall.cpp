// A BOUND TYPE PARAMETER CALLED: the ARGUMENTS ARE SUBSTITUTED FIRST and the arity read off the result, since
// a PACK EXPANSION is ONE element until it expands. `_TupleDst(std::get<_Indices>(std::forward<_TupleSrc>
// (__src))...)' -- how libc++'s tuple_cat builds its answer -- was taken for the one-argument functional cast
// and its pattern substituted whole, refusing pack_unexpanded.
#include <cstdio>
typedef unsigned long size_t_;

template <size_t_... I> struct iseq { };
template <size_t_... I> using indices = iseq<I...>;

struct Src { int v[3]; };
template <size_t_ N> int at(const Src &s) { return s.v[N]; }

struct Three { int a, b, c; Three(int x, int y, int z) : a(x), b(y), c(z) { } };
struct One { int n; One(int x) : n(x) { } };

template <class Dst, class S, size_t_... I> Dst pick(S &&s, indices<I...>) { return Dst(at<I>(s)...); }
template <class Dst, size_t_ I> Dst one(const Src &s) { return Dst(at<I>(s)); }   // ONE argument, no pack
template <class T> T zero() { return T(); }                                      // none

int main() {
    Src s; s.v[0] = 4; s.v[1] = 5; s.v[2] = 6;
    Three t = pick<Three>(s, indices<0, 1, 2>());
    printf("%d %d %d\n", t.a, t.b, t.c);
    One u = one<One, 1>(s);
    printf("%d\n", u.n);
    printf("%d\n", zero<int>());
    return 0;
}
