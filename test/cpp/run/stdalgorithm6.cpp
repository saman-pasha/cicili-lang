// <algorithm>, the partitions and the sorts
#include <algorithm>
#include <vector>
#include <functional>
#include <cstdio>
static void show(const char *tag, const std::vector<int> &v) {
    printf("%s", tag);
    for (int i = 0; i < (int) v.size(); i++) printf(" %d", v[i]);
    printf("\n");
}
int main() {
    std::vector<int> v = {5, 2, 8, 2, 9, 1};
    std::vector<int> pv = v;
    std::vector<int>::iterator pp = std::partition(pv.begin(), pv.end(), [](int x) { return x % 2 == 0; });
    printf("partition %d %d\n", (int) (pp - pv.begin()),
           (int) std::is_partitioned(pv.begin(), pv.end(), [](int x) { return x % 2 == 0; }));
    std::vector<int> sp = {1, 2, 3, 4, 5, 6};
    std::stable_partition(sp.begin(), sp.end(), [](int x) { return x % 2 == 0; });
    show("stable_partition", sp);
    std::vector<int> ps = {2, 4, 6, 1, 3};
    printf("partition_point %d\n",
           (int) (std::partition_point(ps.begin(), ps.end(), [](int x) { return x % 2 == 0; }) - ps.begin()));
    std::vector<int> s = v;
    std::sort(s.begin(), s.end());
    show("sort", s);
    std::vector<int> g = v;
    std::sort(g.begin(), g.end(), std::greater<int>());
    show("sort_greater", g);
    std::vector<int> st = v;
    std::stable_sort(st.begin(), st.end());
    show("stable_sort", st);
    std::vector<int> pq = v;
    std::partial_sort(pq.begin(), pq.begin() + 3, pq.end());
    printf("partial_sort %d %d %d\n", pq[0], pq[1], pq[2]);
    std::vector<int> ne = v;
    std::nth_element(ne.begin(), ne.begin() + 2, ne.end());
    printf("nth_element %d\n", ne[2]);
    printf("is_sorted %d %d\n", (int) std::is_sorted(s.begin(), s.end()), (int) std::is_sorted(v.begin(), v.end()));
    printf("is_sorted_until %d\n", (int) (std::is_sorted_until(v.begin(), v.end()) - v.begin()));
    return 0;
}
