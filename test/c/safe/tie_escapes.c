#include <stdlib.h>
int main(void) { own char *a = malloc(8); own char *p <*> a = malloc(8); own char *m = move(p); free(m); free(a); return 0; }
