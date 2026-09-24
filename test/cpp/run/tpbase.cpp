// 0.93: a partial specialization whose base is its own type parameter (libc++ 18's compressed pair and tuple leaf are
// built so), a member reached through that base, a destructor called with its class's template arguments spelled out
#include <cstdio>
template <class T, int I, bool B = true> struct elem { T v; int tag; int k() const { return 100 + tag; } };
template <class T, int I> struct elem<T, I, true> : private T { int tag; int k() const { return T::k() + tag; } };
struct alloc { int k() const { return 7; } };
template <class T> struct box { T v; int gone; int get() const { return v; } };
static int destroyed = 0;
template <class T> struct pair2 { T a, b; int sum() const { return a + b; } ~pair2() { destroyed++; } };
int main() {
  elem<alloc, 1> e; e.tag = 3;
  elem<alloc, 2, false> f; f.tag = 5; f.v = alloc();
  pair2<int> p; p.a = 4; p.b = 6;
  printf("%d %d %d\n", e.k(), f.k(), p.sum());
  p.~pair2<int>();
  printf("%d\n", destroyed);
  destroyed = -1;
  return 0;
}
