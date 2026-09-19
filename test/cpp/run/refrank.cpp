// AN RVALUE PREFERS `T &&' ([over.ics.ref], [over.ics.rank]/3.2.3): an overload set of function
// TEMPLATES differing only in the reference kind of one parameter -- which is how libc++ writes
// std::get for a tuple, four overloads over `tuple &', `const tuple &', `tuple &&' and
// `const tuple &&' -- is chosen by the ARGUMENT'S VALUE CATEGORY. The template road unrefs both
// sides, so the three were one candidate to it and the tie fell to the first declared:
// `std::get<0>(std::forward<_Tuple0>(__t0))' answered `int &' where C++ answers `int &&'.
#include <cstdio>
template <class T> struct box { T v; };
template <class T> T &&fwd(T &x) { return static_cast<T &&>(x); }   // std::forward's shape

template <class T> int pick(box<T> &)       { return 1; }
template <class T> int pick(const box<T> &) { return 2; }
template <class T> int pick(box<T> &&)      { return 3; }

// and the other declaration order, so the answer is the rule and not the order
template <class T> int pick2(const box<T> &) { return 20; }
template <class T> int pick2(box<T> &&)      { return 30; }

int main() {
    box<int> b; b.v = 7;
    printf("%d %d\n", pick(b), pick(fwd(b)));
    printf("%d %d\n", pick2(b), pick2(fwd(b)));
    return 0;
}
