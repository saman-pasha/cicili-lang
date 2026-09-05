/* structs by value of every ABI class, built and summed by clang (abi_helper.c),
   bumped by cicili-lang (abi_main.c), each side calling the other */
typedef struct { int a; } s4;
typedef struct { int a, b; } s8;
typedef struct { float x, y; } f8;
typedef struct { int a, b, c; } s12;
typedef struct { double x, y; } d16;
typedef struct { long a, b; } l16;
typedef struct { double d; int i; } di;
typedef struct { float f; int i; } fi;
typedef struct { char c; short s; int i; } csi;
typedef struct { float v[3]; } f12;
typedef struct { double d; float f; } df;
typedef struct { long a, b, c; } l24;
typedef struct { double x, y, z; } d24;
typedef struct { char *p; int i; } pi;
s4 mk_s4(int a);            double sum_s4(s4 v);
s8 mk_s8(int a, int b);     double sum_s8(s8 v);
f8 mk_f8(float x, float y); double sum_f8(f8 v);
s12 mk_s12(int a, int b, int c);      double sum_s12(s12 v);
d16 mk_d16(double x, double y);       double sum_d16(d16 v);
l16 mk_l16(long a, long b);           double sum_l16(l16 v);
di mk_di(double d, int i);            double sum_di(di v);
fi mk_fi(float f, int i);             double sum_fi(fi v);
csi mk_csi(char c, short s, int i);   double sum_csi(csi v);
f12 mk_f12(float a, float b, float c); double sum_f12(f12 v);
df mk_df(double d, float f);          double sum_df(df v);
l24 mk_l24(long a, long b, long c);   double sum_l24(l24 v);
d24 mk_d24(double x, double y, double z); double sum_d24(d24 v);
pi mk_pi(char *p, int i);             double sum_pi(pi v);
/* defined by the main, called back by the helper: via_T(v) = sum_T(bump_T(v)) */
s8 bump_s8(s8 v);   d16 bump_d16(d16 v); di bump_di(di v);   l24 bump_l24(l24 v);
f12 bump_f12(f12 v); pi bump_pi(pi v);  d24 bump_d24(d24 v); csi bump_csi(csi v);
double via_s8(s8 v); double via_d16(d16 v); double via_di(di v); double via_l24(l24 v);
double via_f12(f12 v); double via_pi(pi v); double via_d24(d24 v); double via_csi(csi v);
