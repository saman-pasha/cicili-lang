/* an own array bounded by a sibling field: the struct's last member, room
   for it allocated and counted by the developer, drained to the count */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct bag { int n; own char *s[n]; } bag;
static own char *copy(const char *t) { own char *d = malloc(strlen(t) + 1); strcpy(d, t); return d; }
static own bag *new_bag(int k) { own bag *b = calloc(1, sizeof(bag) + k * sizeof(char *)); b->n = k; return b; }
int main(void) {
    own bag *b = new_bag(3);
    b->s[0] = copy("a"); b->s[1] = copy("b"); b->s[2] = copy("c");
    b->s[1] = copy("B");                       /* the old one freed */
    own char *t = move(b->s[2]);               /* out: the slot null */
    printf("%d %s %s %s %s\n", (int) sizeof(bag), b->s[0], b->s[1], b->s[2] ? b->s[2] : "-", t);
    free(t);
    free(b);                                   /* the drain, to b->n */
    return 0;
}
