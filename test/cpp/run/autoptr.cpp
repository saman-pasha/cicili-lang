// M6's fifteenth step: 'auto' deduces ANY type, not only a plain one -- a pointer from arithmetic, an array's
// element's address, a string literal, a pointer to a class -- which libc++'s __relocate needs ('auto __new_begin =
// __begin_ - __size').
#include <cstdio>
struct P { int v; int get() const { return v; } };
int main() {
  int a[4] = {1, 2, 3, 4};
  auto p = a + 1;
  auto n = p - a;
  auto q = &a[3];
  auto s = "abc";
  P objs[2] = {{7}, {9}};
  auto r = &objs[1];
  printf("%d %d %d %s %d\n", *p, (int) n, *q, s, r->get());
  return 0;
}
