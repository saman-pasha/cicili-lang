// std::bind and the callable adaptors from libc++, compiled from their own
// bodies: the placeholders, a reordering bind, a partial one, a member function
// bound, std::ref into a bind, mem_fn, invoke, and a pointer to member.
#include <cstdio>
#include <functional>

struct Point {
    int x; int y;
    int sum() const { return x + y; }
    int scale(int k) const { return (x + y) * k; }
};
int add3(int a, int b, int c) { return a + b + c; }

int main() {
    using namespace std::placeholders;
    auto b1 = std::bind(add3, 1, 2, _1);
    printf("%d\n", b1(10));
    auto b2 = std::bind(add3, _2, _1, 100);
    printf("%d\n", b2(3, 4));
    auto b3 = std::bind(add3, _1, _1, _1);
    printf("%d\n", b3(5));

    Point p{5, 6};
    auto m = std::mem_fn(&Point::sum);
    printf("%d\n", m(p));
    auto ms = std::mem_fn(&Point::scale);
    printf("%d\n", ms(p, 3));

    printf("%d\n", std::invoke(add3, 1, 2, 3));
    printf("%d\n", std::invoke(&Point::sum, p));
    printf("%d\n", std::invoke(&Point::scale, p, 4));

    int (Point::*pm)(int) const = &Point::scale;          // a pointer to member, written out
    Point *pp = &p;
    printf("%d %d\n", (p.*pm)(2), (pp->*pm)(3));

    int base = 100;
    auto grow = [&base](int d) { base += d; return base; };
    std::function<int(int)> fr = std::ref(grow);
    printf("%d %d\n", fr(5), base);

    auto bm = std::bind(&Point::scale, p, _1);            // a member function bound to an object
    printf("%d\n", bm(10));
    return 0;
}
