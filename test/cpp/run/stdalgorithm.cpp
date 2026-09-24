// <algorithm>, the predicate family
#include <algorithm>
#include <vector>
#include <cstdio>
static bool even(int x) { return x % 2 == 0; }
int main() {
    std::vector<int> v = {4, 1, 7, 1, 9, 3, 7};
    printf("%d %d %d\n", (int) std::all_of(v.begin(), v.end(), [](int x) { return x > 0; }),
                         (int) std::any_of(v.begin(), v.end(), [](int x) { return x > 8; }),
                         (int) std::none_of(v.begin(), v.end(), [](int x) { return x < 0; }));
    int sum = 0;
    std::for_each(v.begin(), v.end(), [&sum](int x) { sum += x; });
    printf("%d\n", sum);
    printf("%d %d\n", (int) std::count(v.begin(), v.end(), 7), (int) std::count_if(v.begin(), v.end(), even));
    return 0;
}
