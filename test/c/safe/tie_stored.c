#include <stdlib.h>
typedef struct view { const char *s; int n; } view;
int main(void) { own char *a = malloc(8); own char *b = malloc(8); view v <*> a = { a, 1 }; v.s = b; free(a); free(b); return v.n; }
