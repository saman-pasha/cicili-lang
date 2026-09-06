/* C++20: concepts and requires, the three-way comparison, consteval and constinit, char8_t,
   coroutines (read, refused), using enum, a range-for with an initializer, designated
   initializers, an abbreviated function template, a template lambda, if constexpr */
#include <stdio.h>
template <typename T> concept Number = requires (T a, T b) { a + b; a * b; { a < b } -> Boolean; };
template <typename T> concept Boolean = requires (T x) { !x; };
template <typename T> requires Number<T> T twice(T x) { return x + x; }
template <typename T> struct Box { T v; };
constexpr int square(int x) { return x * x; }
consteval int cube(int x) { return x * x * x; }
constinit int limit = 100;
char8_t glyph = 'g';
enum class Mode { Read, Write };
struct Point { int x; int y; };
auto add(auto a, auto b) { return a + b; }
int order(int a, int b) { return (a <=> b) < 0 ? -1 : (a <=> b) > 0 ? 1 : 0; }
struct Task { struct promise_type { }; };
Task count() { co_return; }
int main() {
    using enum Mode;
    Mode m = Write;
    Point p = { .x = 3, .y = 4 };
    int xs[3] = { 1, 2, 3 };
    int t = 0;
    for (int k = 2; int x : xs) t += x * k;
    auto pick = []<typename T>(T a, T b) { return a < b ? a : b; };
    if constexpr (sizeof(int) == 4) t += 1; else t -= 1;
    [[likely]] if (t > 0) t += square(2);
    return twice(t) + add(1, 2) + order(1, 2) + (int) m + p.x + cube(2) + limit + (int) glyph;
}
