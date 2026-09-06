/* C++23: if consteval, an explicit object parameter (deducing this), a multidimensional
   subscript, auto(x), a label at the end of a block, the size_t suffix, delimited escapes,
   a lambda without parentheses, an alias in an init-statement, a static operator() */
struct Grid { int cells[9]; int &operator[](int r, int c) { return cells[r * 3 + c]; } int sum(this const Grid &self) { return self.cells[0]; } };
struct Twice { static int operator()(int x) { return 2 * x; } };
constexpr int pick(int x) { if consteval { return x; } else { return x + 1; } }
int main() {
    Grid g;
    g[1, 2] = 5;
    auto fact = [](this auto self, int n) -> int { return n < 2 ? 1 : n * self(n - 1); };
    auto sq = [] mutable -> int { return 49; };
    const int k = 5;
    int copy = auto(k);
    size_t n = 4uz;
    const char *s = "\x{41}\u{43}";
    if (using T = long; true) { T x = 40; copy += (int) x; }
    { copy = 1; done: }
    return copy;
}
