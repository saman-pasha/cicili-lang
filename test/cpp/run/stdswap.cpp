// M6's fourteenth step: the first of libc++'s functions compiled from its own body -- std::swap, a function template
// of <utility>, instantiated over pointers and over ints: its result type through __enable_if_t, is_move_constructible
// and is_move_assignable (the compiler's __is_constructible and __is_assignable, decided here), its body
// `_Tp __t(std::move(__x)); __x = std::move(__y); __y = std::move(__t);' -- a library's function, C++'s rules, unchecked.
#include <cstdio>
#include <utility>

int main() {
  int a = 1, b = 2;
  int *p = &a, *q = &b;
  std::swap(p, q);
  std::swap(a, b);
  printf("%d %d %d %d\n", *p, *q, a, b);
  return 0;
}
