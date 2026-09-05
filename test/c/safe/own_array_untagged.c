#include <stdlib.h>
typedef struct { own int *slot[2]; } box;
int main(void) { own box *b = calloc(1, sizeof(box)); free(b); return 0; }
