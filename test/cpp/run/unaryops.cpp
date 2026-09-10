// M6's sixteenth step: a UNARY operator on a class goes to the class's operator, as a binary one already did --
// '*it', '++it', 'it++' (postfix taking the int C++ marks it with), '!x', '-x', '~x'. libc++'s iterators are built
// on them, and 'addressof(*__first)' could not be typed without.
#include <cstdio>
static int a[3] = {4, 5, 6};
struct It {
  int k;
  int &operator*() const { return a[k]; }
  It &operator++() { ++k; return *this; }
  It operator++(int) { It t = *this; ++k; return t; }
  bool operator!() const { return k >= 3; }
  int operator-() const { return -a[k]; }
  int operator~() const { return a[k] + 100; }
};
int main() {
  It i; i.k = 0;
  int first = *i;
  ++i;
  int second = *i;
  It j = i++;
  printf("%d %d %d %d %d %d %d\n", first, second, *j, *i, (int) !i, -i, ~i);
  return 0;
}
