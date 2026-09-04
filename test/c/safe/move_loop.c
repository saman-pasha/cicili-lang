#include <stdlib.h>
int main(void) { own char *p = malloc(8); for (int i = 0; i < 3; i++) { free(p); } return 0; }
