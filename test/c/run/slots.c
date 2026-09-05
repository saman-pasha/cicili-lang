/* a local own array: its elements null or owned, the old one freed when a slot
   is overwritten, the slot nulled when an element leaves, the rest drained at
   the scope's end */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static own char *copy(const char *s) { own char *d = malloc(strlen(s) + 1); strcpy(d, s); return d; }
int main(void) {
    own char *s[3] = { 0 };
    s[0] = copy("one"); s[1] = copy("two"); s[2] = copy("three");
    s[1] = copy("deux");                  /* "two" freed by the lowering */
    own char *t = move(s[2]);             /* out: the slot is null */
    free(s[0]);                           /* freed: null too */
    printf("%s %s %s\n", s[0] ? s[0] : "-", s[1], t);
    free(t);
    return 0;                             /* "deux" freed by the drain */
}
