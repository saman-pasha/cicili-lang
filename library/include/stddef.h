/* cicili-lang's own <stddef.h>, for LP64 targets: the compiler's header, not a library's */
#ifndef _CICILI_STDDEF_H
#define _CICILI_STDDEF_H
typedef unsigned long size_t;
typedef long ptrdiff_t;
#ifndef __cplusplus
typedef int wchar_t;
#endif
typedef long double max_align_t;
#define NULL ((void *)0)
#define offsetof(t, m) __builtin_offsetof(t, m)
#endif
