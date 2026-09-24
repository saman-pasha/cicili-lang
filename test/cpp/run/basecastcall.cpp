// A CALL THROUGH A CAST TO A BASE'S REFERENCE calls the base's operator() over the base sub-object (0.94): libc++ 18's
// __map_value_compare writes `static_cast<const _Compare &>(*this)(x.first, y.first)' over its empty base, and taken as
// the operand's own road the comparator called itself until the stack was gone -- every map of strings segfaulted.
#include <cstdio>
struct Cmp { bool operator()(int a, int b) const { return a < b; } };
struct Wrap : private Cmp {
  bool operator()(int x, int y) const { return static_cast<const Cmp&>(*this)(x, y); }
  bool go(int a, int b) const { return (*this)(a, b); }
  const Cmp &comp() const { return *this; }
  bool go2(int a, int b) const { return comp()(a, b); }
};
int main() { Wrap w; printf("%d %d %d\n", (int) w.go(1, 2), (int) w.go(3, 2), (int) w.go2(1, 2)); return 0; }
