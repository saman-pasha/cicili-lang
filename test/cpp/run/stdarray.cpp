// <array>, whole: libc++ writes it as the aggregate `struct { _Tp __elems_[_Size]; }', so every
// `std::array<T, N> a = {...}' is BRACE ELISION ([dcl.init.aggr]/15) -- one member, N items -- and its
// iterators are RAW POINTERS where a vector's are a `__wrap_iter' class, so the range-for's own
// `auto __e = a.end()' is a plain pointer the safe part must read as a borrow of the object.
#include <array>
#include <string>
#include <tuple>
#include <cstdio>

int main() {
    std::array<int, 4> a = {1, 2, 3, 4};
    printf("%d %d %d %d %d\n", (int) a.size(), a[0], a.at(1), a.front(), a.back());
    printf("%d %d\n", (int) a.empty(), (int) (a.max_size() == 4));

    a[1] = 20; a.at(2) = 30;
    int s = 0; for (int x : a) s += x;                       // the range-for over raw-pointer iterators
    printf("%d\n", s);

    int t = 0; for (std::array<int, 4>::iterator it = a.begin(); it != a.end(); ++it) t += *it;
    printf("%d\n", t);

    std::array<int, 4> b = a;                                // copied
    printf("%d %d %d\n", (int)(a == b), (int)(a != b), (int)(a < b));
    b.fill(7);
    printf("%d %d %d\n", b[0], b[3], (int)(a < b));
    a.swap(b);
    printf("%d %d\n", a[0], b[0]);
    printf("%d %d\n", a.data()[0], *(b.begin() + 1));

    std::array<int, 3> g = {5, 6, 7};                        // the tuple protocol over an array
    printf("%d %d\n", std::get<0>(g), std::get<2>(g));
    printf("%d\n", (int) std::tuple_size<std::array<int, 3> >::value);
    auto [p, q, r] = g;
    printf("%d %d %d\n", p, q, r);

    std::array<std::string, 2> n = {"alpha", "beta"};        // elements that construct and destroy
    printf("%s %s\n", n[0].c_str(), n[1].c_str());
    n[0] = "gamma";
    printf("%s %d\n", n[0].c_str(), (int) n[0].size());

    std::array<int, 3> z = {};                               // value-initialised
    printf("%d %d %d\n", z[0], z[1], z[2]);
    return 0;
}
