#include <cstdio>
#include <set>
#include <string>
#include <vector>
int main() {
    std::vector<int> v = {5, 3, 8, 3};
    std::set<int> s;
    s.insert(v.begin(), v.end());
    s.insert({1, 9});
    printf("%d\n", (int) s.size());
    auto h = s.emplace_hint(s.begin(), 0);
    printf("%d %d\n", *h, *s.cbegin());
    for (auto it = s.crbegin(); it != s.crend(); ++it) printf("%d ", *it);
    printf("\n");
    std::set<int> t = {1, 2};
    printf("%d %d %d\n", (int) (t < s), (int) (s < t), (int) s.value_comp()(1, 2));
    printf("%d\n", (int) (s.max_size() > 1000));
    s.merge(t);
    printf("%d %d\n", (int) s.size(), (int) t.size());
    std::set<std::string, std::less<>> names = {"bob", "amy"};
    printf("%d %d\n", (int) (names.find("amy") != names.end()), (int) names.count("zed"));
    auto r = s.equal_range(3);
    printf("%d %d\n", *r.first, *r.second);
    s.erase(s.begin());
    printf("%d %d\n", *s.begin(), (int) s.size());
    return 0;
}
