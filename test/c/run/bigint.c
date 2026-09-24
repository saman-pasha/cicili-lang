/* A literal past 2^60 -- cocolog's integers are 61-bit (the finding), so `9223372036854775807LL' arrived as -1 and libc++'s string
   read, bounded by `numeric_limits<streamsize>::max()', never looped (0.94): both lexers give `big(Atom)', nothing folds it, and
   the lowering spells it into the IR as it is, `u0x...' for the hex form. */
#include <stdio.h>
#include <limits.h>
int main(void) {
    long long a = 9223372036854775807LL;
    unsigned long long b = 18446744073709551615ULL;
    long long c = LLONG_MAX;
    long long d = LLONG_MIN;
    unsigned long e = ULONG_MAX;
    unsigned long long f = 0xFFFFFFFFFFFFFFFF;
    long long g = 0x1000000000000000;
    unsigned long long h = 0b1111111111111111111111111111111111111111111111111111111111111111;
    long long i = 0100000000000000000000;
    long long j = 1152921504606846975;
    static long long k = 9223372036854775807;
    printf("%lld %llu %lld %lld %lu\n", a, b, c, d, e);
    printf("%llu %lld %llu %lld %lld %lld\n", f, g, h, i, j, k);
    printf("%d %d\n", (int) (a > 1152921504606846975LL), (int) (b == f));
    return 0;
}
