#include <stdlib.h>
static void take(own char *s) { free(s); }
static void give(char *s) { take(s); }
int main(void) { return 0; }
