#include <cstdio>
#include <optional>
#include <string>
std::optional<std::string> pick(int n) {
    if (n > 0) return std::string("chosen");
    return std::nullopt;
}
int main() {
    std::optional<std::string> a;
    std::optional<std::string> b = std::string("hello world, a long string");
    printf("%d %d %s\n", (int) a.has_value(), (int) b.has_value(), b->c_str());
    printf("%d %s\n", (int) b->size(), b.value().c_str());
    printf("%s %s\n", a.value_or("none").c_str(), b.value_or("none").c_str());
    a = "short";
    printf("%d %s\n", (int) a.has_value(), a->c_str());
    a.reset();
    printf("%d\n", (int) a.has_value());
    auto p = pick(1);
    auto q = pick(0);
    printf("%d %s %d\n", (int) p.has_value(), p->c_str(), (int) q.has_value());
    b.emplace("emplaced");
    printf("%s %d\n", b->c_str(), (int) (b == std::string("emplaced")));
    std::optional<std::string> c = b;
    printf("%d %d %s\n", (int) (c == b), (int) (a == b), c->c_str());
    auto m = std::make_optional<std::string>("made");
    printf("%s %d\n", m->c_str(), (int) (*m == "made"));
    a.swap(m);
    printf("%d %d %s\n", (int) a.has_value(), (int) m.has_value(), a->c_str());
    return 0;
}
