/* templates (M6, the fourth step): a class template instantiated at every
   template-id met, a function template at a call, its arguments explicit or
   deduced; an alias of an instance; methods over the instance's members */
#include <stdio.h>
template <typename T> T max2(T a, T b) { return a > b ? a : b; }
template <typename T, int N> struct Buf {
    T d[N];
    int count;
    Buf() : count(0) { }
    void push(T x) { if (count < N) d[count++] = x; }
    T sum() const { T s = 0; for (int i = 0; i < count; i++) s = s + d[i]; return s; }
    int size() const { return N; }
};
template <typename T> struct Box { T v; T get() const { return v; } };
using Ints = Buf<int, 8>;
int main() {
    Ints b;
    b.push(3); b.push(4); b.push(5);
    Buf<double, 2> f;
    f.push(1.5); f.push(2.25); f.push(9.0);
    Box<char> c;
    c.v = 'x';
    printf("%d %d %d %.2f %d %c %d %.1f\n", b.sum(), b.size(), b.count, f.sum(), f.count, c.get(), max2(3, 4), max2<double>(1.5, 2));
    return 0;
}
