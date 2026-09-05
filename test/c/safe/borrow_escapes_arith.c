#include <stdlib.h>
char *f(void) { own char *p = malloc(8); defer(p) { free(p); } return p + 1; }
int main(void) { return f() != 0; }
