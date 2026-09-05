#include <stdlib.h>
person { own char *name; int age; }
static void strip(person *p) { free(p->name); }
int main(void) { return 0; }
