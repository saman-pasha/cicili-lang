// <algorithm>, the comparisons and the min/max surface
#include <algorithm>
#include <vector>
#include <cstdio>
int main() {
    std::vector<int> v = {4, 1, 7, 1, 9, 3, 7};
    std::vector<int> w = v;
    printf("%d %d\n", (int) std::equal(v.begin(), v.end(), w.begin()),
                      (int) std::lexicographical_compare(v.begin(), v.end(), w.begin(), w.end()));
    w[2] = 100;
    printf("%d\n", (int) (std::mismatch(v.begin(), v.end(), w.begin()).first - v.begin()));
    printf("%d %d\n", *std::min_element(v.begin(), v.end()), *std::max_element(v.begin(), v.end()));
    printf("%d %d\n", *std::minmax_element(v.begin(), v.end()).first, *std::minmax_element(v.begin(), v.end()).second);
    printf("%d %d %d %d\n", std::min(3, 8), std::max(3, 8), std::minmax(3, 8).first, std::minmax(3, 8).second);
    printf("%d %d %d\n", std::clamp(5, 1, 4), std::clamp(0, 1, 4), std::clamp(2, 1, 4));
    return 0;
}
