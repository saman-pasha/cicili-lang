#include <stdlib.h>
point { int x; double y; }
static void drop(own point *p) { free(p); }
int main(void) { own point *a = malloc(sizeof *a); drop(a); return a->x; }
