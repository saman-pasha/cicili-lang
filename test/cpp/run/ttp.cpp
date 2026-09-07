// M6's fourteenth step: a template template parameter -- bound to a template's name, defaulted, passed on,
// used as a base (the CRTP libc++'s __split_buffer makes of its layout) and deduced from an argument's type.
#include <cstdio>

template <class T> struct Box { T v; Box(T x) : v(x) {} T get() const { return v; } };
template <class T> struct Twice { T v; Twice(T x) : v(x + x) {} T get() const { return v; } };

template <class T, template <class> class Holder = Box>
struct Cell {
  Holder<T> h;
  Cell(T x) : h(x) {}
  T value() const { return h.get(); }
};

template <class Derived, class T> struct Layout {
  T items[4];
  int n;
  Layout() : n(0) {}
  int count() const { return n; }
  void put(T x) { items[n++] = x; }
  T last() const { return items[n - 1]; }
};

template <class T, template <class, class> class L = Layout>
struct Buffer : L<Buffer<T, L>, T> {
  using base = L<Buffer<T, L>, T>;
  void push(T x) { this->put(x); }
  int size() const { return this->count(); }
};

template <template <class> class H, class T> T unwrap(const H<T> &h) { return h.get(); }

int main() {
  Cell<int> a(5);
  Cell<int, Twice> b(5);
  Buffer<int> buf;
  buf.push(3);
  buf.push(4);
  Box<int> d(7);
  Twice<int> e(8);
  printf("%d %d %d %d %d %d\n", a.value(), b.value(), buf.size(), buf.last(), unwrap(d), unwrap(e));
  return 0;
}
