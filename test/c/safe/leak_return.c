#include <stdlib.h>
int f(int n) { own char *p = malloc(8); if (n) return 1; free(p); return 0; }
int main(void) { return f(1); }
