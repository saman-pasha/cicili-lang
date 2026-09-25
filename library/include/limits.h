/* cicili-lang's own <limits.h>, the freestanding one C requires of the compiler (LP64 targets):
   the values are the predefined macros' (__INT_MAX__ and kin, the reference compiler's), and
   the C library's own limits.h follows through #include_next where there is one -- glibc's
   defines nothing of these itself under a GNU-shaped compiler and asks the compiler's header
   for them (it tests _GCC_LIMITS_H_, which GCC's file defines and this one does too), so on
   Linux INT_MAX was undefined until this header existed; the SDK's on macOS defines them all
   itself, and a redefinition to the same value is nothing. */
#ifndef _CICILI_LIMITS_H
#define _CICILI_LIMITS_H
#define _GCC_LIMITS_H_

#define CHAR_BIT __CHAR_BIT__
#define SCHAR_MAX __SCHAR_MAX__
#define SCHAR_MIN (-__SCHAR_MAX__ - 1)
#define UCHAR_MAX (__SCHAR_MAX__ * 2 + 1)
#ifdef __CHAR_UNSIGNED__
#define CHAR_MIN 0
#define CHAR_MAX UCHAR_MAX
#else
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#endif
#define SHRT_MAX __SHRT_MAX__
#define SHRT_MIN (-__SHRT_MAX__ - 1)
#define USHRT_MAX (__SHRT_MAX__ * 2 + 1)
#define INT_MAX __INT_MAX__
#define INT_MIN (-__INT_MAX__ - 1)
#define UINT_MAX (__INT_MAX__ * 2U + 1U)
#define LONG_MAX __LONG_MAX__
#define LONG_MIN (-__LONG_MAX__ - 1L)
#define ULONG_MAX (__LONG_MAX__ * 2UL + 1UL)
#define LLONG_MAX __LONG_LONG_MAX__
#define LLONG_MIN (-__LONG_LONG_MAX__ - 1LL)
#define ULLONG_MAX (__LONG_LONG_MAX__ * 2ULL + 1ULL)
#ifndef MB_LEN_MAX
#define MB_LEN_MAX 16
#endif

/* C23: the widths ([tab:limits.h]), and the bit-precise integers' bound */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
#define BOOL_WIDTH 1
#define CHAR_WIDTH CHAR_BIT
#define SCHAR_WIDTH CHAR_BIT
#define UCHAR_WIDTH CHAR_BIT
#define SHRT_WIDTH 16
#define USHRT_WIDTH 16
#define INT_WIDTH 32
#define UINT_WIDTH 32
#define LONG_WIDTH 64
#define ULONG_WIDTH 64
#define LLONG_WIDTH 64
#define ULLONG_WIDTH 64
#define BITINT_MAXWIDTH 128
#endif

/* the C library's own (PATH_MAX and POSIX's, on the platforms that have them), past this file */
#if __has_include_next(<limits.h>)
#include_next <limits.h>
#endif
#endif
