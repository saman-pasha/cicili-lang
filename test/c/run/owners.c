#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* the safe part: owners are linear -- consumed exactly once on every path */
static void take(own char *s) { printf("took %s\n", s); free(s); }
static own char *make(const char *text) { own char *s = malloc(strlen(text) + 1); strcpy(s, text); return s; }
int count(const char *path) {
    own char *buf = malloc(8);
    defer(buf) { free(buf); printf("buf freed\n"); }
    if (path[0] == 'x') return -1;          /* the defer frees buf on this path too */
    buf[0] = 'a';
    return 1;
}
int main(void) {
    own char *a = make("one");
    own char *b = move(a);                   /* a is consumed; b owns it now */
    take(b);                                 /* b is consumed by take's own parameter */
    own char *c = make("two");
    if (strlen(c) > 1) { free(c); } else { free(c); }
    printf("%d %d\n", count("x"), count("y"));
    own char *d = malloc(4);
    d[0] = 'z';
    printf("%c\n", d[0]);
    free(d);
    d = malloc(2);                           /* a consumed owner may own again */
    free(d);
    return 0;
}
