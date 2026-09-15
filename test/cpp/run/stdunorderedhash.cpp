#include <cstdio>
#include <unordered_map>
#include <unordered_set>
#include <string>
struct Key { int a; int b; bool operator==(const Key &o) const { return a == o.a && b == o.b; } };
namespace std {
template <> struct hash<Key> {
    size_t operator()(const Key &k) const { return std::hash<int>()(k.a) * 31 + std::hash<int>()(k.b); }
};
}
int main() {
    std::unordered_map<Key, int> um;
    um[Key{1, 2}] = 12;
    um[Key{3, 4}] = 34;
    Key k5{5, 6};
    printf("%d %d %d %d\n", um[Key{1, 2}], (int) um.count(Key{3, 4}), (int) um.count(k5), (int) um.size());
    std::unordered_map<int, int> m;
    for (int i = 0; i < 20; i++) m[i] = i * i;
    printf("%d %d\n", (int) (m.bucket_count() >= 20), (int) (m.load_factor() <= m.max_load_factor()));
    size_t total = 0;
    for (size_t b = 0; b < m.bucket_count(); b++) total += m.bucket_size(b);
    printf("%d %d\n", (int) total, (int) (m.bucket(3) < m.bucket_count()));
    int inb = 0;
    for (auto it = m.begin(m.bucket(3)); it != m.end(m.bucket(3)); ++it) if (it->first == 3) inb = 1;
    printf("%d\n", inb);
    m.max_load_factor(0.5f);
    m.rehash(100);
    printf("%d %d %d\n", (int) (m.bucket_count() >= 100), (int) m.size(), (int) (m.max_load_factor() == 0.5f));
    m.reserve(300);
    printf("%d\n", (int) (m.bucket_count() >= 600));
    auto nh = m.extract(3);
    printf("%d %d %d %d\n", (int) nh.empty(), nh.key(), nh.mapped(), (int) m.count(3));
    nh.key() = 100;
    m.insert(std::move(nh));
    printf("%d %d %d\n", (int) m.count(100), m[100], (int) m.size());
    std::unordered_set<std::string> us = {"a", "bb"};
    auto sh = us.extract("bb");
    printf("%s %d\n", sh.value().c_str(), (int) us.size());
    us.insert(std::move(sh));
    printf("%d\n", (int) us.count("bb"));
    return 0;
}
