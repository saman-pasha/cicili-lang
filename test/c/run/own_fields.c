#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* owners inside structs: a field declared own is an owner of its own, tracked
   as p->name under an own pointer and as c.name in a struct held by value */
person { own char *name; int age; }

static own char *dup(const char *s) { own char *d = malloc(strlen(s) + 1); strcpy(d, s); return d; }

/* from malloc the field is unset; it must be given something before the struct is returned */
static own person *make(const char *name, int age) {
    own person *p = malloc(sizeof *p);
    p->name = dup(name);
    p->age = age;
    return p;                                /* complete: moved to the caller with its field */
}
/* an own parameter arrives complete; freeing the struct demands the field consumed first */
static void drop(own person *p) { free(p->name); free(p); }
/* a field moved out; the struct freed without it */
static own char *take_name(own person *p) { own char *n = move(p->name); free(p); return n; }
/* by pointer: the fields are only looked at (by value, the copy would take
   them over, as `person d = c' does: test/c/safe/by_value_move.c) */
static int total(person *a, person *b) { return a->age + b->age; }

int main(void) {
    own person *a = make("ann", 30);
    printf("%s %d\n", a->name, a->age);
    drop(a);
    own person *b = make("bob", 40);
    own char *n = take_name(b);
    printf("%s\n", n);
    free(n);
    person c = { dup("cy"), 50 };            /* by value: c.name is an owner */
    person d = c;                            /* the copy takes the field over: c.name is moved */
    printf("%s %d\n", d.name, d.age);
    free(d.name);
    person e = { 0, 60 };                    /* a null field: nothing to free, may be given something */
    e.name = dup("eve");
    defer(e) { free(e.name); }               /* consumed at main's exit */
    own person *f = make("fay", 70);
    defer(f) { free(f->name); free(f); }
    printf("%s %s %d\n", e.name, f->name, total(&e, &e));
    return 0;
}
