#include <stdio.h>

/* C23's preprocessor (-std=c23): __VA_OPT__, #embed with its parameters, __has_embed,
   __has_c_attribute; and the C library's limits, from the compiler's own <limits.h> */
#include <limits.h>
#define LOG(fmt, ...) printf(fmt __VA_OPT__(,) __VA_ARGS__)
#define F(a, ...) a __VA_OPT__(* (__VA_ARGS__))
#define PACK(...) (0 __VA_OPT__(+ (__VA_ARGS__)))
static const unsigned char data[] = {
#embed "embed.txt"
};
static const unsigned char part[] = {
#embed "embed.txt" limit(3) prefix(1,) suffix(, 99)
};
static const int none[] = {
#embed "empty.txt" if_empty(7, 8)
};
#if __has_embed("embed.txt") == __STDC_EMBED_FOUND__
#define E1 1
#endif
#if __has_embed("empty.txt") == __STDC_EMBED_EMPTY__
#define E2 1
#endif
#if __has_embed("nowhere.bin") == __STDC_EMBED_NOT_FOUND__
#define E3 1
#endif
#if __has_c_attribute(nodiscard) == 202003L && __has_c_attribute(__maybe_unused__) && !__has_c_attribute(frob)
#define A1 1
#endif
int main(void) {
    LOG("plain\n");
    LOG("%d %d\n", 1, 2);
    printf("%d %d %d\n", (int) sizeof data, data[0], data[sizeof data - 1]);
    printf("%d %d %d %d %d\n", (int) (sizeof part / sizeof part[0]), part[0], part[1], part[3], part[4]);
    printf("%d %d\n", none[0], none[1]);
    printf("%d %d %d %d %d %d %d\n", E1, E2, E3, A1, F(6, 7), F(5), PACK(1, 2) + PACK());
    printf("%d %d %d %d\n", INT_MAX, CHAR_BIT, UCHAR_MAX, INT_MIN);
    return 0;
}
