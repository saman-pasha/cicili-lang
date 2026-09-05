#include <stdlib.h>
node { char *name; }
int main(void) { own char *s = malloc(4); node n; n.name = s; free(s); return 0; }
