#include "abi.h"
s4 mk_s4(int a) { s4 v = { a }; return v; }                          double sum_s4(s4 v) { return v.a; }
s8 mk_s8(int a, int b) { s8 v = { a, b }; return v; }                double sum_s8(s8 v) { return v.a + 10.0 * v.b; }
f8 mk_f8(float x, float y) { f8 v = { x, y }; return v; }            double sum_f8(f8 v) { return v.x + 10.0 * v.y; }
s12 mk_s12(int a, int b, int c) { s12 v = { a, b, c }; return v; }  double sum_s12(s12 v) { return v.a + 10.0 * v.b + 100.0 * v.c; }
d16 mk_d16(double x, double y) { d16 v = { x, y }; return v; }      double sum_d16(d16 v) { return v.x + 10.0 * v.y; }
l16 mk_l16(long a, long b) { l16 v = { a, b }; return v; }          double sum_l16(l16 v) { return v.a + 10.0 * v.b; }
di mk_di(double d, int i) { di v = { d, i }; return v; }            double sum_di(di v) { return v.d + 10.0 * v.i; }
fi mk_fi(float f, int i) { fi v = { f, i }; return v; }             double sum_fi(fi v) { return v.f + 10.0 * v.i; }
csi mk_csi(char c, short s, int i) { csi v = { c, s, i }; return v; } double sum_csi(csi v) { return v.c + 10.0 * v.s + 100.0 * v.i; }
f12 mk_f12(float a, float b, float c) { f12 v = { { a, b, c } }; return v; } double sum_f12(f12 v) { return v.v[0] + 10.0 * v.v[1] + 100.0 * v.v[2]; }
df mk_df(double d, float f) { df v = { d, f }; return v; }          double sum_df(df v) { return v.d + 10.0 * v.f; }
l24 mk_l24(long a, long b, long c) { l24 v = { a, b, c }; return v; } double sum_l24(l24 v) { return v.a + 10.0 * v.b + 100.0 * v.c; }
d24 mk_d24(double x, double y, double z) { d24 v = { x, y, z }; return v; } double sum_d24(d24 v) { return v.x + 10.0 * v.y + 100.0 * v.z; }
pi mk_pi(char *p, int i) { pi v = { p, i }; return v; }             double sum_pi(pi v) { return v.p[0] + 10.0 * v.i; }
double via_s8(s8 v) { return sum_s8(bump_s8(v)); }
double via_d16(d16 v) { return sum_d16(bump_d16(v)); }
double via_di(di v) { return sum_di(bump_di(v)); }
double via_l24(l24 v) { return sum_l24(bump_l24(v)); }
double via_f12(f12 v) { return sum_f12(bump_f12(v)); }
double via_pi(pi v) { return sum_pi(bump_pi(v)); }
double via_d24(d24 v) { return sum_d24(bump_d24(v)); }
double via_csi(csi v) { return sum_csi(bump_csi(v)); }
bf mk_bf(int a, int b, short s, int c) { bf v = { a, b, s, c }; return v; }
double sum_bf(bf v) { return v.a + 10.0 * v.b + 100.0 * v.s + 1000.0 * v.c; }
un mk_un(double d) { un v; v.d = d; return v; }
double sum_un(un v) { return v.d; }
double via_bf(bf v) { return sum_bf(bump_bf(v)); }
double via_un(un v) { return sum_un(bump_un(v)); }
