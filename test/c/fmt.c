#include <stdio.h>
typedef struct point { int x; double y; } point_t;
struct node { point_t at; const char *name; unsigned long id; };
int main(void) {
    n := 42;
    name := "cicili";
    p := (point_t){ 1, 2.5 };
    println("n = {} name = {name} again {0} p = {p} 100%", n);
    s := format("{} + {} = {}", 1, 2, 3);
    print("{s}\n");
    struct node nd = { p, "root", 7ul };
    println("{nd} {{braces}}");
    return 0;
}
