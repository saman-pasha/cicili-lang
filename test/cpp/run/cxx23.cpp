/* C++23 (M6, the twelfth step), built with -std=c++23: if consteval (the run-time
   branch), an explicit object parameter on a method and on a recursive lambda, a
   multidimensional subscript, a static operator(), auto(x), [[assume]], a label at
   the end of a block, the size_t suffix, delimited escapes, a lambda without
   parentheses, an alias in an init-statement, #elifdef, and __cplusplus at the level
   asked */
#include <stdio.h>
#define HAVE_GRID
struct Grid {
    int cells[9];
    int &operator[](int r, int c) { return cells[r * 3 + c]; }
    int sum(this const Grid &self) { int t = 0; for (int i = 0; i < 9; i++) t += self.cells[i]; return t; }
};
struct Twice { static int operator()(int x) { return 2 * x; } };
constexpr int pick(int x) { if consteval { return x; } else { return x + 1; } }
int main() {
    Grid g;
    for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) g[r, c] = r * 3 + c;
    int base = 1;
    auto fact = [base](this auto self, int n) -> int { return n < 2 ? base : n * self(n - 1); };
    auto sq = [] -> int { return 7 * 7; };
    Twice tw;
    const int k = 5;
    auto copy = auto(k);
    copy += 1;
    [[assume(copy > 0)]];
    size_t n = 4uz;
    const char *s = "\x{41}\o{102}\u{43}\104";
    int level = 0;
#ifdef NOTHING
    level = 1;
#elifdef HAVE_GRID
    level = 2;
#elifndef HAVE_GRID
    level = 3;
#endif
    if (using T = long; true) { T x = 40; level += (int) x; }
    int labelled = 0;
    { labelled = 1; done: }
    printf("%d %d %d %d %d %d %d %s %d %d %d %ld\n", g[1, 2], g.sum(), fact(5), sq(), tw(21), pick(1), copy, s, (int) n, level, labelled, __cplusplus);
    return 0;
}
