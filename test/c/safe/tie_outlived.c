#include <stdlib.h>
int main(void) { own char *a = malloc(8); own char *b <*> a = malloc(8); free(a); free(b); return 0; }
