#include <cstdio>
#include <string>
#include <unordered_map>
int main() {
    std::unordered_map<std::string, int> w;
    w["apple"] = 1;
    w["pear"] = 4;
    w["apple"] += 2;
    w["fig"]++;
    printf("%d %d %d\n", (int) w.size(), w["apple"], w["fig"]);
    auto it = w.find("pear");
    printf("%d %s %d\n", (int) (it != w.end()), it->first.c_str(), it->second);
    printf("%d %d\n", (int) w.count("apple"), (int) w.count("plum"));
    w.erase("pear");
    int sum = 0;
    for (const auto &kv : w) sum += kv.second;
    printf("%d %d\n", (int) w.size(), sum);
    std::string k = "fig";
    printf("%d %d\n", w.at(k), (int) (w.find("zzz") == w.end()));
    return 0;
}
