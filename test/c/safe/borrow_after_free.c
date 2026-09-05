#include <stdlib.h>
int main(void) { own char *p = malloc(8); char *q = p; free(p); q[0] = 1; return 0; }
