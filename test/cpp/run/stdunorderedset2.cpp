#include <cstdio>
#include <string>
#include <unordered_set>
int main() {
    std::unordered_multiset<int> ms = {1, 1, 2};
    ms.insert(1);
    ms.emplace(3);
    printf("%d %d %d\n", (int) ms.size(), (int) ms.count(1), (int) ms.count(9));
    auto r = ms.equal_range(1);
    int n = 0;
    for (auto it = r.first; it != r.second; ++it) n++;
    printf("%d\n", n);
    ms.erase(1);
    printf("%d %d\n", (int) ms.size(), (int) ms.count(1));
    std::unordered_set<std::string> a = {"x", "y"};
    std::unordered_set<std::string> b = a;
    b.insert("z");
    printf("%d %d %d\n", (int) (a == b), (int) b.size(), (int) (a.find("y") != a.end()));
    b.erase(b.find("z"));
    printf("%d\n", (int) (a == b));
    a.reserve(64);
    printf("%d %d\n", (int) (a.bucket_count() >= 64), (int) a.count("x"));
    return 0;
}
