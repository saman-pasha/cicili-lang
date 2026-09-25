// AN EMPTY CLASS VALUE MOVES NO BYTES (0.94): its one byte is padding as a complete object and, as an empty base reached
// through a reference, somebody else's -- libc++ 18's compressed pair swaps its deleter through `static_cast<_Base2 &>(*this)',
// and the byte stored at the pair's address was the pointer's low byte.
#include <cstdio>
struct D {};
struct E : private D { int v; D &d() { return static_cast<D &>(*this); } };
struct F { D del; int w; D &d() { return del; } };
int main() {
  E a, b; a.v = 1; b.v = 2;
  D t = a.d(); a.d() = b.d(); b.d() = t;
  F f, g; f.w = 3; g.w = 4;
  D u = f.d(); f.d() = g.d(); g.d() = u;
  printf("%d %d %d %d\n", a.v, b.v, f.w, g.w);
  return 0;
}
