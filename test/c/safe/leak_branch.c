#include <stdlib.h>
int main(int n, char **v) { own char *p = malloc(8); if (n > 1) free(p); return 0; }
