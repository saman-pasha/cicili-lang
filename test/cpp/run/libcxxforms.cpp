#include <stdio.h>

/* The forms libc++'s vector walks through, written in a program's own code:
   a typedef inside a block (which the table cannot hold one of per function),
   a prvalue used as a place, an alias template called as a type, a static const
   that folds where it is named, and the bit count the compiler answers. */

template <class T> struct Box {
    T v;
    int twice() const { return (int) v * 2; }
};

template <class T> using Alias = Box<T>;
template <class T> using Ptr = T *;

struct Point { int x; int y; };

static Point make() { Point p = { 3, 4 }; return p; }
static Box<int> boxed() { Box<int> b = { 21 }; return b; }

template <class T> struct Bits {
    static const int digits = __builtin_popcountg((unsigned long) ~(unsigned long) 0);
    static const int half = digits / 2;
};

typedef Box<int> IntBox;

static int first() {
    typedef int number;                       /* each function has its own `number' */
    number n = 5;
    return n;
}

static int second() {
    typedef double number;
    number d = 2.5;
    return (int) (d * 4);
}

int main() {
    Alias<int> a = { 7 };
    IntBox ib = IntBox();
    Ptr<int> p = Ptr<int>(0);
    printf("%d %d %d %d %d %d %d %d\n",
           first(), second(), make().x, boxed().twice(), a.twice(), Bits<long>::half, ib.v, p == 0);
    return 0;
}
