// AN ARRAY BOUND DEDUCES ([temp.deduct.type]/9: `T (&a)[N]' binds N from the argument's own bound), which a
// REFERENCE parameter brings undecayed; a STATIC MEMBER ARRAY with an in-class initializer is its own
// definition (0.45's rule, which only a folding SCALAR had); and a constexpr CALL and an INDEX into such an
// array fold WHEREVER THEY SIT, since the search is written as a conditional whose arms hold the recursive
// call. Together they are how libc++'s `std::get<T>' finds a type's place in a tuple.
#include <cstdio>
typedef unsigned long size_t_;

template <class A, class B> struct same_ { static constexpr bool value = false; };
template <class A> struct same_<A, A> { static constexpr bool value = true; };

template <size_t_ N> size_t_ how_many(const int (&a)[N]) { return N; }
template <size_t_ N> int first_of(const int (&a)[N]) { return a[0]; }

template <size_t_ N>
constexpr size_t_ find_idx(size_t_ i, const bool (&m)[N]) {
    return i == N ? (size_t_) -1 : (m[i] ? i : find_idx(i + 1, m));
}

template <class T, class... Args>
struct find_one {
    static constexpr bool matches[sizeof...(Args)] = { same_<T, Args>::value... };
    static constexpr size_t_ value = find_idx(0, matches);
};

struct Flags { static constexpr bool bits[4] = { false, true, false, true }; };
template <size_t_ N> int count_true(const bool (&a)[N]) { int k = 0; for (size_t_ i = 0; i < N; i++) if (a[i]) k++; return k; }

int main() {
    int v[4] = { 7, 8, 9, 10 };
    printf("%d %d\n", (int) how_many(v), first_of(v));
    printf("%d\n", count_true(Flags::bits));                       // a static member array, at run time
    printf("%d %d %d\n", (int) find_one<int, char, int, double>::value,
                          (int) find_one<double, char, int, double>::value,
                          (int) find_one<char, char, int, double>::value);
    int w[2] = { 1, 2 };
    printf("%d\n", (int) how_many(w));                             // a second bound, its own instance
    return 0;
}
