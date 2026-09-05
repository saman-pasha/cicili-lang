#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* a borrow: a plain pointer that took its value from an owner, bound to it */
static int length(const char *s) { return (int) strlen(s); }   /* looks only */
int main(void) {
    own char *p = malloc(16);
    strcpy(p, "hello");
    char *q = p;                    /* q borrows p */
    char *r = p + 1;                /* so does r */
    printf("%s %s %d\n", q, r, length(q));
    q = "static";                   /* q is a borrow no more */
    free(p);                        /* r dangles now; q does not */
    printf("%s\n", q);
    own char *s = malloc(8);
    { const char *t = s; strcpy(s, "x"); printf("%s\n", t); }   /* a borrow in an inner scope */
    free(s);
    return 0;
}
