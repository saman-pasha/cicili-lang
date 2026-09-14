#include <cstdio>
#include <optional>
#include <utility>
struct P { int x; int y; };
std::optional<P> mk(int n) {
    if (n < 0) return std::nullopt;
    return P{n, n * 2};
}
int main() {
    auto p = mk(3);
    auto q = mk(-1);
    printf("%d %d %d %d\n", (int) p.has_value(), p->x, p->y, (int) q.has_value());
    std::optional<double> d = 2.5;
    printf("%d %.1f %.1f\n", (int) d.has_value(), *d, d.value_or(0.0) * 2);
    std::optional<std::pair<int, int>> pr = std::make_pair(4, 5);
    printf("%d %d\n", pr->first, pr->second);
    std::optional<int> e;
    e = std::nullopt;
    printf("%d %d\n", (int) e.has_value(), (int) (e == std::nullopt));
    e = 7;
    e = std::optional<int>(8);
    printf("%d %d\n", *e, (int) (e != std::nullopt));
    std::optional<int> f = std::move(e);
    printf("%d %d\n", *f, (int) (f > 3));
    return 0;
}
