// an empty [[no_unique_address]] member's ADDRESS, as the Itanium ABI places it: at offset 0 whatever lies there,
// unless an empty subobject of its own type is there already -- then at the data size, stepping by its alignment;
// its byte still counts toward the class's size (measured against clang++ 18)
#include <cstdio>
struct E {}; struct F {};
struct A { [[no_unique_address]] E a, b; };
struct B { int x; [[no_unique_address]] E a, b; };
struct C { [[no_unique_address]] E a; char c; };
struct D { char c; [[no_unique_address]] E a; };
struct G { char c; [[no_unique_address]] E a, b, c2; };
struct H { [[no_unique_address]] E a; int x; [[no_unique_address]] E b; [[no_unique_address]] F f; };
struct I { char c[3]; [[no_unique_address]] E a; int x; };
struct J { [[no_unique_address]] E a; [[no_unique_address]] F f; char c; };
struct K { int x; [[no_unique_address]] E a; char c; [[no_unique_address]] E b; };
struct M { E plain; [[no_unique_address]] E a; };
#define AT(o, m) (int) ((char *) &(o).m - (char *) &(o))
int main() {
    A oa; B ob; C oc; D od; G og; H oh; I oi; J oj; K ok; M om;
    printf("A %d %d %d\n", (int) sizeof(A), AT(oa, a), AT(oa, b));
    printf("B %d %d %d\n", (int) sizeof(B), AT(ob, a), AT(ob, b));
    printf("C %d %d %d\n", (int) sizeof(C), AT(oc, a), AT(oc, c));
    printf("D %d %d %d\n", (int) sizeof(D), AT(od, c), AT(od, a));
    printf("G %d %d %d %d\n", (int) sizeof(G), AT(og, a), AT(og, b), AT(og, c2));
    printf("H %d %d %d %d %d\n", (int) sizeof(H), AT(oh, a), AT(oh, x), AT(oh, b), AT(oh, f));
    printf("I %d %d %d\n", (int) sizeof(I), AT(oi, a), AT(oi, x));
    printf("J %d %d %d %d\n", (int) sizeof(J), AT(oj, a), AT(oj, f), AT(oj, c));
    printf("K %d %d %d %d\n", (int) sizeof(K), AT(ok, a), AT(ok, c), AT(ok, b));
    printf("M %d %d %d\n", (int) sizeof(M), AT(om, plain), AT(om, a));
    ob.x = 7; ok.x = 9; ok.c = 'k';
    printf("%d %d %c\n", ob.x, ok.x, ok.c);
    return 0;
}
