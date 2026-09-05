#include <stdlib.h>
int main(void) { own char *p = malloc(8); char *r = p + 1; free(p); return r[0]; }
