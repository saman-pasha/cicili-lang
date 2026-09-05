#include <stdlib.h>
char *g;
int main(void) { own char *s = malloc(4); char *q = s + 1; g = q; free(s); return 0; }
