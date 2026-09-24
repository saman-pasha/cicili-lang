// <algorithm>, copy, fill, transform and generate
#include <algorithm>
#include <vector>
#include <cstdio>
static void show(const char *tag, const std::vector<int> &v) {
    printf("%s", tag);
    for (int i = 0; i < (int) v.size(); i++) printf(" %d", v[i]);
    printf("\n");
}
int main() {
    std::vector<int> v = {5, 2, 8, 2, 9, 1};
    std::vector<int> w(v.size());
    std::copy(v.begin(), v.end(), w.begin());
    show("copy", w);
    std::vector<int> c2(3);
    std::copy_n(v.begin(), 3, c2.begin());
    show("copy_n", c2);
    std::vector<int> odd(6, 0);
    int n = (int) (std::copy_if(v.begin(), v.end(), odd.begin(), [](int x) { return x % 2 == 1; }) - odd.begin());
    printf("copy_if %d %d %d\n", n, odd[0], odd[1]);
    std::vector<int> back(v.size());
    std::copy_backward(v.begin(), v.end(), back.end());
    show("copy_backward", back);
    std::vector<int> f(4);
    std::fill(f.begin(), f.end(), 7);
    show("fill", f);
    std::fill_n(f.begin(), 2, 3);
    show("fill_n", f);
    std::vector<int> t(v.size());
    std::transform(v.begin(), v.end(), t.begin(), [](int x) { return x * 10; });
    show("transform", t);
    std::transform(v.begin(), v.end(), w.begin(), t.begin(), [](int a, int b) { return a + b; });
    show("transform2", t);
    int k = 0;
    std::generate(f.begin(), f.end(), [&k]() { return ++k; });
    show("generate", f);
    return 0;
}
