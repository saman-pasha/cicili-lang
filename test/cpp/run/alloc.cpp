// M6's fifteenth step: a class whose only written constructors are a defaulted one and a CONVERTING TEMPLATE
// (libc++'s std::allocator), as a member and as a local: default-initialized it needs no call, and from a value of
// its own class it takes the implicit copy, never the template -- and a constructor's parameters are in scope while
// its member initializers are built, or 'a_(a)' cannot type 'a' to choose.
#include <cstdio>
template <class T> struct Alloc {
  Alloc() noexcept = default;
  template <class U> Alloc(const Alloc<U> &) noexcept {}
  int tag() const { return 7; }
};
template <class T> struct Layout {
  Alloc<T> a_;
  int n_;
  explicit Layout(const Alloc<T> &a) : n_(0), a_(a) {}
  int size() const { return a_.tag() + n_; }
};
int main() { Alloc<int> a; Layout<int> l(a); Alloc<long> b(a); printf("%d %d\n", l.size(), b.tag()); return 0; }
