/* C++17 structured bindings: a struct's members by position, an array's elements, by value and by reference */
#include <stdio.h>
struct P { int x; int y; };
P twice(P p) { return P{ p.x * 2, p.y * 2 }; }
int main() {
    P p = { 3, 4 };
    auto [a, b] = p;
    auto &[c, d] = p;
    c = 10;
    int arr[2] = { 5, 6 };
    auto [e, f] = arr;
    auto [g, h] = twice(p);
    printf("%d %d %d %d %d %d %d %d\n", a, b, p.x, d, e, f, g, h);
    return 0;
}
