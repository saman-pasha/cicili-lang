/* the user's own macros, expanded by the preprocessor in cocolog -- and the
   headers' known to it: NULL, EOF, INT_MAX, stdin */
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#define SQ(x) ((x) * (x))
#define MAXN 4
#define GREETING "hello, " "macros"
#define STR(x) #x
#define CAT(a, b) a##b
#ifdef __LP64__
#  define BITS 64
#else
#  define BITS 32
#endif
#if !defined(NOPE) && SQ(3) == 9
#  define OK 1
#else
#  define OK 0
#endif
int CAT(tw, o) = 2;
int main(void) {
    int a[MAXN] = { 1, 2, 3, 4 };
    char *p = NULL;
    int sum = 0;
    for (int i = 0; i < MAXN; i++) sum += SQ(a[i]);
    if (p == NULL && stdin != NULL) sum += 100;
    printf("%s %d %d %d %d %s %d %d %d\n", GREETING, sum, BITS, OK, two, STR(a b), EOF, INT_MAX > 0, __LINE__);
    return 0;
}
