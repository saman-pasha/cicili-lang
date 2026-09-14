#include <cstdio>
#include <optional>
std::optional<int> half(int n) {
    if (n % 2 == 0) return n / 2;
    return std::nullopt;
}
int main() {
    std::optional<int> a;
    std::optional<int> b = 21;
    printf("%d %d\n", (int) a.has_value(), (int) b.has_value());
    printf("%d %d\n", *b, b.value());
    printf("%d %d\n", a.value_or(-1), b.value_or(-1));
    a = 5;
    printf("%d %d\n", (int) (bool) a, *a);
    a.reset();
    printf("%d\n", (int) a.has_value());
    auto h = half(8);
    auto g = half(7);
    printf("%d %d %d\n", (int) h.has_value(), *h, (int) g.has_value());
    b.emplace(9);
    printf("%d %d\n", *b, (int) (b == 9));
    std::optional<int> c = b;
    printf("%d %d %d\n", (int) (c == b), (int) (a == b), (int) (a < b));
    if (h) printf("h %d\n", *h);
    if (!g) printf("no g\n");
    return 0;
}
