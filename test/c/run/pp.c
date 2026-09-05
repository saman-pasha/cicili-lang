/* the preprocessor, in cocolog: pp_defs.h is read through it (its false
   group is not C), and its macros' results arrive here as constants */
#include <stdio.h>
#include "pp_defs.h"

int main(void) {
    mytype v = PP_AREA;
    printf("%d %d %d %d %d %d %d %d %d\n", v, PP_CAT, PP_SUM, PP_TWICE, PP_TAKEN, PP_HAS, PP_BITS, PP_ZERO, PP_LINE);
    return 0;
}
