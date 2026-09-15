#include <cstdio>
#include <map>
int main() {
    std::map<int, int> m;
    auto r = m.emplace(1, 10);
    printf("%d %d %d\n", r.first->first, r.first->second, (int) r.second);
    r = m.emplace(1, 11);
    printf("%d %d\n", r.first->second, (int) r.second);
    auto r2 = m.insert_or_assign(1, 12);
    printf("%d %d\n", r2.first->second, (int) r2.second);
    r2 = m.insert_or_assign(2, 20);
    printf("%d %d %d\n", r2.first->first, r2.first->second, (int) r2.second);
    auto r3 = m.try_emplace(2, 99);
    printf("%d %d\n", r3.first->second, (int) r3.second);
    r3 = m.try_emplace(3, 30);
    printf("%d %d %d\n", r3.first->first, r3.first->second, (int) r3.second);
    std::map<int, int> other = {{3, 33}, {4, 44}, {5, 55}};
    m.merge(other);
    printf("%d %d | %d %d\n", (int) m.size(), m[4], (int) other.size(), other[3]);
    auto nh = m.extract(5);
    std::allocator<int> al = nh.get_allocator();
    std::allocator<int> al2;
    printf("%d %d\n", (int) (al == al2), nh.mapped());
    auto h = m.emplace_hint(m.end(), 9, 90);
    printf("%d %d\n", h->first, (int) m.size());
    return 0;
}
