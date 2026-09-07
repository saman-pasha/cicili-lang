// M6's fourteenth step: __builtin_offsetof decided from the layout the compiler already computes -- plain, nested,
// and through a template's instance (libc++ finds a type's data size this way, the offset of a char placed after it).
#include <cstdio>
struct Inner { int a; double b; };
struct Outer { char c; Inner in; int tail; };
template <class T> struct Pad { T v; char first_pad; };
int main() {
  printf("%d %d %d %d %d\n", (int) __builtin_offsetof(Outer, c), (int) __builtin_offsetof(Outer, in),
         (int) __builtin_offsetof(Outer, in.b), (int) __builtin_offsetof(Outer, tail),
         (int) __builtin_offsetof(Pad<int *>, first_pad));
  return 0;
}
