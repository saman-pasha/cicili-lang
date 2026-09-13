// A CONSTEXPR FUNCTION OF ONE `return' FOLDS where a constant is asked for: libc++'s pair
// chooses its constructors by `__enable_if_t<_CheckArgsDep::template __is_pair_constructible
// <_U1, _U2>(), int> = 0', a static constexpr member function template over two traits. Here:
// the same shape on the program's own classes, a static const from a constexpr call with an
// argument, and the same function called at run time.
#include <stdio.h>

template <class T, T v> struct ic { static constexpr T value = v; };
template <class T> struct is_int : ic<bool, false> {};
template <> struct is_int<int> : ic<bool, true> {};
template <> struct is_int<long> : ic<bool, true> {};
template <bool, class T = void> struct eif {};
template <class T> struct eif<true, T> { typedef T type; };

template <class A, class B> struct chk {
  template <class U1, class U2> static constexpr bool both() { return is_int<U1>::value && is_int<U2>::value; }
  static constexpr bool first() { return is_int<A>::value; }
  static constexpr int twice(int n) { return n * 2; }
};

template <class T1, class T2> struct pr {
  T1 first; T2 second;
  template <class C = chk<T1, T2>, typename eif<C::template both<T1, T2>(), int>::type = 0>
  constexpr pr(T1 a, T2 b) : first(a), second(b) {}
  static constexpr int width = chk<T1, T2>::twice(3);      // a static const from a constexpr call
};

int main() {
  pr<int, long> p(5, 7L);                                  // the enable_if folds to true
  printf("%d %ld %d %d\n", p.first, p.second, pr<int, long>::width, (int) chk<int, char>::first());
  return chk<int, char>::both<int, long>() ? 1 : 2;       // the same function, called at run time
}
