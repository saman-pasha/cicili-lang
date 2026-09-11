// M6's twenty-second step: an anonymous struct whose members carry DEFAULT INITIALIZERS comes to the desugaring in
// C++'s own class shape, not the plain one anon.cpp covers, and its members are the holder's just the same. libc++'s
// vector layout keeps its capacity and its allocator in one.
#include <cstdio>
template <class T, class A> class Layout {
public:
  A &alloc() { return alloc_; }
  T cap() { return cap_; }
  void set(T v) { cap_ = v; }
private:
  struct { [[__no_unique_address__]] T cap_ = 0; [[__no_unique_address__]] A alloc_ = 9; };
};
int main() { Layout<int, int> l; l.set(7); printf("%d %d\n", l.cap(), l.alloc()); return 0; }
