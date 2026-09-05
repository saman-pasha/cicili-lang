/* C++ statements and expressions: range-for, try/catch/throw, lambdas, enum class, casts, functional casts */
enum class Color : int { Red, Green = 3 };
struct Err { int code; };
int sum(int *xs, int n) {
    int total = 0;
    for (int i = 0; i < n; i++) total += xs[i];
    return total;
}
int main() {
    int xs[3] = { 1, 2, 3 };
    int t = 0;
    for (int x : xs) t += x;
    for (auto &x : xs) x = x * 2;
    auto add = [](int a, int b) { return a + b; };
    int k = 10;
    auto addk = [k, &t](int a) mutable -> int { t += a; return a + k; };
    auto all = [=]() { return k; };
    auto refs = [&] { return t; };
    try {
        if (t > 100) throw Err{t};
        throw 3;
    } catch (Err e) {
        t = e.code;
    } catch (...) {
        t = -1;
    }
    Color c = Color::Green;
    long big = static_cast<long>(t);
    unsigned u = unsigned(k);
    return add(t, k) + addk(1) + all() + refs() + (int) big + (int) u + (c == Color::Red);
}
