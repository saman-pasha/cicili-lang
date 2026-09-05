#include <stdlib.h>
static void take(own char *s) { free(s); }
int main(void) { void (*fp)(own char *) = take; own char *g = malloc(4); fp(g); free(g); return 0; }
