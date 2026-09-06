/* range-for over an array, by value and by reference; enum class; the casts;
   new and delete of a scalar and of an array (an owner to the check) */
#include <stdio.h>
enum class Color : int { Red, Green = 3 };
int main() {
    int xs[3] = { 1, 2, 3 };
    int t = 0;
    for (int x : xs) t += x;
    for (auto &x : xs) x = x * 2;
    for (const int &x : xs) t += x;
    Color c = Color::Green;
    long big = static_cast<long>(t) * 1000000000L;
    unsigned u = unsigned(t);
    int *p = new int(41);
    *p = *p + 1;
    int *ys = new int[4];
    for (int i = 0; i < 4; i++) ys[i] = i * i;
    int s = 0;
    for (int i = 0; i < 4; i++) s += ys[i];
    printf("%d %d %ld %u %d %d %d\n", t, (int) c, big, u, *p, s, c == Color::Red);
    delete p;
    delete[] ys;
    return 0;
}
