#include <stdio.h>

/* A scoped enum's UNDERLYING TYPE decides its bytes and its LLVM type; one with no
   enumerators at all is libc++'s strong typedef (enum class __element_count : size_t { }),
   and shares its members' shape with an empty struct, which it is not. */

enum class Count : unsigned long { };
enum class Color : unsigned char { red, green, blue = 9 };
enum Plain : short { one = 1, two };

static unsigned long take(Count n) { return (unsigned long) n; }

int main() {
    Count n = Count(1234567890123UL);
    printf("%lu %d %d %d %d %d\n", take(n), (int) sizeof(Count), (int) sizeof(Color),
           (int) Color::blue, (int) sizeof(Plain), (int) two);
    return 0;
}
