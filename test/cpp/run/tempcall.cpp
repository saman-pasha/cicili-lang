#include <stdio.h>

/* A temporary's operator(), the shape libc++'s vector destructor is written in:
   __destroy_vector(*this)() -- the object is built and called in one expression,
   so the call must go inside the block that builds it, where it has an address. */

int seen = 0;

struct Adder {
    int base;
    Adder(int b) : base(b) { }
    int operator()(int x) const { return base + x; }
};

struct Setter {
    int mark;
    Setter(int m) : mark(m) { }
    void operator()() const { seen = mark; }      /* void, as a destroyer is */
};

int main() {
    int r = Adder(10)(5);
    Setter(7)();
    Adder a(100);
    Adder *p = &a;
    Adder fs[2] = { Adder(1), Adder(2) };
    (*p)(2);                                      /* a parenthesized callee at a statement's start */
    printf("%d %d %d %d\n", r, seen, (*p)(1), fs[1](40));
    return 0;
}
