#include <cstdio>
#include <unordered_map>
#include <vector>
int main() {
    std::unordered_map<int, int> m = {{1, 10}, {2, 20}, {3, 30}};
    std::unordered_map<int, int> c = m;
    c.emplace(4, 40);
    printf("%d %d %d\n", (int) m.size(), (int) c.size(), (int) (m == c));
    c.erase(4);
    printf("%d\n", (int) (m == c));
    auto r = c.insert({2, 99});
    printf("%d %d\n", (int) r.second, r.first->second);
    auto it = c.find(1);
    it = c.erase(it);
    printf("%d %d\n", (int) c.size(), (int) c.count(1));
    std::vector<std::pair<int, int>> v = {{7, 70}, {8, 80}};
    c.insert(v.begin(), v.end());
    printf("%d %d\n", (int) c.size(), c[8]);
    c.reserve(100);
    printf("%d %d\n", (int) (c.bucket_count() >= 100), (int) (c.load_factor() < 1.0f));
    c.rehash(8);
    printf("%d\n", (int) c.count(7));
    std::unordered_multimap<int, int> mm;
    mm.insert({1, 1});
    mm.insert({1, 2});
    mm.insert({2, 3});
    printf("%d %d\n", (int) mm.size(), (int) mm.count(1));
    auto er = mm.equal_range(1);
    int n = 0;
    for (auto q = er.first; q != er.second; ++q) n += q->second;
    printf("%d\n", n);
    c.clear();
    printf("%d %d\n", (int) c.empty(), (int) mm.empty());
    return 0;
}
