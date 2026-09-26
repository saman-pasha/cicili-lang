// a constexpr function with STATEMENTS ([dcl.constexpr], C++14): locals, assignments, if, loops, several returns,
// folded where a constant is wanted -- a template argument, an array's bound, a static const, a global constexpr
#include <cstdio>
constexpr int fact(int n) { int r = 1; for (int i = 2; i <= n; ++i) r *= i; return r; }
constexpr int fib(int n) {
    if (n < 2) return n;
    int a = 0, b = 1;
    while (n-- > 1) { int t = a + b; a = b; b = t; }
    return b;
}
constexpr int bits(unsigned v) { int c = 0; while (v) { c += v & 1; v >>= 1; } return c; }
constexpr int collatz(int n) { int steps = 0; do { if (n % 2 == 0) n /= 2; else n = 3 * n + 1; steps++; } while (n != 1); return steps; }
constexpr int first_square_over(int limit) { for (int i = 1;; i++) { if (i * i > limit) return i; } }
constexpr int sum_odd(int n) { int s = 0; for (int i = 0; i < n; i++) { if (i % 2 == 0) continue; if (i > 7) break; s += i; } return s; }
template <int N> struct Arr { int v[N]; };
struct Q { static constexpr int k = fib(7); };
constexpr int F5 = fact(5);
constexpr int C27 = collatz(27);
int main() {
    Arr<fib(10)> a;
    int buf[bits(255u)];
    static_assert(fact(3) == 6, "fact");
    static_assert(first_square_over(50) == 8, "square");
    printf("%d %d %d %d\n", F5, (int) (sizeof a.v / sizeof(int)), (int) (sizeof buf / sizeof buf[0]), Q::k);
    printf("%d %d %d\n", C27, first_square_over(99), sum_odd(20));
    int n = 6;
    printf("%d %d\n", fact(n), fib(n));
    return 0;
}
