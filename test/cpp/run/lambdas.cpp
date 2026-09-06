/* lambdas (M6, the fifth step): a class of the captures with operator() its
   body; by value, by reference, default captures, a deduced result, a
   lambda handed to a function template and called there */
#include <stdio.h>
template <typename F> int apply(F f, int x) { return f(x); }
int main() {
    int t = 0;
    int k = 10;
    auto add = [](int a, int b) { return a + b; };
    auto addk = [k, &t](int a) mutable -> int { t += a; return a + k; };
    auto all = [=]() { return k * 2; };
    auto refs = [&] { t = t + 100; return t; };
    int r1 = add(3, 4);
    int r2 = addk(5);
    int r3 = all();
    int r4 = refs();
    int r5 = apply([](int v) { return v * v; }, 7);
    int r6 = apply(addk, 1);
    printf("%d %d %d %d %d %d %d\n", r1, r2, r3, r4, r5, r6, t);
    return 0;
}
