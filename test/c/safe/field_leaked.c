#include <stdlib.h>
person { own char *name; int age; }
int main(void) { own person *p = malloc(sizeof *p); p->name = malloc(4); free(p); return 0; }
