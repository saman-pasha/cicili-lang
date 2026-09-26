#include <cstdio>
struct P { int x; int y; };
constexpr int table[5] = {3, 1, 4, 1, 5};
constexpr P origin = {7, 9};
constexpr int sum_table(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s += table[i];
    return s;
}
constexpr int sum_local(int n) {
    int a[4] = {10, 20, 30, 40};
    a[1] = a[1] + n;
    int s = 0;
    for (int i = 0; i < 4; ++i) s += a[i];
    return s;
}
constexpr int grid(int k) {
    int g[2][3] = {{1, 2, 3}, {4, 5, 6}};
    g[1][2] += k;
    return g[0][1] * 10 + g[1][2];
}
constexpr int point(int d) {
    P p = {1, 2};
    p.x += d;
    p.y = p.y * 3;
    return p.x * 100 + p.y + origin.x;
}
constexpr int digits(int n) {
    int c = 0;
    while (n > 0) { c++; n /= 10; }
    return c;
}
constexpr int twice_digits(int n) {
    return digits(n) * 2 + digits(sum_table(5));
}
constexpr int kind(int c) {
    switch (c) {
        case 1: return 10;
        case 2:
        case 3: return 20;
        case 4: { int t = c * 2; return t + 1; }
        default: return -1;
    }
}
constexpr int fall(int c) {
    int r = 0;
    switch (c) {
        case 1: r += 1;
        case 2: r += 10; break;
        case 3: r += 100;
    }
    return r;
}
constexpr int pts(int n) {
    P ps[3] = {{1, 2}, {3, 4}, {5, 6}};
    ps[1].y = n;
    int s = 0;
    for (int i = 0; i < 3; i++) s += ps[i].x * ps[i].y;
    return s;
}
template <int N> struct Box { static const int v = N; };
int main() {
    static_assert(sum_table(5) == 14, "sum");
    static_assert(sum_local(5) == 105, "local");
    static_assert(grid(4) == 30, "grid");
    static_assert(point(2) == 313, "point");
    static_assert(twice_digits(12345) == 12, "nested");
    static_assert(kind(3) == 20 && kind(4) == 9 && kind(9) == -1, "switch");
    static_assert(fall(1) == 11 && fall(2) == 10 && fall(3) == 100 && fall(7) == 0, "fall");
    static_assert(pts(10) == 62, "pts");
    int arr[sum_table(3)];
    printf("%d %d %d %d\n", sum_table(5), sum_local(5), grid(4), point(2));
    printf("%d %d %d %d %d\n", twice_digits(12345), kind(3), kind(4), fall(1), pts(10));
    printf("%d %d %d\n", Box<sum_local(1)>::v, (int) (sizeof(arr) / sizeof(int)), Box<fall(3)>::v);
    printf("%d %d %d\n", sum_table(2), digits(999), kind(2));
    return 0;
}
