// `alignas' ON A CLASS, A STRUCT OR A UNION ([dcl.align]): kept by the reader as a layout
// marker beside the members, folded in the class's own words, and read by the layout -- never
// smaller than the natural alignment, with the size rounded up to it. libc++'s aligned_storage
// states std::function's inline buffer this way.
#include <cstdio>
struct alignas(16) V4 { float v[4]; };
struct alignas(32) Over { char c; };
struct Plain { char c; };
struct alignas(double) AsType { char c; };
union alignas(16) Buf { unsigned char b[8]; };
struct Holder { char c; V4 v; };
struct alignas(16) EmptyOver { };            // an empty base takes no bytes but keeps its alignment
struct FromEmpty : EmptyOver { char c; };
int main() {
    printf("%d %d\n", (int) sizeof(V4), (int) alignof(V4));
    printf("%d %d\n", (int) sizeof(Over), (int) alignof(Over));
    printf("%d %d\n", (int) sizeof(Plain), (int) alignof(Plain));
    printf("%d %d\n", (int) sizeof(AsType), (int) alignof(AsType));
    printf("%d %d\n", (int) sizeof(Buf), (int) alignof(Buf));
    printf("%d %d\n", (int) sizeof(Holder), (int) alignof(Holder));
    printf("%d %d\n", (int) sizeof(FromEmpty), (int) alignof(FromEmpty));
    V4 a; 
    printf("%d\n", (int) (((unsigned long) &a) % 16 == 0));
    return 0;
}
