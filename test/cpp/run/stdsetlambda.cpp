#include <cstdio>
#include <set>
int main() {
    auto cmp = [](int a, int b) { return a > b; };
    std::set<int, decltype(cmp)> s(cmp);
    s.insert(3);
    s.insert(9);
    s.insert(1);
    for (int x : s) printf("%d ", x);
    printf("\n");
    std::set<int> a = {1, 2, 3};
    std::multiset<int> ms = {2, 3, 3, 4};
    a.merge(ms);
    printf("%d %d\n", (int) a.size(), (int) ms.size());
    for (int x : a) printf("%d ", x);
    printf("\n");
    for (int x : ms) printf("%d ", x);
    printf("\n");
    std::multiset<int> ms2 = {7};
    ms2.merge(a);
    printf("%d %d\n", (int) ms2.size(), (int) a.size());
    for (int x : ms2) printf("%d ", x);
    printf("\n");
    return 0;
}
