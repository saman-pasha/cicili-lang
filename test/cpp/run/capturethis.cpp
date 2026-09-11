#include <stdio.h>

/* A LAMBDA CAPTURING THIS: inside a member function a lambda reaches the
   enclosing object through the captured pointer -- a data member named bare,
   a member called, `this->' written out, and a default capture taking it. */

struct Counter {
    int n;
    int step;

    Counter(int s) : n(0), step(s) { }

    int bump() { n = n + step; return n; }

    int twice() {
        auto f = [this] { return bump() + bump(); };          /* [this], and a method called */
        return f();
    }

    int plus(int k) {
        auto g = [&] { return n + k + step; };                /* [&] takes this beside the local */
        return g();
    }

    static int id(int x) { return x; }

    int through() {
        auto h = [this](int x) { return this->n + id(x); };   /* this-> written out, and a static */
        return h(5);
    }
};

int main() {
    Counter c(3);
    int a = c.twice();
    int b = c.plus(10);
    int d = c.through();
    printf("%d %d %d %d\n", a, b, d, c.n);
    return 0;
}
