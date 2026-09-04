#include <stdlib.h>
int main(void) { own char *p = malloc(8); free(p); p[0] = 1; return 0; }
