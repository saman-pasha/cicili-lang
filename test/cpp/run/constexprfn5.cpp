#include <cstdio>
struct P {
    int x;
    int y;
    constexpr int sum() const { return x + y; }
    constexpr int scaled(int k) const { return (x + y) * k; }
};
constexpr P make(int a) { return {a, a * 2}; }
constexpr P flip(P p) { return P{p.y, p.x}; }
constexpr int area(P p) { return p.x * p.y; }
constexpr int area_ref(const P &p) { return p.x * p.y; }
constexpr P origin = make(7);
constexpr P corner = {3, 4};
constexpr int len(const char *s) {
    int n = 0;
    while (s[n] != 0) n++;
    return n;
}
constexpr int count_a(const char *s) {
    int c = 0;
    while (*s) { if (*s == 'a') c++; s++; }
    return c;
}
constexpr int sum(const int *a, int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s += a[i];
    return s;
}
constexpr int table[4] = {2, 3, 5, 7};
constexpr int sum_table() { return sum(table, 4); }
constexpr int sum_local() {
    int a[3] = {10, 20, 30};
    return sum(a, 3) + sum(a + 1, 2);
}
constexpr int first_word(const char *s) {
    const char *p = s;
    while (*p && *p != ' ') ++p;
    return (int) (p - s);
}
template <int N> struct Box { static const int v = N; };
int main() {
    static_assert(make(3).sum() == 9, "make");
    static_assert(origin.x == 7 && origin.y == 14, "origin");
    static_assert(area(corner) == 12 && area_ref(corner) == 12, "area");
    static_assert(flip(corner).x == 4, "flip");
    static_assert(len("hello") == 5 && count_a("banana") == 3, "strings");
    static_assert(sum_table() == 17 && sum_local() == 110, "arrays");
    static_assert(corner.scaled(3) == 21, "member");
    static_assert(first_word("hello world") == 5, "word");
    printf("%d %d %d %d\n", make(3).sum(), origin.x + origin.y, area(corner), flip(corner).x);
    printf("%d %d %d %d\n", len("hello"), count_a("banana"), sum_table(), sum_local());
    printf("%d %d %d\n", Box<corner.scaled(3)>::v, Box<len("abcdefg")>::v, Box<make(5).y>::v);
    printf("%d %d\n", first_word("hello world"), Box<sum(table, 2)>::v);
    return 0;
}
