// <functional>'s function objects, reference wrappers and hashes, from libc++.
#include <cstdio>
#include <functional>
#include <string>
#include <set>

int twice(int x) { return x * 2; }

int main() {
    printf("%d %d %d %d\n", std::plus<int>()(3, 4), std::minus<int>()(3, 4),
           std::multiplies<int>()(3, 4), std::divides<int>()(12, 4));
    printf("%d %d\n", std::modulus<int>()(13, 5), std::negate<int>()(7));
    printf("%d %d %d %d\n", (int) std::equal_to<int>()(2, 2), (int) std::not_equal_to<int>()(2, 2),
           (int) std::less<int>()(1, 2), (int) std::greater<int>()(1, 2));
    printf("%d %d\n", (int) std::less_equal<int>()(2, 2), (int) std::greater_equal<int>()(1, 2));
    printf("%d %d %d\n", (int) std::logical_and<bool>()(true, false),
           (int) std::logical_or<bool>()(true, false), (int) std::logical_not<bool>()(false));
    printf("%d %d %d %d\n", std::bit_and<int>()(12, 10), std::bit_or<int>()(12, 10),
           std::bit_xor<int>()(12, 10), std::bit_not<int>()(0));

    std::less<> lt;                                        // the transparent comparators
    printf("%d %d\n", (int) lt(1, 2), (int) lt(std::string("a"), std::string("b")));
    std::plus<> pl;
    printf("%d\n", pl(20, 22));

    int n = 41;                                            // reference_wrapper
    std::reference_wrapper<int> r = std::ref(n);
    r.get()++;
    printf("%d %d\n", n, r.get());
    std::reference_wrapper<const int> cr = std::cref(n);
    printf("%d\n", cr.get());
    int m = 3;
    std::reference_wrapper<int> r2 = std::ref(m);
    r2 = r;                                                // rebound
    printf("%d %d\n", r2.get(), m);

    std::hash<int> hi;                                     // the hashes
    printf("%d\n", (int) (hi(7) == hi(7)));
    std::hash<std::string> hs;
    printf("%d %d\n", (int) (hs(std::string("cicili")) == hs(std::string("cicili"))),
           (int) (hs(std::string("a")) == hs(std::string("b"))));

    std::set<int, std::greater<int>> g{1, 5, 3};           // a function object as a comparator
    int first = *g.begin();
    printf("%d %d\n", first, (int) g.size());

    std::function<int(int)> f = twice;                     // a function object held
    printf("%d\n", f(21));
    return 0;
}
