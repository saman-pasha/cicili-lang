/* cicili-lang's own <stdbit.h> (C23 7.18): the bit and byte utilities. The suffixed functions (_uc, _us, _ui,
   _ul, _ull) are written over the bit builtins the lowering turns into LLVM's intrinsics at the argument's own
   width, and the type-generic forms choose one by _Generic, which the reader decides at the read. */
#ifndef _CICILI_STDBIT_H
#define _CICILI_STDBIT_H
#define __STDC_VERSION_STDBIT_H__ 202311L
#define __STDC_ENDIAN_LITTLE__ __ORDER_LITTLE_ENDIAN__
#define __STDC_ENDIAN_BIG__ __ORDER_BIG_ENDIAN__
#define __STDC_ENDIAN_NATIVE__ __BYTE_ORDER__

#define __CCL_STDBIT(sfx, T) \
static inline unsigned int stdc_leading_zeros_##sfx(T x) { return (unsigned int) __builtin_clzg(x); } \
static inline unsigned int stdc_leading_ones_##sfx(T x) { return (unsigned int) __builtin_clzg((T) ~x); } \
static inline unsigned int stdc_trailing_zeros_##sfx(T x) { return (unsigned int) __builtin_ctzg(x); } \
static inline unsigned int stdc_trailing_ones_##sfx(T x) { return (unsigned int) __builtin_ctzg((T) ~x); } \
static inline unsigned int stdc_first_leading_one_##sfx(T x) { return x ? (unsigned int) __builtin_clzg(x) + 1u : 0u; } \
static inline unsigned int stdc_first_leading_zero_##sfx(T x) { return stdc_first_leading_one_##sfx((T) ~x); } \
static inline unsigned int stdc_first_trailing_one_##sfx(T x) { return x ? (unsigned int) __builtin_ctzg(x) + 1u : 0u; } \
static inline unsigned int stdc_first_trailing_zero_##sfx(T x) { return stdc_first_trailing_one_##sfx((T) ~x); } \
static inline unsigned int stdc_count_ones_##sfx(T x) { return (unsigned int) __builtin_popcountg(x); } \
static inline unsigned int stdc_count_zeros_##sfx(T x) { return (unsigned int) (sizeof(T) * 8) - (unsigned int) __builtin_popcountg(x); } \
static inline bool stdc_has_single_bit_##sfx(T x) { return __builtin_popcountg(x) == 1; } \
static inline unsigned int stdc_bit_width_##sfx(T x) { return (unsigned int) (sizeof(T) * 8) - (unsigned int) __builtin_clzg(x); } \
static inline T stdc_bit_floor_##sfx(T x) { return x ? (T) ((T) 1 << (stdc_bit_width_##sfx(x) - 1u)) : (T) 0; } \
static inline T stdc_bit_ceil_##sfx(T x) { return x <= 1 ? (T) 1 : (T) ((T) 1 << stdc_bit_width_##sfx((T) (x - 1))); }
__CCL_STDBIT(uc, unsigned char)
__CCL_STDBIT(us, unsigned short)
__CCL_STDBIT(ui, unsigned int)
__CCL_STDBIT(ul, unsigned long)
__CCL_STDBIT(ull, unsigned long long)
#undef __CCL_STDBIT

#define __CCL_STDBIT_GENERIC(name, x) _Generic((x), unsigned char: name##_uc, unsigned short: name##_us, unsigned int: name##_ui, unsigned long: name##_ul, unsigned long long: name##_ull)(x)
#define stdc_leading_zeros(x) __CCL_STDBIT_GENERIC(stdc_leading_zeros, x)
#define stdc_leading_ones(x) __CCL_STDBIT_GENERIC(stdc_leading_ones, x)
#define stdc_trailing_zeros(x) __CCL_STDBIT_GENERIC(stdc_trailing_zeros, x)
#define stdc_trailing_ones(x) __CCL_STDBIT_GENERIC(stdc_trailing_ones, x)
#define stdc_first_leading_one(x) __CCL_STDBIT_GENERIC(stdc_first_leading_one, x)
#define stdc_first_leading_zero(x) __CCL_STDBIT_GENERIC(stdc_first_leading_zero, x)
#define stdc_first_trailing_one(x) __CCL_STDBIT_GENERIC(stdc_first_trailing_one, x)
#define stdc_first_trailing_zero(x) __CCL_STDBIT_GENERIC(stdc_first_trailing_zero, x)
#define stdc_count_ones(x) __CCL_STDBIT_GENERIC(stdc_count_ones, x)
#define stdc_count_zeros(x) __CCL_STDBIT_GENERIC(stdc_count_zeros, x)
#define stdc_has_single_bit(x) __CCL_STDBIT_GENERIC(stdc_has_single_bit, x)
#define stdc_bit_width(x) __CCL_STDBIT_GENERIC(stdc_bit_width, x)
#define stdc_bit_floor(x) __CCL_STDBIT_GENERIC(stdc_bit_floor, x)
#define stdc_bit_ceil(x) __CCL_STDBIT_GENERIC(stdc_bit_ceil, x)
#endif
