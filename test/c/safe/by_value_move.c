/* a struct with an own field handed BY VALUE hands the field to the callee's
   copy, as `person d = c' hands it to d: the caller's is moved, and freeing
   it is a use after move (the callee must consume its copy's) */
#include <stdlib.h>
#include <string.h>
typedef struct person { own char *name; int age; } person;
static int age_of(person p) { int a = p.age; free(p.name); return a; }
int main(void) {
    person c = { strdup("cy"), 50 };
    int a = age_of(c);
    free(c.name);
    return a;
}
