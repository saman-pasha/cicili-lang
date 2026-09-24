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
/* C23: nullptr's own type, and unreachable() -- the store keys a C23 read apart from the C17 one */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
typedef typeof(nullptr) nullptr_t;
#define unreachable() __builtin_unreachable()
#define __STDC_VERSION_STDDEF_H__ 202311L
#endif
#endif
