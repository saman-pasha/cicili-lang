// <algorithm>, the search family
#include <algorithm>
#include <vector>
#include <cstdio>
static bool even(int x) { return x % 2 == 0; }
int main() {
    std::vector<int> v = {4, 1, 7, 1, 9, 3, 7};
    printf("%d %d %d\n", (int) (std::find(v.begin(), v.end(), 9) - v.begin()),
                         (int) (std::find_if(v.begin(), v.end(), even) - v.begin()),
                         (int) (std::find_if_not(v.begin(), v.end(), even) - v.begin()));
    std::vector<int> pat = {1, 9};
    printf("%d\n", (int) (std::search(v.begin(), v.end(), pat.begin(), pat.end()) - v.begin()));
    std::vector<int> dup = {3, 3};
    printf("%d\n", (int) (std::adjacent_find(v.begin(), v.end()) - v.begin()));
    printf("%d\n", (int) (std::find_end(v.begin(), v.end(), pat.begin(), pat.end()) - v.begin()));
    printf("%d\n", (int) (std::find_first_of(v.begin(), v.end(), dup.begin(), dup.end()) - v.begin()));
    return 0;
}
