// libc++'s num_get: `class num_get : public locale::facet, private __num_get<_CharT>', the second base a struct of
// STATICS ONLY over a base of statics only -- an empty base, once a `static const char src[33]' (whose `static'
// sits in the array's element type) is split as the static it is; the array defined out of class from a shorter
// literal, zero-filled to its bound.
#include <stdio.h>
struct base_ {
  static const int buf_sz = 40;
  static int get_base(int m) { return m * 2; }
  static const char src[33];
};
const char base_::src[33] = "0123456789abcdefABCDEF+-xX";
template <class C> struct helper : protected base_ {
  static int prep(C c) { return get_base((int) c) + buf_sz; }
};
struct facet { virtual ~facet() {} int refs = 1; };
template <class C> class getter : public facet, private helper<C> {
public:
  int go(C c) const { return helper<C>::prep(c) + refs; }
};
int main() { getter<char> g; printf("%d %c %d\n", g.go('a'), base_::src[10], (int) base_::src[30]); return g.go('b') - 200; }
