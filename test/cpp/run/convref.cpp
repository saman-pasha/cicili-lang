// A CONVERSION OPERATOR AT A REFERENCE PARAMETER ([over.ics.user], [dcl.init.ref]/5): a class value where
// `const T &' is wanted converts through its `operator T()' and the reference binds to the PRVALUE the
// operator makes -- so neither the reference nor the `const' on it is the conversion's business. The
// emitter took the type as written, where `ccl_resolve_type' passes a `ref' through unchanged and the
// type-level class test must not unref (0.51's rule), and the value went raw.
#include <cstdio>

struct Yards { int n; };                       // a plain struct: no registered class to compare by

struct Feet {
    int n;
    operator Yards() const { Yards y; y.n = n / 3; return y; }
};

// a class of its own, with a constructor and a destructor: the other branch of cpp_conv_to
struct Metres {
    int n;
    Metres(int m) : n(m) { }
    ~Metres() { }
};

struct Steps {
    int n;
    operator Metres() const { return Metres(n / 2); }
};

int by_val(Yards y) { return y.n; }
int by_ref(const Yards &y) { return y.n; }
int by_rref(Yards &&y) { return y.n; }

struct Sink {
    int take(const Yards &y) const { return y.n * 10; }
};

int metres_by_ref(const Metres &m) { return m.n; }

int main() {
    Feet f; f.n = 9;
    printf("%d %d %d\n", by_val(f), by_ref(f), by_rref(f));
    Yards g = f;                                // copy-initialisation, the same road
    const Yards &r = f;                         // a reference bound to the converted prvalue
    printf("%d %d\n", g.n, r.n);
    Sink s;
    printf("%d\n", s.take(f));                  // a method's reference parameter
    Steps t; t.n = 10;
    printf("%d\n", metres_by_ref(t));           // a REGISTERED class as the target
    return 0;
}
