#include <stdio.h>
#include <stddef.h>
#include <limits.h>
#include <stdckdint.h>
#include <stdbit.h>

/* C23's language (-std=c23), the rest: _BitInt(N) lowered as LLVM's iN, nullptr_t, unreachable(),
   the empty initializer, checked arithmetic (<stdckdint.h>), the bit utilities (<stdbit.h>) over
   _Generic, alignof, and C11's _Generic, _Alignof and _Alignas */
_BitInt(7) small = 60;
unsigned _BitInt(12) twelve = 4000;
struct pair { _BitInt(7) lo; unsigned _BitInt(40) hi; };
#define KIND(x) _Generic((x), int: 1, unsigned int: 2, double: 3, char *: 4, const char *: 4, default: 9)
static const char *cname = "c";
int main(void) {
    _BitInt(7) a = small + 3;
    unsigned _BitInt(12) b = twelve + 95;
    _BitInt(100) big = 1;
    big = big << 70;
    long back = (long) (big >> 40);
    struct pair pr = { -5, 1099511627775ul };
    nullptr_t np = nullptr;
    int *p = nullptr;
    int r; bool o1 = ckd_add(&r, INT_MAX, 1);
    int s; bool o2 = ckd_mul(&s, 6, 7);
    long t; bool o3 = ckd_sub(&t, 3, 5);
    unsigned char u; bool o4 = ckd_add(&u, 200, 100);
    int e = {};
    struct pair z = {};
    _Alignas(16) int aligned = 5;
    const int ci = 9; typeof_unqual(ci) mut = ci; mut++;   /* typeof_unqual: the const is off */
    printf("%d %d %ld %d %d %d %d %d %ld %d %d %d %d %d\n", (int) a, (int) b, back, p == np, o1, o2, s, o3, t, o4, u, e, (int) z.lo, aligned);
    printf("%d %ld %d %d %d\n", (int) pr.lo, (long) pr.hi, (int) sizeof(struct pair), (int) sizeof(_BitInt(100)), (int) alignof(_BitInt(100)));
    printf("%u %u %u %u %u %u %d %u\n", stdc_leading_zeros(1u), stdc_trailing_zeros(8u), stdc_count_ones(255u), stdc_bit_width(255u),
           stdc_bit_floor(100u), stdc_bit_ceil(100u), stdc_has_single_bit(64u), stdc_first_leading_one((unsigned char) 0x10));
    printf("%u %u %u %u %lu\n", stdc_leading_ones((unsigned char) 0xF0), stdc_trailing_ones((unsigned short) 7), stdc_count_zeros((unsigned char) 1),
           stdc_first_trailing_zero(7u), stdc_bit_ceil(17ul));
    printf("%d %d %d %d %d %d %d\n", KIND(1), KIND(1u), KIND(1.5), KIND(cname), KIND(a), (int) _Alignof(double), mut);
    if (a > 0) return 0;
    unreachable();
}
