#include <stdio.h>
/* static locals: a private global of the function's, initialized once, kept across calls */
static int next(void) { static int n = 10; return ++n; }
static const char *name(int i) <*> names { static const char *names[] = { "zero", "one", "two" }; return names[i]; }   /* the result: static storage */
struct pt { int x, y; };
static struct pt *origin(void) <*> o { static struct pt o = { 1, 2 }; o.x++; return &o; }
int main(void) {
    int a = next(), b = next();
    printf("%d %d %s %s\n", a, b, name(2), name(0));
    origin();
    struct pt *p = origin();
    printf("%d %d\n", p->x, p->y);
    return 0;
}
