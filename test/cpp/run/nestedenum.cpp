// a NESTED ENUM is a type of the class that holds it, as a nested class is: libc++'s
// `ios_base::seekdir', which basic_streambuf writes in three of its methods. Plain and
// scoped, named from outside, from a template's body, and as a member's type.
#include <stdio.h>

class Base {
public:
  enum seekdir { beg, cur, end };
  enum class strong : long { one = 7, two };
  typedef int off_t;
  Base(seekdir w) : w_(w) {}
  seekdir where() const { return w_; }
  off_t twice() const { return (off_t) w_ * 2; }
private:
  seekdir w_;                                     // the class's own type, named bare inside it
};

template <class T> class Holder {
public:
  Holder(Base::seekdir w) : w_(w) {}
  T sum(Base::seekdir w) { return (T) ((int) w + (int) w_); }
  Base::seekdir keep() { return Base::cur; }
private:
  Base::seekdir w_;                               // a nested enum as a member's type, in a template
};

int main() {
  Base b(Base::end);
  Holder<int> h(Base::beg);
  printf("%d %d %d %d %d\n", (int) b.where(), (int) b.twice(), h.sum(Base::cur),
         (int) h.keep(), (int) (long) Base::strong::two);
  return (int) b.where();
}
