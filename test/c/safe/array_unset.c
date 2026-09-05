#include <stdlib.h>
typedef struct box { own int *slot[2]; } box;
int main(void) { own box *b = malloc(sizeof(box)); free(b); return 0; }
