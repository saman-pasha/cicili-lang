#include <cstdio>
#include <optional>
int main() {
    int x = 5;
    std::optional<int &> r = x;
    *r = 7;
    printf("%d %d %d\n", x, *r, (int) r.has_value());
    std::optional<int &> none;
    printf("%d %d\n", (int) none.has_value(), none.value_or(9));
    int y = 1;
    r = y;
    *r = 2;
    printf("%d %d\n", x, y);
    return 0;
}
