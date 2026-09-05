#include <stdlib.h>
char *f(void) { own char *p = malloc(8); char *q = p; defer(p) { free(p); } return q; }
int main(void) { return f() != 0; }
