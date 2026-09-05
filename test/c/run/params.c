#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* parameters as borrows: a plain pointer parameter is the caller's -- read,
   passed on, returned, never stored, freed or moved; an own field reached
   through it may be replaced, and must be whole again when the callee returns */
person { own char *name; int age; }
static own char *dup(const char *s) { own char *d = malloc(strlen(s) + 1); strcpy(d, s); return d; }
static const char *skip(const char *s) { return s + 1; }                          /* a borrow of a parameter returns */
static const char *pick(const char **v, int i) { const char *q = v[i]; return q; } /* an element, through a local */
static int len(const char *s) { int n = 0; while (s[n]) n++; return n; }          /* an int taken out is an int */
static void bump(person *p) { p->age++; }                                         /* changed through a borrow */
static void rename_to(person *p, const char *s) { free(p->name); p->name = dup(s); }   /* the field replaced: whole again */
static void take(own char *s) { printf("took %s\n", s); free(s); }
static void hand(void (*f)(own char *), own char *s) { f(s); }                    /* an own parameter through a function pointer */
int main(void) {
    const char *words[] = { "alpha", "beta" };
    printf("%s %s %d\n", skip("xyz"), pick(words, 1), len("four"));
    person a = { dup("ann"), 30 };
    bump(&a);
    rename_to(&a, "anne");
    printf("%s %d\n", a.name, a.age);
    free(a.name);
    hand(take, dup("gift"));
    void (*fp)(own char *) = take;
    own char *g = dup("more");
    fp(g);                                                                        /* consumed through the pointer */
    return 0;
}
