/* the lexer's corners, for the native lexer against the DCG (k84, test/c/lexer.c): every
   token kind, every number shape, every escape, the punctuators, the # lines */
#include <stdio.h>
#define WIDE(a, b) ((a) \
                    + (b))
# define SPACED 1
int hex = 0x1F + 0XfF + 0x0u + 0xABCDEFul;
int oct = 017 + 0 + 00 + 0777L;
int dec = 42 + 9u + 9U + 9l + 9L + 9ul + 9ULL + 09;
double fl = 1.5 + 1. + .5 + 1e5 + 1E-3 + 2.5e+2 + 1.5f + 1.F + 3.0L + 1e5f + 0.;
unsigned long long big = 18446744073709551615ULL + 9223372036854775807 + 1152921504606846975;
char cs[] = "plain" "with \"quotes\" and \\ back" "\n\t\r\0\a\b\f\v\e\x41\x4a\x7Fz" "\q\'\"";
char ch = 'a' + '\n' + '\'' + '\\' + '\x41' + '"';
int ops = a ... b >>= c <<= d := e <*> f -> g ++ h -- i << j >> k <= l >= m == n != o && p || q *= r /= s %= t += u -= v &= w ^= x |= y;
int one = a[b](c){d}.e&f*g+h-i~j!k/l%m<n>o^p|q?r:s;t=u,v;
int words = auto_ + _Bool + _Float16 + bool + class + new + delete + true + nullptr + int_ + inline;
/* a block
   comment */ int after; // a line comment
int x = y /* inline */ + z;
#cocolog
  double(X, Y) :- Y is X * 2.
  greet(N, R) :- R = puts("hi").
#end
int last = 1;
#if 0
this is not C but the lexer reads it: @ $ ` are where it stops
#endif
