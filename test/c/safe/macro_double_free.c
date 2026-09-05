#include <stdlib.h>
#include "../macros.pl"
int main(void) { own char *p = malloc(8); freeit(p); freeit(p); return 0; }
