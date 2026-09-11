#include <stdio.h>

/* FREE FUNCTION OVERLOADS, chosen by their arguments and mangled apart: C++ gives each
   its own symbol where C has one name one function. libc++ writes ten overloads of
   __convert_to_integral this way, one per integer type. */

struct Point { int x; int y; };

int    kind(int n)          { return 1 + n * 0; }
int    kind(double d)       { return 2 + (int) (d * 0); }
int    kind(const char *s)  { return 3 + (s[0] - s[0]); }
int    kind(Point p)        { return 4 + p.x * 0; }
int    kind()               { return 5; }
int    kind(int a, int b)   { return 6 + a + b; }

unsigned long widen(unsigned long n) { return n; }   /* an exact match must beat the template */
template <class T> unsigned long widen(T v) { return (unsigned long) v + 1000; }

static int seen(int n);                              /* declared first, defined below */
static int seen(int n) { return n * 2; }

int main() {
    Point p = { 7, 8 };
    unsigned long big = 4000000000UL;
    printf("%d %d %d %d %d %d %lu %lu %d\n",
           kind(1), kind(2.5), kind("x"), kind(p), kind(), kind(10, 20),
           widen(big), widen(3), seen(21));
    return 0;
}
