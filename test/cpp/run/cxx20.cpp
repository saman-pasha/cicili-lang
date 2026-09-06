/* C++20 (M6, the eleventh step), built with -std=c++20: a concept checked
   where a template is instantiated, an abbreviated function template with
   its result deduced, if constexpr decided at compile time (in a template
   too), the three-way comparison, constinit, using enum, a range-for with
   an initializer, designated initializers, [[likely]], and __cplusplus at
   the level asked (an integer literal's suffix is not read yet: hence the casts) */
#include <stdio.h>
template <typename T> concept Number = requires (T a, T b) { a + b; a * b; };
template <typename T> requires Number<T> T twice(T x) { return x + x; }
template <typename T> T sum3(T a, T b, T c) { if constexpr (sizeof(T) == 8) return a + b + c; else return a + b + c + 1; }
auto add(auto a, auto b) { return a + b; }
constexpr int square(int x) { return x * x; }
constinit int limit = 100;
enum class Mode { Read, Write, Both };
struct Point { int x; int y; };
int order(int a, int b) { return (a <=> b) < 0 ? -1 : (a <=> b) > 0 ? 1 : 0; }
int main() {
    using enum Mode;
    Mode m = Both;
    Point p = { .x = 3, .y = 4 };
    int xs[3] = { 1, 2, 3 };
    int t = 0;
    for (int k = 2; int x : xs) t += x * k;
    if constexpr (sizeof(int) == 4) t += 1; else t -= 1;
    [[likely]] if (t > 0) t += square(2);
    printf("%d %d %d %.1f %d %d %d %d %d %ld\n", t, twice(21), add(1, 2), add(1.5, 2.0), sum3(1, 2, 3), (int) (sum3(1.0, 2.0, 3.0) == 6.0), order(1, 2), order(5, 5), (int) m + p.x + p.y + limit, (long) __cplusplus);
    return 0;
}
