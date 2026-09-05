#include <stdio.h>
#include "abi.h"
/* the cicili-lang side: bumps every field by one and hands the struct back */
s8 bump_s8(s8 v) { v.a += 1; v.b += 1; return v; }
d16 bump_d16(d16 v) { v.x += 1; v.y += 1; return v; }
di bump_di(di v) { v.d += 1; v.i += 1; return v; }
l24 bump_l24(l24 v) { v.a += 1; v.b += 1; v.c += 1; return v; }
f12 bump_f12(f12 v) { v.v[0] += 1; v.v[1] += 1; v.v[2] += 1; return v; }
pi bump_pi(pi v) { v.p += 1; v.i += 1; return v; }
d24 bump_d24(d24 v) { v.x += 1; v.y += 1; v.z += 1; return v; }
csi bump_csi(csi v) { v.c += 1; v.s += 1; v.i += 1; return v; }
bf bump_bf(bf v) { v.a += 1; v.b += 1; v.s += 1; v.c += 1; return v; }
un bump_un(un v) { v.d += 1; return v; }
int main(void) {
    char text[] = "AB";
    printf("%g %g %g %g %g %g %g\n", sum_s4(mk_s4(1)), sum_s8(mk_s8(1, 2)), sum_f8(mk_f8(1.5f, 2)), sum_s12(mk_s12(1, 2, 3)),
           sum_d16(mk_d16(1.5, 2.5)), sum_l16(mk_l16(1, 2)), sum_di(mk_di(1.5, 2)));
    printf("%g %g %g %g %g %g %g\n", sum_fi(mk_fi(1.5f, 2)), sum_csi(mk_csi(1, 2, 3)), sum_f12(mk_f12(1, 2, 3)), sum_df(mk_df(1.5, 2)),
           sum_l24(mk_l24(1, 2, 3)), sum_d24(mk_d24(1, 2, 3)), sum_pi(mk_pi(text, 2)));
    printf("%g %g %g %g %g %g %g %g\n", via_s8(mk_s8(1, 2)), via_d16(mk_d16(1, 2)), via_di(mk_di(1, 2)), via_l24(mk_l24(1, 2, 3)),
           via_f12(mk_f12(1, 2, 3)), via_pi(mk_pi(text, 2)), via_d24(mk_d24(1, 2, 3)), via_csi(mk_csi(1, 2, 3)));
    printf("%g %g %g %g\n", sum_bf(mk_bf(1, 2, 3, 4)), via_bf(mk_bf(1, 2, 3, 4)), sum_un(mk_un(1.5)), via_un(mk_un(1.5)));
    s12 s = mk_s12(4, 5, 6);
    d24 d = mk_d24(4, 5, 6);
    printf("%d %d %d %g %g %g\n", s.a, s.b, s.c, d.x, d.y, d.z);
    return 0;
}
