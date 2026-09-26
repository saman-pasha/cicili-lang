// <algorithm>, the set operations on sorted ranges
#include <algorithm>
#include <vector>
#include <cstdio>
static void show(const std::vector<int> &v) { for (int x : v) printf("%d ", x); printf("\n"); }
int main() {
    std::vector<int> a = {1, 2, 4, 5, 7};
    std::vector<int> b = {2, 3, 5, 6};
    std::vector<int> r(16, 0);
    printf("%d\n", (int) std::includes(a.begin(), a.end(), std::vector<int>{2, 5}.begin(), std::vector<int>{2, 5}.end()));
    std::vector<int> two = {2, 6};
    printf("%d\n", (int) std::includes(a.begin(), a.end(), two.begin(), two.end()));
    auto e = std::set_union(a.begin(), a.end(), b.begin(), b.end(), r.begin());
    r.resize(e - r.begin()); show(r);
    r.assign(16, 0); e = std::set_intersection(a.begin(), a.end(), b.begin(), b.end(), r.begin());
    r.resize(e - r.begin()); show(r);
    r.assign(16, 0); e = std::set_difference(a.begin(), a.end(), b.begin(), b.end(), r.begin());
    r.resize(e - r.begin()); show(r);
    r.assign(16, 0); e = std::set_symmetric_difference(a.begin(), a.end(), b.begin(), b.end(), r.begin());
    r.resize(e - r.begin()); show(r);
    std::vector<int> m = {1, 4, 7, 2, 5, 6};
    std::inplace_merge(m.begin(), m.begin() + 3, m.end()); show(m);
    return 0;
}
