// M6's seventeenth step: a NESTED class is a type of the class that holds it ('Plain::Nested' outside, 'Nested'
// within) and a class of its own under the mangled name; the enclosing class's typedefs are in scope inside it, and
// a braced 'Plain::Nested{7}' is the aggregate it is. libc++'s vector destroys itself through a nested class.
#include <cstdio>
struct Plain {
  int n;
  struct Nested { int k; int get() const { return k * 2; } };
  Nested make() const { Nested x; x.k = n; return x; }
};
template <class T> struct Holder {
  T v;
  class Inner {
  public:
    T doubled(T x) const { return x + x; }
  };
  T twice() { Inner i; return i.doubled(v); }
};
int main() {
  Plain p; p.n = 5;
  Plain::Nested q = p.make();
  Holder<int> h; h.v = 21;
  printf("%d %d %d\n", q.get(), h.twice(), Plain::Nested{7}.get());
  return 0;
}
