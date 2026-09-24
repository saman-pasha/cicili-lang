// 0.93: the braced forms on scalars and a template's defaults, found on the road to libc++ 18 at C++20
#include <cstdio>
#include <type_traits>
struct P { int a; int b; int c; };
struct S { int m; };
template <class T> T g(T a, int b = 5) { return a + b; }
template <class T> struct copyc : std::integral_constant<bool, __is_constructible(T, std::__add_lvalue_reference_t<typename std::add_const<T>::type>)> {};
int f(int a, int b = {}, int c = {7}) { return a + b + c; }
int h(const int *p = {}) { return p == 0; }
int main() {
  int z{}; int x{5}; double d{1.5};
  P p = { .a = 1, .b{2}, .c{3} };
  printf("%d %d %g %d %d %d\n", z, x, d, p.a, p.b, p.c);
  printf("%d %d %d %d\n", f(1), f(1, {2}), f(1, {}, {}), h());
  printf("%d %d\n", g(1), g(1, 2));
  printf("%d %d %d %d\n", (int) std::is_copy_constructible<int *>::value, (int) std::is_copy_constructible<S>::value,
         (int) copyc<S>::value, (int) __is_same(typename std::add_const<int *>::type, int *const));
  return 0;
}
