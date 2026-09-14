#include <cstdio>
#include <map>
#include <string>
int main() {
    std::map<std::string, int> m = {{"a", 1}, {"b", 2}};
    printf("%d\n", (int) m.size());
    for (const auto &kv : m) printf("[%s]=%d ", kv.first.c_str(), kv.second);
    printf("\n%d %d\n", (int) m.count("a"), (int) m.count("b"));
    printf("%d %d %d\n", m["a"], m["b"], (int) m.size());
    return 0;
}
