// `[[no_unique_address]]' ([dcl.attr.nouniqueaddr]) is C++20's empty base optimization for a
// MEMBER: an empty member marked with it takes NO BYTES and keeps its alignment, while a member
// with bytes of its own lies where it always did. libc++ marks every container's allocator and
// comparator with it, and basic_string's short form is a marked padding beside its data.
#include <cstdio>
struct E { };
struct alignas(16) EA { };
struct P { int v; };
struct One   { [[no_unique_address]] E e; int x; };                        // the empty member costs nothing
struct Plain { E e; int x; };                                              // ... where unmarked it takes its byte
struct Two   { [[no_unique_address]] E a; [[no_unique_address]] E b; int x; };
struct Align { [[no_unique_address]] EA e; char c; };                      // ... and keeps its alignment
struct Has   { [[no_unique_address]] P p; char c; };                       // a member with bytes is untouched
struct Last  { int x; [[no_unique_address]] E e; };
struct Pair  { [[no_unique_address]] E cmp; char *p; unsigned long n; };   // libc++'s compressed pair
int main() {
    printf("%d %d %d\n", (int) sizeof(One), (int) alignof(One), (int) __builtin_offsetof(One, x));
    printf("%d %d\n", (int) sizeof(Plain), (int) __builtin_offsetof(Plain, x));
    printf("%d %d\n", (int) sizeof(Two), (int) alignof(Two));
    printf("%d %d\n", (int) sizeof(Align), (int) alignof(Align));
    printf("%d %d %d\n", (int) sizeof(Has), (int) alignof(Has), (int) __builtin_offsetof(Has, c));
    printf("%d %d\n", (int) sizeof(Last), (int) alignof(Last));
    printf("%d %d %d\n", (int) sizeof(Pair), (int) __builtin_offsetof(Pair, p), (int) __builtin_offsetof(Pair, n));
    One o; o.x = 41; printf("%d\n", o.x + 1);
    Pair q; q.p = (char *) "abc"; q.n = 3;
    printf("%s %d\n", q.p, (int) q.n);
    return 0;
}
