#include <stdlib.h>
node { char *name; }
int main(void) { own char *s = malloc(4); node n; char *q = s; n.name = q; free(s); return 0; }
