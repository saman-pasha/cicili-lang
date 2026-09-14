#include <cstdio>
#include <unordered_map>
int main() {
    std::unordered_map<int, int> m;
    m[3] = 30;
    m[1] = 10;
    m[2] = 20;
    m.insert({4, 40});
    printf("%d %d\n", (int) m.size(), m[3]);
    auto it = m.find(2);
    printf("%d %d\n", (int) (it != m.end()), it->second);
    printf("%d %d\n", (int) m.count(1), (int) m.count(9));
    m.erase(1);
    printf("%d %d\n", (int) m.size(), (int) m.count(1));
    int sum = 0;
    for (auto &kv : m) sum += kv.second;
    printf("%d\n", sum);
    printf("%d %d\n", m.at(4), (int) m.empty());
    m[2] += 5;
    printf("%d %d\n", m[2], (int) (m.bucket_count() > 0));
    m.clear();
    printf("%d\n", (int) m.size());
    return 0;
}
