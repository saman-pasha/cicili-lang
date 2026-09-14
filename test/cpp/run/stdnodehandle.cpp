#include <cstdio>
#include <set>
#include <map>
#include <string>
int main() {
    std::set<int> s = {1, 5, 9};
    std::set<int> t = {2};
    auto nh = s.extract(9);
    printf("%d %d %d\n", (int) nh.empty(), nh.value(), (int) s.count(9));
    t.insert(std::move(nh));
    printf("%d %d %d\n", (int) t.size(), (int) t.count(9), (int) nh.empty());
    auto none = s.extract(42);
    printf("%d %d\n", (int) none.empty(), (int) (bool) none);
    std::map<std::string, int> m = {{"a", 1}, {"b", 2}};
    auto mh = m.extract("a");
    printf("%s %d %d\n", mh.key().c_str(), mh.mapped(), (int) m.size());
    mh.key() = "z";
    m.insert(std::move(mh));
    printf("%d %d\n", (int) m.count("z"), m["z"]);
    return 0;
}
