// libc++'s unique_ptr: `unique_ptr(pointer __p, const deleter_type & __d)' with
// deleter_type = __destruct_n &, so `const D &' COLLAPSES to `__destruct_n &' ([dcl.ref]/6)
#include <cstdio>
struct N { unsigned long n; };
template <bool B, class T> struct enif { };
template <class T> struct enif<true, T> { typedef T type; };
template <class T> struct is_cc { static const bool value = true; };
// the libc++ shape: a constructor TEMPLATE whose parameter is `const D &' with D a REFERENCE
template <class T, class D> struct UP {
    unsigned long n;
    template <class D2 = D, typename enif<is_cc<D2>::value, int>::type = 0>
    UP(T *q, const D &dd) : n(dd.n + (unsigned long) (q != 0)) { }
};
int main() {
    setvbuf(stdout, 0, _IONBF, 0);
    int v = 7;
    N d; d.n = 5;
    UP<int, N> a(&v, d);
    printf("%lu\n", a.n);
    UP<int, N &> b(&v, d);
    printf("%lu\n", b.n);
    return 0;
}
