#include <cstdio>
struct dtag {};
struct vtag {};
template <class T> struct is_dc { static const bool value = true; };
template <bool B, class T = void> struct enable_if {};
template <class T> struct enable_if<true, T> { typedef T type; };
template <bool B, class T = void> using enable_if_t = typename enable_if<B, T>::type;
template <class T, bool> struct dep : T {};
struct End { int *left; End() : left(nullptr) {} };
template <class T, int I> struct elem {
  elem(dtag) {}
  elem(vtag) : v() {}
  template <class U> explicit elem(U &&u) : v(u) {}
  T &get() { return v; }
  T v;
};
template <class T1, class T2> struct cpair : private elem<T1, 0>, private elem<T2, 1> {
  using B1 = elem<T1, 0>;
  using B2 = elem<T2, 1>;
  template <bool D = true, class = enable_if_t<dep<is_dc<T1>, D>::value && dep<is_dc<T2>, D>::value>>
  cpair() : B1(vtag()), B2(vtag()) {}
  T1 &first() { return static_cast<B1 &>(*this).get(); }
  T2 &second() { return static_cast<B2 &>(*this).get(); }
};
struct tree { cpair<End, int> p; tree() : p() {} };
int main() {
  cpair<End, int> c;
  tree t;
  printf("%d %d %d %d\n", c.first().left == nullptr, c.second(), t.p.first().left == nullptr, t.p.second());
  return 0;
}
