// M6's fourteenth step: an anonymous struct member's members are the class's own (libc++'s compressed pair is one), an
// anonymous union's are reached through the one member it becomes; in a template and in a plain struct.
#include <cstdio>
template <class T> struct P { T b; struct { [[no_unique_address]] T cap; [[no_unique_address]] int pad; }; union { int u; float v; }; void f() { cap = b + 1; u = 7; } };
struct Q { int x; struct { int y; int z; }; };
int main() { P<int> p; p.b = 4; p.f(); Q q; q.y = 2; q.z = 3; printf("%d %d %d %d\n", p.cap, p.u, q.y, q.z); return 0; }
