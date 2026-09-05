/* cicili-lang's own <stdarg.h>: the variadic argument list as LLVM's builtins have it */
#ifndef _CICILI_STDARG_H
#define _CICILI_STDARG_H
typedef __builtin_va_list va_list;
#define va_start(ap, param) __builtin_va_start(ap, param)
#define va_end(ap) __builtin_va_end(ap)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#define va_copy(dest, src) __builtin_va_copy(dest, src)
#endif
