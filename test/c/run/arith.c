#include <stdio.h>
int main(void) {
    int a = 7, b = 2;
    long big = 3000000000L;
    unsigned u = 4000000000u;
    double d = 2.5;
    float f = 1.25f;
    char c = 'A';
    printf("%d %d %d %d %d\n", a + b, a - b, a * b, a / b, a % b);
    printf("%ld %u %g %g\n", big * 2, u / 3, d * a, f + d);
    printf("%d %d %d %d\n", a > b, a == b, a != b && b < 3, !a || b);
    printf("%d %d %d %d\n", a << 2, a >> 1, a & b, a | b ^ 1);
    printf("%d %d %c %d\n", (int) d, (int) (d * 3), c + 1, (char) 300);
    printf("%g %d\n", (double) a / b, -a + +b);
    int x = 5; x += 3; x *= 2; x -= 1; x /= 3; x %= 4; x <<= 2; x |= 1;
    printf("%d %d %d\n", x, x++ + ++x, x--);
    return a * b + (int) d;
}
