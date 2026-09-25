#include <cstdio>
// the comma operator in a constant expression (libc++'s __all is written on it), and a prvalue preferring T &&
template <bool... Ps> struct dummy {};
template <class A, class B> struct same { static const bool value = false; };
template <class A> struct same<A, A> { static const bool value = true; };
template <bool... Ps> using all = same<dummy<Ps...>, dummy<((void) Ps, true)...>>;
struct S { int v; S(int x) : v(x) {} };
S mk(int x) { return S(x); }
struct T { int v; T(const S &s) : v(s.v + 100) {} T(S &&s) : v(s.v + 200) {} };
template <class U> struct W { int v; template <class V> W(const V &x) : v(x.v + 100) {} template <class V> W(V &&x) : v(x.v + 200) {} };
int main() {
  printf("%d %d %d\n", (int) all<true, true>::value, (int) all<true, false>::value, (int) all<>::value);
  T t(mk(1)); S s(2); T u(s);
  W<int> w(mk(3)); W<int> x(s);
  printf("%d %d %d %d\n", t.v, u.v, w.v, x.v);
  return 0;
}
