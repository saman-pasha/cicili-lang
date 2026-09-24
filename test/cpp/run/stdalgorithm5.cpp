// <algorithm>, the mutating operations
#include <algorithm>
#include <vector>
#include <cstdio>
static void show(const char *tag, const std::vector<int> &v) {
    printf("%s", tag);
    for (int i = 0; i < (int) v.size(); i++) printf(" %d", v[i]);
    printf("\n");
}
int main() {
    std::vector<int> v = {5, 2, 8, 2, 9, 1};
    std::vector<int> r = v;
    r.erase(std::remove(r.begin(), r.end(), 2), r.end());
    show("remove", r);
    std::vector<int> r2 = v;
    r2.erase(std::remove_if(r2.begin(), r2.end(), [](int x) { return x > 4; }), r2.end());
    show("remove_if", r2);
    std::vector<int> p = v;
    std::replace(p.begin(), p.end(), 2, 0);
    show("replace", p);
    std::replace_if(p.begin(), p.end(), [](int x) { return x > 7; }, -1);
    show("replace_if", p);
    std::vector<int> a = {1, 2, 3}, b = {9, 8, 7};
    std::swap_ranges(a.begin(), a.end(), b.begin());
    show("swap_a", a); show("swap_b", b);
    std::vector<int> rv = v;
    std::reverse(rv.begin(), rv.end());
    show("reverse", rv);
    std::vector<int> rc(v.size());
    std::reverse_copy(v.begin(), v.end(), rc.begin());
    show("reverse_copy", rc);
    std::vector<int> ro = {1, 2, 3, 4, 5};
    std::rotate(ro.begin(), ro.begin() + 2, ro.end());
    show("rotate", ro);
    std::vector<int> u = {1, 1, 2, 2, 2, 3, 1};
    u.erase(std::unique(u.begin(), u.end()), u.end());
    show("unique", u);
    return 0;
}
