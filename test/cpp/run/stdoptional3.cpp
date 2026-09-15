#include <cstdio>
#include <optional>
#include <string>
std::optional<int> half(int x) { if (x % 2) return std::nullopt; return x / 2; }
int main() {
    std::optional<int> a = 8;
    auto b = a.and_then(half);
    printf("%d %d\n", (int) b.has_value(), *b);
    auto c = b.and_then(half).and_then(half);
    printf("%d %d\n", (int) c.has_value(), *c);
    auto d = c.and_then(half);
    printf("%d\n", (int) d.has_value());
    auto e = a.transform([](int x) { return x * 10; });
    printf("%d\n", *e);
    auto f = d.or_else([] { return std::optional<int>(-1); });
    printf("%d\n", *f);
    auto g = a.transform([](int x) { return x + 1; }).and_then(half);
    printf("%d %d\n", (int) g.has_value(), (int) d.value_or(7));
    return 0;
}
