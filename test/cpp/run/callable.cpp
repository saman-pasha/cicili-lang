// M6's thirty-fourth step: A DATA MEMBER THAT IS CALLABLE, named bare inside its class. A local of a class with
// operator() has been callable since lambdas were added; a MEMBER was not, and libc++'s `__scope_guard' holds the
// closure it was made with and writes `__func_()' in its destructor -- which is the whole of how `basic_string'
// unwinds an append. Beside it, three more the growing string asked for: a PRVALUE of the class IS the object
// (C++17's elision, where the only constructor took something else entirely), a CONVERTING CONSTRUCTOR at a call
// (`__rep(__long)'), and a DEFAULT ARGUMENT kept from the declaration where the out-of-class definition may not
// repeat it.
#include <cstdio>

int total = 0;

struct Adder {
    int k;
    void operator()() const { total += k; }                      // called bare in a destructor
    int operator()(int n) const { return n + k; }                // ... and with an argument, in a method
};

struct Wide { int a; int b; };
struct Narrow {
    int v;
    Narrow(Wide w) : v(w.a + w.b) { }                            // a converting constructor, used at a call
};
int sum(Narrow n) { return n.v; }

struct Guard {
    Adder f_;
    ~Guard() { f_(); }
    int bump(int n) const { return f_(n); }
    int step(int n, int by = 10) const { return n + by; }        // the default lives on THIS declaration
};

int main() {
    int r, st;
    {
        Guard g;
        g.f_.k = 5;
        r  = g.bump(37);
        st = g.step(7);
    }
    Wide w;
    w.a = 20;
    w.b = 22;
    printf("%d %d %d %d\n", total, r, st, sum(w));
    return 0;
}
