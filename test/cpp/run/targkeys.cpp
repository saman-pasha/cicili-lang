#include <cstdio>
template <int N> struct Box { static const int v = N; };
template <char C> struct Ch { static const int v = C; };
template <bool B> struct Flag { static const int v = B ? 1 : 0; };
enum { SEVEN = 7 };
constexpr int twice(int x) { return x * 2; }
int main() {
    printf("%d %d %d %d %d %d\n", Box<-3>::v, Ch<'a'>::v, Flag<true>::v, Box<SEVEN>::v, Box<(int) sizeof(int)>::v, Box<twice(4)>::v);
    return 0;
}
