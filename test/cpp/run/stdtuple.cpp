// <tuple>, whole: libc++'s tuple is one BASE per element (`__tuple_impl<__index_sequence<_Indx...>, _Tp...>
// : public __tuple_leaf<_Indx, _Tp>...'), so everything here goes through 0.88's multiple inheritance and
// 0.89's empty base; the structured binding is C++'s TUPLE PROTOCOL ([dcl.struct.bind]/4), a tuple having
// no data member of its own to bind by position.
#include <tuple>
#include <string>
#include <utility>
#include <cstdio>

std::tuple<int, int> two(int a, int b) { return std::make_tuple(a, b); }

int main() {
    std::tuple<int, double, char> t(1, 2.5, 'x');
    printf("%d %.1f %c\n", std::get<0>(t), std::get<1>(t), std::get<2>(t));

    std::get<0>(t) = 7;                                    // written through
    printf("%d\n", std::get<0>(t));

    auto m = std::make_tuple(3, 4.5);                      // deduced
    printf("%d %.1f\n", std::get<0>(m), std::get<1>(m));

    printf("%d\n", (int) std::tuple_size<std::tuple<int, double, char> >::value);
    std::tuple_element<1, std::tuple<int, double> >::type d = 4.5;
    printf("%.1f\n", d);

    std::tuple<int, double> u(8, 9.5);                     // BY TYPE (C++14)
    printf("%d %.1f\n", std::get<int>(u), std::get<double>(u));

    int a = 0; double b = 0;                               // tie, and tie with ignore
    std::tie(a, b) = u;
    printf("%d %.1f\n", a, b);
    int c = 0;
    std::tie(c, std::ignore) = two(7, 8);
    printf("%d\n", c);

    int x0 = 9, y0 = 10;                                   // forward_as_tuple
    auto f = std::forward_as_tuple(x0, y0);
    printf("%d %d\n", std::get<0>(f), std::get<1>(f));

    std::pair<int, double> pr(11, 12.5);                   // from a pair
    std::tuple<int, double> fp(pr);
    printf("%d %.1f\n", std::get<0>(fp), std::get<1>(fp));

    std::tuple<int, int> p(1, 2), q(1, 3);                 // the comparisons
    printf("%d %d %d\n", (int)(p == q), (int)(p != q), (int)(p < q));
    printf("%d\n", (int)(two(1, 2) == std::make_tuple(1, 2)));

    auto [bx, by] = std::make_tuple(11, 22);               // the TUPLE PROTOCOL
    printf("%d %d\n", bx, by);
    const auto &[cx, cy] = p;
    printf("%d %d\n", cx, cy);

    std::tuple<std::string, int> s("alpha", 5);            // a class with a destructor held
    printf("%s %d\n", std::get<0>(s).c_str(), std::get<1>(s));
    std::tuple<std::string, std::string> s2("beta", "gamma");
    std::tuple<std::string, std::string> s3 = std::move(s2);
    printf("%s %s\n", std::get<0>(s3).c_str(), std::get<1>(s3).c_str());

    std::tuple<int, int> cp = p;                           // copy, member swap, free swap
    cp.swap(q);
    printf("%d %d  %d %d\n", std::get<0>(cp), std::get<1>(cp), std::get<0>(q), std::get<1>(q));
    std::swap(cp, q);
    printf("%d %d  %d %d\n", std::get<0>(cp), std::get<1>(cp), std::get<0>(q), std::get<1>(q));

    auto sum = [](int i, int j) { return i + j; };         // apply (C++17)
    printf("%d\n", std::apply(sum, std::make_tuple(13, 14)));
    return 0;
}
