#include <cstdio>
#include <set>
#include <map>
#include <unordered_map>
#include <unordered_set>
int main() {
    std::set<int> s = {1, 2, 3, 4, 5, 6};
    printf("%d %d\n", (int) s.contains(3), (int) s.contains(9));
    auto n = std::erase_if(s, [](int x) { return x % 2 == 0; });
    printf("%d %d\n", (int) n, (int) s.size());
    for (int x : s) printf("%d ", x);
    printf("\n");
    std::map<int, int> m = {{1, 10}, {2, 20}, {3, 30}};
    printf("%d %d\n", (int) m.contains(2), (int) m.contains(7));
    auto k = std::erase_if(m, [](const std::pair<const int, int> &kv) { return kv.second > 15; });
    printf("%d %d\n", (int) k, (int) m.size());
    std::unordered_map<int, int> um = {{1, 10}, {2, 20}};
    std::unordered_set<int> us = {5, 6};
    printf("%d %d %d %d\n", (int) um.contains(1), (int) um.contains(3), (int) us.contains(6), (int) us.contains(7));
    return 0;
}
