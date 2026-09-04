#include <stdio.h>
#include <stdlib.h>

/* a buffer and a file, each released at every exit of its scope */
int count_lines(const char *path, int max) {
    FILE *f = fopen(path, "r");
    if (f == NULL) return -1;
    defer(f) { fclose(f); }

    buf := malloc(max);
    if (buf == NULL) return -2;
    defer(buf) { free(buf); }

    n := 0;
    while (fgets(buf, max, f) != NULL) {
        n++;
        if (n > 1000) return n;        /* free(buf), then fclose(f) */
    }
    return n;                          /* the same two, in that order */
}

int g(void) { return defer(1, 2); }
