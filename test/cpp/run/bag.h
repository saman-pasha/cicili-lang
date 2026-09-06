/* a string and a container of the program's own, over own memory: what the
   fixtures use where a program would use libc++'s -- whose templates the
   compiler does not instantiate yet. A local header, read whole: its classes
   and templates reach every unit that includes it. */
#ifndef BAG_H
#define BAG_H
#include <stdlib.h>
#include <string.h>
class Name {
    own char *d;
    int n;
public:
    Name() : d(nullptr), n(0) { }
    Name(const char *s) : d(nullptr), n(0) { n = (int) strlen(s); d = (own char *) malloc(n + 1); memcpy(d, s, n + 1); }
    ~Name() { free(d); }
    int size() const { return n; }
    const char *c_str() const { return d; }
    Name &operator+=(const char *s) { int m = (int) strlen(s); d = (own char *) realloc(d, n + m + 1); memcpy(d + n, s, m + 1); n = n + m; return *this; }
    Name &operator+=(char c) { d = (own char *) realloc(d, n + 2); d[n] = c; n = n + 1; d[n] = 0; return *this; }
    bool operator==(const char *s) const { return strcmp(d, s) == 0; }
};
template <typename T> class Bag {
    own T *d;
    int n;
    int cap;
public:
    Bag() : d(nullptr), n(0), cap(0) { }
    ~Bag() { for (int i = 0; i < n; i++) d[i].~T(); free(d); }
    int size() const { return n; }
    T &operator[](int i) { return d[i]; }
    void push(T x) {
        if (n == cap) { cap = cap ? cap * 2 : 4; d = (own T *) realloc(d, cap * sizeof(T)); }
        d[n] = move(x);
        n = n + 1;
    }
    void pop() { n = n - 1; d[n].~T(); }
};
#endif
