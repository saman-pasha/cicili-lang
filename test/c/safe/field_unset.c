#include <stdlib.h>
person { own char *name; int age; }
static own person *bad(void) { own person *p = malloc(sizeof *p); p->age = 1; return p; }
int main(void) { own person *p = bad(); free(p->name); free(p); return 0; }
