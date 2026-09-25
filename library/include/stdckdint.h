/* cicili-lang's own <stdckdint.h> (C23 7.20): checked integer arithmetic over the overflow builtins, which the
   lowering computes exactly (in 128 bits) and answers with a bool saying whether the result fit its slot */
#ifndef _CICILI_STDCKDINT_H
#define _CICILI_STDCKDINT_H
#define __STDC_VERSION_STDCKDINT_H__ 202311L
#define ckd_add(result, a, b) __builtin_add_overflow((a), (b), (result))
#define ckd_sub(result, a, b) __builtin_sub_overflow((a), (b), (result))
#define ckd_mul(result, a, b) __builtin_mul_overflow((a), (b), (result))
#endif
