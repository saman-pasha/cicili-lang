// <algorithm>, the binary searches and the merges
#include <algorithm>
#include <vector>
#include <cstdio>
static void show(const char *tag, const std::vector<int> &v) {
    printf("%s", tag);
    for (int i = 0; i < (int) v.size(); i++) printf(" %d", v[i]);
    printf("\n");
}
int main() {
    std::vector<int> s = {1, 2, 2, 5, 8, 9};
    printf("lower %d upper %d\n", (int) (std::lower_bound(s.begin(), s.end(), 2) - s.begin()),
                                  (int) (std::upper_bound(s.begin(), s.end(), 2) - s.begin()));
    printf("equal_range %d %d\n", (int) (std::equal_range(s.begin(), s.end(), 2).first - s.begin()),
                                  (int) (std::equal_range(s.begin(), s.end(), 2).second - s.begin()));
    printf("binary_search %d %d\n", (int) std::binary_search(s.begin(), s.end(), 8),
                                    (int) std::binary_search(s.begin(), s.end(), 7));
    std::vector<int> a = {1, 3, 5}, b = {2, 3, 6};
    std::vector<int> m(6);
    std::merge(a.begin(), a.end(), b.begin(), b.end(), m.begin());
    show("merge", m);
    std::vector<int> im = {1, 4, 7, 2, 3, 9};
    std::inplace_merge(im.begin(), im.begin() + 3, im.end());
    show("inplace_merge", im);
    printf("includes %d\n", (int) std::includes(s.begin(), s.end(), a.begin(), a.end()));
    return 0;
}
