#include <stdio.h>
#include <stdlib.h>
int work(int n) {
    printf("open %d\n", n);
    defer(n) { printf("close %d\n", n); }
    char *buf = malloc(8);
    defer(buf) { free(buf); printf("freed\n"); }
    for (int i = 0; i < 3; i++) {
        defer(i) { printf("iter %d done\n", i); }
        if (i == n) { printf("early\n"); return i; }
    }
    printf("done\n");
    return 10;
}
int main(void) { int r = work(1) + work(5); printf("%d\n", r); return r; }
