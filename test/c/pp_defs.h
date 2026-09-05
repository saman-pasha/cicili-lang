/* a header the raw reader cannot take (the false group is not C), so the
   preprocessor runs: directives, conditionals, the macro operators, the
   built-ins -- and what they compute reaches pp.c as enumerators and a typedef */
#if 0
this line is not C at all, and the raw read stops on it
#endif
#define AREA(w, h) ((w) * (h))
#define CAT(a, b) a ## b
#define STR(x) #x
#define ADD2(a, b) ((a) + (b))
#define ADD3(a, ...) ((a) + ADD2(__VA_ARGS__))
#define TWICE(x) (2 * \
                  (x))
#if defined(AREA) && AREA(2, 3) == 6 && !defined(NOPE)
#  define TAKEN 1
#elif 1
#  define TAKEN 2
#else
#  define TAKEN 3
#endif
#if __has_include(<stdio.h>) && !__has_include(<no_such_header_anywhere.h>)
#  define HAS 1
#else
#  define HAS 0
#endif
#ifdef __LP64__
#  define BITS 64
#else
#  define BITS 32
#endif
#undef NOPE
#if NOPE + 7 == 7
#  define UNKNOWN_IS_ZERO 7
#else
#  define UNKNOWN_IS_ZERO 0
#endif
typedef int CAT(my, type);
static const char *pp_text = STR(hello world);
enum { PP_AREA = AREA(3, 4), PP_CAT = CAT(4, 2), PP_SUM = ADD3(1, 2, 3), PP_TWICE = TWICE(21), PP_TAKEN = TAKEN,
       PP_HAS = HAS, PP_BITS = BITS, PP_ZERO = UNKNOWN_IS_ZERO, PP_LINE = __LINE__ };
