// M6's fourteenth step: function templates as candidate sets, chosen as C++ chooses -- every definition of the name
// whose signature holds is a candidate, an exact match beats a conversion, the most specialized wins among those.
#include <cstdio>

template <class T> struct Box { T v; };
struct Sub : Box<int> { int extra; };

template <class T> int pick(T &) { return 1; }                  // the generic
template <class T> int pick(Box<T> &) { return 2; }             // more specialized: a Box goes here
template <class T, class U> int pick(Box<T> &, U) { return 3; }  // another arity
template <class T> int pick(T *) { return 4; }                  // a pointer: more specialized than T & for one

template <class T> int kind(const Box<T> &) { return 5; }
template <class T> int kind(const T &) { return 6; }
template <class T> int kind(const T *) { return 7; }

template <class T> int count(T) { return 1; }
template <class T, class... Rest> int count(T, Rest... rest) { return 1 + count(rest...); }

int main() {
  int i = 0;
  Box<int> b{7};
  int *p = &i;
  const int *cp = &i;
  Sub s{};
  printf("%d %d %d %d\n", pick(i), pick(b), pick(b, 1), pick(p));
  printf("%d %d %d %d\n", kind(b), kind(i), kind(cp), pick(s));
  printf("%d %d\n", count(1), count(1, 2, 3));
  return 0;
}
