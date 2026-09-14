#include <cstdio>
#include <string>
#include <unordered_set>
int main() {
    std::unordered_set<int> s = {5, 3, 8, 3};
    s.insert(1);
    s.insert(5);
    printf("%d %d %d\n", (int) s.size(), (int) s.count(3), (int) s.count(4));
    s.erase(3);
    int sum = 0;
    for (int x : s) sum += x;
    printf("%d %d %d\n", (int) s.size(), sum, (int) (s.find(8) != s.end()));
    std::unordered_set<std::string> names;
    names.insert("bob");
    names.insert("amy");
    names.insert("bob");
    printf("%d %d %d\n", (int) names.size(), (int) names.count("amy"), (int) names.count("zed"));
    names.erase("amy");
    printf("%d %d\n", (int) names.size(), (int) names.empty());
    names.clear();
    printf("%d\n", (int) names.empty());
    return 0;
}
