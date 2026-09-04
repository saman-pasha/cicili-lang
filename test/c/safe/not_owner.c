#include <stdlib.h>
int main(void) { char *q = malloc(8); own char *r = move(q); free(r); return 0; }
