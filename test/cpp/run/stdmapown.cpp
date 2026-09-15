#include <cstdio>
#include <map>
#include <string>
struct Pt { int x, y; bool operator<(const Pt &o) const { return x < o.x || (x == o.x && y < o.y); } };
struct Val { std::string name; int n; };
int main() {
    std::map<std::string, int> w;
    w.emplace("one", 1);
    w.emplace(std::string("two"), 2);
    w.try_emplace("three", 3);
    w.insert_or_assign("one", 100);
    for (auto &[k, v] : w) printf("%s=%d ", k.c_str(), v);
    printf("\n");
    std::map<Pt, int> pm;
    pm[{1, 2}] = 5;
    pm[Pt{0, 9}] = 7;
    pm.emplace(Pt{3, 3}, 9);
    for (auto &[p, v] : pm) printf("(%d,%d)=%d ", p.x, p.y, v);
    printf("\n");
    std::map<int, Val> vm;
    vm[1] = Val{"alpha", 1};
    vm.emplace(2, Val{"beta", 2});
    vm.try_emplace(3, Val{"gamma", 3});
    vm.insert({4, {"delta", 4}});
    for (auto &[k, v] : vm) printf("%d:%s/%d ", k, v.name.c_str(), v.n);
    printf("\n");
    Val c = vm[2];
    c.n = 22;
    printf("%s %d %d\n", c.name.c_str(), c.n, vm[2].n);
    return 0;
}
