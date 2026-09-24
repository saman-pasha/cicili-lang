// A CONDITIONAL OVER TWO LVALUES IS AN LVALUE ([expr.cond]/4) -- std::min's whole body
#include <cstdio>
struct S { int n; const char *tag; };
bool operator<(const S &a, const S &b) { return a.n < b.n; }
template <class T> const T &mymin(const T &a, const T &b) { return b < a ? b : a; }
template <class T> T &pick(bool c, T &a, T &b) { return c ? a : b; }
int main() {
    setvbuf(stdout, 0, _IONBF, 0);
    S x = {2, "two"}, y = {1, "one"};
    printf("%s %s\n", mymin(x, y).tag, mymin(y, x).tag);
    int a = 3, b = 4;
    pick(true, a, b) = 30; pick(false, a, b) = 40;
    printf("%d %d\n", a, b);
    printf("%d\n", pick(a < b, a, b));
    return 0;
}
