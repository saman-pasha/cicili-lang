// <algorithm> over std::string: the element type that constructs and destroys
#include <algorithm>
#include <vector>
#include <string>
#include <cstdio>
int main() {
    std::vector<std::string> names = {"cid", "amy", "bob", "amy"};
    std::sort(names.begin(), names.end());
    printf("sort %s %s %s %s\n", names[0].c_str(), names[1].c_str(), names[2].c_str(), names[3].c_str());
    printf("count %d\n", (int) std::count(names.begin(), names.end(), std::string("amy")));
    printf("find %d\n", (int) (std::find(names.begin(), names.end(), std::string("bob")) - names.begin()));
    printf("min %s max %s\n", std::min(names[0], names[2]).c_str(),
                              std::max_element(names.begin(), names.end())->c_str());
    printf("lower %d\n", (int) (std::lower_bound(names.begin(), names.end(), std::string("bob")) - names.begin()));
    std::vector<std::string> out(names.size());
    std::copy(names.begin(), names.end(), out.begin());
    printf("copy %s %s\n", out[0].c_str(), out[3].c_str());
    std::reverse(out.begin(), out.end());
    printf("reverse %s %s\n", out[0].c_str(), out[3].c_str());
    return 0;
}
