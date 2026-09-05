#include <stdio.h>
#include <stdlib.h>
/* structs by value across the C library's ABI: div_t is eight bytes (one
   INTEGER eightbyte), ldiv_t sixteen (two) -- returned by clang-built code */
int main(void) {
    div_t d = div(17, 5);
    ldiv_t l = ldiv(-17L, 5L);
    printf("%d %d %ld %ld\n", d.quot, d.rem, l.quot, l.rem);
    return 0;
}
