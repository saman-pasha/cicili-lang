// VIRTUAL INHERITANCE laid out as the Itanium ABI lays a complete object: the class's own table pointer first, its
// own members, the shared base LAST -- `basic_ostream : virtual public basic_ios', std::cout's shape. The base's
// members, methods, constructor and destructor are reached as through any base, and a pointer or a reference to
// the derived object converts to the base by the base's OFFSET, which is zero for every other base.
#include <stdio.h>
struct A { virtual ~A() {} int a; A() : a(7) {} int twice() const { return a * 2; } };
struct B : virtual public A { virtual ~B() {} long b; B() : b(3) {} long sum() const { return a + b; } };
static int viaptr(const A *p) { return p->a + 1; }
static int viaref(const A &r) { return r.twice(); }
int main() {
  B x;
  x.a = 5;
  A *base = &x;
  const A &ref = x;
  printf("%d %ld %d %ld %d %d %d\n", base->twice(), x.sum(), (int) ((char *) base - (char *) &x), (long) sizeof(B),
         viaptr(&x), viaref(x), ref.twice());
  return (int) x.sum();
}
