#include <stdlib.h>
struct s { char *q; } g;
int main(void) { g.q = malloc(8); return 0; }
