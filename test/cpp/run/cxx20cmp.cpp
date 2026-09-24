#include <cstdio>

// C++20 (-std=c++20): the defaulted comparisons ([class.compare.default]) and the rewritten
// candidates ([over.match.oper]): operator== and operator<=> written `= default' compare the
// members in order (an int here, where C++ has std::strong_ordering), a defaulted <=> brings a
// defaulted == with it, and <, >, <=, >= and != are rewritten through them.
struct P {
    int x;
    int y;
    bool operator==(const P &) const = default;
    auto operator<=>(const P &) const = default;
};
struct V {
    int a;
    double b;
    auto operator<=>(const V &o) const = default;
};
int main() {
    P p{1, 2}, q{1, 3}, r{1, 2};
    printf("%d %d %d %d %d %d %d\n", p == r, p != q, p < q, q > p, p <= r, q >= p, (p <=> q) < 0);
    V v{1, 2.5}, w{1, 2.5}, u{0, 9.0};
    printf("%d %d %d %d %d\n", v == w, v != u, u < v, v >= w, (u <=> v) < 0);
    int c = (3 <=> 5);
    printf("%d %d\n", c < 0, (5 <=> 5) == 0);
    return 0;
}
