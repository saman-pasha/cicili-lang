// A CAST TO A REFERENCE IS A CONVERSION OF ITS OWN ([expr.static.cast], [class.derived]): the offset is from
// the OPERAND's class to the CAST's target, and `ccl_type_of' of a cast answers that target -- so taken whole
// the two classes were equal, no base hops were walked, and the object's own address went out. It is the shape
// libc++'s tuple swaps its leaves by, one base per element: `L1::sw(static_cast<L1 &>(o))'.
#include <cstdio>

struct L0 { int a; void sw(L0 &o) { int t = a; a = o.a; o.a = t; } };
struct L1 { int b; void sw(L1 &o) { int t = b; b = o.b; o.b = t; } };
struct L2 { int c; };

struct Both : L0, L1, L2 {
    Both(int x, int y, int z) { a = x; b = y; c = z; }
    void swap(Both &o) {
        L0::sw(static_cast<L0 &>(o));
        L1::sw(static_cast<L1 &>(o));
    }
};

int second(const L1 &x) { return x.b; }
int third(L2 *p) { return p->c; }

int main() {
    Both p(1, 2, 3), q(5, 6, 7);
    printf("%d %d %d  %d %d %d\n", p.a, p.b, p.c, q.a, q.b, q.c);
    p.swap(q);
    printf("%d %d %d  %d %d %d\n", p.a, p.b, p.c, q.a, q.b, q.c);
    L1 &r = q;                                   // a reference bound to the second base
    L1 *w = &q;                                  // a pointer converted to it
    printf("%d %d\n", r.b, w->b);
    printf("%d %d\n", second(p), third(&p));     // through a parameter, and to the third base
    L2 &s = static_cast<L2 &>(p);                // the cast written out, to a reference
    printf("%d\n", s.c);
    return 0;
}
