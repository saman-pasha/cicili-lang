// M6's twenty-fourth step: a qualified call written as a STATEMENT, 'traits::take(x);', where a declaration is also
// possible -- the vexing parse one scope deeper. It had read as a declaration of a globally qualified name, since a
// declarator may be qualified at file scope. Inside a function body it may not, and libc++'s vector destroys itself
// through exactly this shape.
#include <cstdio>
static int total = 0;
template <class A> struct Traits { static void take(A x) { total += x; } };
template <class T> struct Holder {
  using traits = Traits<T>;
  T v;
  struct Inner { void use(T x) { traits::take(x); } };
  int go() { Inner i; i.use(v); return total; }
};
int main() { Holder<int> h; h.v = 21; printf("%d\n", h.go()); return 0; }
