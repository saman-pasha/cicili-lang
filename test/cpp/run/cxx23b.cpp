#include <cstdio>

// C++23 (-std=c++23): a static operator() and operator[], [[assume(e)]] told to LLVM, a
// constrained auto checked where it is deduced (a declaration and an abbreviated template's
// parameter), and the extended floating-point suffixes (f16, f32, f64, f128, bf16), doubles here.
template <class T> concept Small = sizeof(T) <= 4;
struct Twice {
    static int operator()(int x) { return x * 2; }
    static int operator[](int i) { return i + 10; }
};
int half(Small auto x) { return x / 2; }
int main() {
    Twice t;
    int n = t(21) + t[5];
    [[assume(n > 0)]];
    Small auto s = 7;
    const Small auto &sr = s;
    double d = 1.5f16 + 2.5f32 + 3.0f64 + 4.0f128 + 0.5bf16;
    printf("%d %d %d %.1f %d\n", n, s, sr, d, half(9));
    return 0;
}
