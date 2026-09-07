// M6's fourteenth step: an array's BOUND is an expression the desugaring must rewrite too -- a variable template
// instantiated and folded in it (libc++ pads a compressed pair with 'char p[sizeof(T) - datasize<T>]'), and a class's
// own typedef winning over a namespace's of the same name, as C++ looks names up.
#include <cstdio>
template <class T> struct Pad { T v; char first_pad; };
template <class T> inline const unsigned long dsz = __builtin_offsetof(Pad<T>, first_pad);
template <class A> struct Traits { using pointer = A *; };
template <class A> struct Alloc { };
template <class A> struct ATraits { using pointer = typename Traits<A>::pointer; };
template <class T, class A> struct Layout {
  using alloc_traits = ATraits<T>;
  using pointer = typename alloc_traits::pointer;
  pointer p;
  char pad[sizeof(pointer) - dsz<pointer> + 1];
  int size() { return (int) sizeof(pad); }
};
int main() { Layout<int, Alloc<int>> l; printf("%d\n", l.size()); return 0; }
