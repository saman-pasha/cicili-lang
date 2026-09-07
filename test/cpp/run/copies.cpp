/* copy and move constructors, operator= by copy and by move, chosen by the argument's
   value category; a by-value parameter of a class with a destructor is a copy the callee
   destroys; a local returned by value moves out (owner's rule: the program's own classes) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int made = 0, freed = 0;
class Name {
    own char *s;
public:
    Name(const char *t) : s(strdup(t)) { made++; }
    Name(const Name &o) : s(strdup(o.s)) { made++; }
    Name(Name &&o) : s(o.s) { o.s = nullptr; }
    Name &operator=(const Name &o) { char *t = strdup(o.s); free(s); s = t; return *this; }
    Name &operator=(Name &&o) { free(s); s = o.s; o.s = nullptr; return *this; }
    ~Name() { if (s) { freed++; free(s); } }
    const char *c_str() const { return s ? s : "-"; }
};
int len(Name n) { return (int) strlen(n.c_str()); }
Name make(const char *t) { Name r(t); return r; }
int main() {
    Name a("alpha");
    Name b = a;
    Name c(std::move(a));
    b = c;
    Name d = make("delta");
    c = std::move(d);
    printf("%s %s %s %s %d %d\n", a.c_str(), b.c_str(), c.c_str(), d.c_str(), len(b), made);
    return 0;
}
