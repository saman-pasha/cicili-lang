// <algorithm>, the heap and the permutations
#include <algorithm>
#include <vector>
#include <cstdio>
static void show(const char *tag, const std::vector<int> &v) {
    printf("%s", tag);
    for (int i = 0; i < (int) v.size(); i++) printf(" %d", v[i]);
    printf("\n");
}
int main() {
    std::vector<int> h = {5, 2, 8, 2, 9, 1};
    std::make_heap(h.begin(), h.end());
    printf("make_heap %d %d\n", h[0], (int) std::is_heap(h.begin(), h.end()));
    h.push_back(10); std::push_heap(h.begin(), h.end());
    printf("push_heap %d\n", h[0]);
    std::pop_heap(h.begin(), h.end()); int top = h.back(); h.pop_back();
    printf("pop_heap %d %d\n", top, h[0]);
    std::sort_heap(h.begin(), h.end());
    show("sort_heap", h);
    std::vector<int> pm = {1, 2, 3};
    std::next_permutation(pm.begin(), pm.end());
    show("next_permutation", pm);
    std::prev_permutation(pm.begin(), pm.end());
    show("prev_permutation", pm);
    std::vector<int> q = {3, 1, 2};
    printf("is_permutation %d\n", (int) std::is_permutation(pm.begin(), pm.end(), q.begin()));
    return 0;
}
