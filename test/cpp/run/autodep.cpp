// M6's eighteenth step: 'auto' whose deduced type still carries a DEPENDENT name is not deduced at read time --
// the symbol table holds a function template under its raw, unsubstituted signature, so 'auto r = take(a, n)' took
// 'Result<typename T::pointer, ...>' with T unbound and instantiated a class keyed by names that never resolved.
// It stays 'auto' now, and the desugaring deduces it once the call is instantiated.
#include <cstdio>
template <class P, class S = unsigned long> struct Result { P first; S count; };
struct Alloc { using value_type = int; int make(unsigned long n) { return (int) n * 2; } };
template <class A> struct Traits { using elem = typename A::value_type; using size_type = unsigned long; };
template <class A, class T = Traits<A>>
Result<typename T::elem, typename T::size_type> take(A &a, unsigned long n) {
  return Result<typename T::elem, typename T::size_type>{a.make(n), n};
}
template <class E, class A> struct Vec {
  A alloc_;
  int grab(unsigned long n) { auto r = take(alloc_, n); return (int) (r.count + r.first); }
};
int main() { Vec<int, Alloc> v; printf("%d\n", v.grab(5)); return 0; }
