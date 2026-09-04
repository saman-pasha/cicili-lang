#include <stdlib.h>
int main(void) { own char *p = malloc(8); p = malloc(8); free(p); return 0; }
