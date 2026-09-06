/* a typedef inside a block: the passes' symbol table takes it from the function's body */
#include <stdio.h>
int main(void) {
    typedef int T;
    T x = 1;
    { typedef long U; U y = x + 2; x = (int) y; }
    for (int i = 0; i < 2; i++) { typedef T Tt; Tt z = 10; x += z; }
    printf("%d %d\n", x, (int) sizeof(T));
    return 0;
}
