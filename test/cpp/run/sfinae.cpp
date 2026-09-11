// M6's nineteenth step: the SFINAE shape libc++'s allocator_traits picks its overloads with -- STATIC MEMBER
// templates whose enable_if default is written over a variable template and its NEGATION, through an alias template
// and over a const argument. A variable template read as a type in an expression must be evaluated, or the negation
// comes out false; and a bool argument keys as its number, so 'true' and '1' name one instance and not two.
#include <cstdio>
template <bool B, class T = void> struct EnIf {};
template <class T> struct EnIf<true, T> { using type = T; };
template <bool B, class T = void> using EnT = typename EnIf<B, T>::type;
template <class A> inline const bool fl = false;
template <> inline const bool fl<const int> = true;
struct Traits {
  template <class Ap = int, EnT<fl<const Ap>, int> = 0> static int m(int x) { return x + 1; }
  template <class Ap = int, EnT<!fl<const Ap>, int> = 0> static int m(int x) { return x + 2; }
};
struct Other {
  template <class Ap = double, EnT<fl<const Ap>, int> = 0> static int m(int x) { return x + 1; }
  template <class Ap = double, EnT<!fl<const Ap>, int> = 0> static int m(int x) { return x + 2; }
};
int main() { printf("%d %d\n", Traits::m(10), Other::m(10)); return 0; }
