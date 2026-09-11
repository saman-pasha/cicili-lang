#include <stdio.h>

/* C23 (-std=c23): the level's own forms. bool, true, false and nullptr are
   keywords there; constexpr declares a constant that folds; an enum may name
   its underlying type; [[attributes]] and typeof are the language's own;
   auto deduces; static_assert needs no message; 0b and the digit separator. */

constexpr int K = 7;
static_assert(K == 7, "K is seven");
static_assert(K > 0);
_Static_assert(sizeof(int) == 4, "int is four bytes");

enum Small : unsigned char { A = 1, B };

[[maybe_unused]] static int twice(int n) { return n * 2; }

typedef typeof(K) kint;

int main(void) {
    bool t = true;
    bool f = false;
    int *p = nullptr;
    auto n = K + 1;
    kint k = K;
    int arr[K];
    arr[0] = 0b101010;
    long big = 1'000'000;
    double d = 1'5.2'5;
    static_assert(K < 10, "small");
    printf("%d %d %d %d %d %d %d %ld %.2f %ld\n",
           (int) t, (int) f, p == nullptr, n, (int) B, k, arr[0], big, d, __STDC_VERSION__);
    return 0;
}
