#include <stdlib.h>
int main(void) { own char *a = malloc(8); own char *b = move(a); a[0] = 1; free(b); return 0; }
