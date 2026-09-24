/* A LOCAL SHADOWS AN ENUMERATOR (0.94): the lowering asked the enumerators' table before the locals, and the constant
   folding never asked the locals at all. */
#include <stdio.h>
enum { ptr = 14, LIMIT = 40 };
static int take(int ptr) { int r = ptr; return r; }
static int limit(int LIMIT) { return LIMIT * 2; }
int main(void) { printf("%d %d %d\n", take(5), limit(7), ptr + LIMIT); return 0; }
