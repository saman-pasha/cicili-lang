// std::function from libc++, compiled from its own body: a function pointer, a
// lambda, a functor, the empty one, copied and assigned, swapped, compared with
// nullptr, a void result and two arguments.
#include <cstdio>
#include <functional>
#include <vector>

int twice(int x) { return x * 2; }
struct Adder { int n; int operator()(int x) const { return x + n; } };
static int side = 0;
void bump(int d) { side += d; }

int main() {
    std::function<int(int)> f = twice;
    printf("%d\n", f(5));
    std::function<int(int)> g = [](int x) { return x * x; };
    printf("%d\n", g(6));
    Adder a{10};
    std::function<int(int)> h = a;
    printf("%d\n", h(7));
    printf("%d %d\n", (int) (bool) f, (int) (bool) g);

    std::function<int(int)> e;
    printf("%d %d %d\n", (int) (bool) e, (int) (e == nullptr), (int) (f != nullptr));

    std::function<int(int)> c = g;                 // copied
    printf("%d %d\n", c(4), g(4));
    c = twice;                                     // assigned
    printf("%d\n", c(4));
    c.swap(f);
    printf("%d %d\n", c(3), f(3));
    e = nullptr;
    printf("%d\n", (int) (bool) e);

    std::function<void(int)> v = bump;             // a void result
    v(3); v(4);
    printf("%d\n", side);

    std::function<int(int, int)> two = [](int x, int y) { return x * 100 + y; };
    printf("%d\n", two(7, 8));

    int base = 1000;                                // a lambda that captures
    std::function<int(int)> cap = [base](int x) { return base + x; };
    printf("%d\n", cap(11));

    std::vector<std::function<int(int)>> fs;        // held in a container
    fs.push_back(twice);
    fs.push_back([](int x) { return x + 1; });
    int sum = 0;
    for (const std::function<int(int)> &fn : fs) sum += fn(10);
    printf("%d\n", sum);
    return 0;
}
