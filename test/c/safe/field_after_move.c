#include <stdio.h>
#include <stdlib.h>
person { own char *name; int age; }
int main(void) { own person *p = malloc(sizeof *p); p->name = malloc(4); own char *n = move(p->name); printf("%s", p->name); free(n); free(p); return 0; }
