// a function's constexpr is no const on its result ([dcl.constexpr]): the reference it returns is writable,
// a template deduces the plain type from it, and a constexpr OBJECT stays a constant that folds
#include <cstdio>
struct Box { int v[2]; };
static constexpr int &at(Box &b, int i) { return b.v[i]; }
static constexpr const int &cat(const Box &b, int i) { return b.v[i]; }
template <class T> struct Kind { static const int k = 0; };
template <> struct Kind<int &> { static const int k = 1; };
template <> struct Kind<const int &> { static const int k = 2; };
template <class T> constexpr int kind_of(T &&) { return Kind<T>::k; }
constexpr int twice(int n) { return n * 2; }
constexpr int N = twice(21);
int main() {
    Box b = {{1, 2}};
    at(b, 0) = 10;
    int &r = at(b, 1);
    r += 5;
    printf("%d %d\n", b.v[0], b.v[1]);
    printf("%d %d %d\n", kind_of(at(b, 0)), kind_of(cat(b, 0)), kind_of(twice(3)));
    int arr[N];
    printf("%d %d\n", (int) (sizeof arr / sizeof arr[0]), N);
    return 0;
}
