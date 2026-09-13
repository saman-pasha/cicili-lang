// the shape libc++ builds its locale on: `class locale::facet : public __shared_count'
// -- a nested class DECLARED in its holder and DEFINED out of it, deriving from an
// abstract class (a pure virtual slot the table holds a null for) and from an EMPTY
// second base, which is a scope and no sub-object, with a base constructor that has a
// default argument.
#include <stdio.h>

class Shared {                                    // the abstract base: a slot nothing here overrides
public:
  explicit Shared(long refs = 0) : owners_(refs) {}
  virtual ~Shared() {}
  virtual void on_zero() = 0;                     // pure: the table takes a null
  long use_count() const { return owners_ + 1; }
protected:
  long owners_;
};

class Tag {                                       // an EMPTY base: types, constants, nothing to store
public:
  typedef unsigned long mask;
  static const mask space = 1;
  static const mask digit = 4;
  enum kind { one, two };
};

class Locale {
public:
  class Facet;                                    // declared here, defined below
  typedef int id;
};

class Locale::Facet : public Shared, public Tag {
public:
  explicit Facet(unsigned long refs = 0) : Shared(static_cast<long>(refs) - 1) {}
  void on_zero() { owners_ = 0; }
  Locale::id twice() const { return (id) (use_count() * 2); }
  mask both() const { return space | digit; }     // the empty base's constants, named bare
};

int main() {
  Locale::Facet f(7);
  Shared *s = &f;
  printf("%ld %d %lu %d\n", f.use_count(), f.twice(), f.both(), (int) Tag::two);
  s->on_zero();                                   // through the slot the derived class fills
  printf("%ld\n", f.use_count());
  return (int) f.both();
}
