/* the lexer's corners, for the native lexer against the DCG (k84, test/c/lexer.c): every
   token kind, every number shape, every escape, the punctuators, the # lines */
#include <stdio.h>
#define WIDE(a, b) ((a) \
                    + (b))
# define SPACED 1
int hex = 0x1F + 0XfF + 0x0u + 0xABCDEFul;
int oct = 017 + 0 + 00 + 0777L;
int dec = 42 + 9u + 9U + 9l + 9L + 9ul + 9ULL + 09;
int bin = 0b1011 + 0B1 + 0b1010u + 0b11'11 + 1'000'000 + 0xFF'FF + 0'17;   /* C23 and C++14: the binary literal and the digit separator */
double fl = 1.5 + 1. + .5 + 1e5 + 1E-3 + 2.5e+2 + 1.5f + 1.F + 3.0L + 1e5f + 0. + 1'5.2'5 + 1'0e1'0;
unsigned long long big = 18446744073709551615ULL + 9223372036854775807 + 1152921504606846975 + 0xFFFFFFFFFFFFFFFF + 0x1000000000000000ul + 0x0FFFFFFFFFFFFFFF + 0b1000000000000000000000000000000000000000000000000000000000000 + 0100000000000000000000 + 1'152'921'504'606'846'976; /* past 2^60: big(Atom) in both lexers, decimal or 0x */
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
int cxx20 = a <=> b; /* C++20's three-way comparison, and its words: in C plain names, in C++ keywords in both lexers */
int words = concept + requires + co_await + co_yield + co_return + consteval + constinit + char8_t;
unsigned long z = 4uz + 5z + 6ZU; /* C++23: the size_t suffix, a long under LP64 */
const char *esc = "\x{41}\o{102}\u{43}\104\u00e9\U0001F600\0\7x"; /* C++23: delimited escapes; universal character names as UTF-8; octal */
char oct = '\101'; char ucn = '\u{7a}';
int wbs = 1wb + 2uwb + 3WB + 4UWB + 5uWB + 0x1Fwb + 0b11uwb; /* C23: the _BitInt literal suffix, in both lexers */
double efl = 1.5f16 + 2.5F32 + 3.0f64 + 4.0f128 + 0.5bf16 + 0.25BF16 + 1e2f32; /* C++23: the extended floating-point suffixes, dropped as f is */
int last = 1;
#if 0
this is not C but the lexer reads it: @ $ ` are where it stops
#endif
const char *pfx = u8"utf8" "plain"; const int *w = L"wide" u"u16" U"u32"; int wc = L'w' + u'x' + U'y' + u8'z'; /* C11's prefixed literals, in both lexers */
