#include <stdio.h>
#include <string.h>

/* C11 and C17 forms that came late: a variable length array (sized at run time, sizeof
   with it), _Thread_local storage (a global and a static local), and the prefixed literals
   L"...", u"...", U"...", u8"..." and their chars */
_Thread_local int counter = 5;
static _Thread_local int hidden;
int sum(int n, int a[n]) { int s = 0; for (int i = 0; i < n; i++) s += a[i]; return s; }
static int tick(void) { static _Thread_local int t; return ++t; }
int main(int argc, char **argv) {
    int n = argc + 2;
    int v[n];
    for (int i = 0; i < n; i++) v[i] = i * 10;
    const __WCHAR_TYPE__ *w = L"wide";
    const char *u = u8"utf8";
    const unsigned short *s16 = u"ab";
    const unsigned int *s32 = U"xyzé";
    int wl = 0; while (w[wl]) wl++;
    hidden = 7; counter++; tick(); tick();
    printf("%d %d %d %d %d %d %d %d\n", n, (int) sizeof v, (int) (sizeof v / sizeof v[0]), sum(n, v), wl, (int) w[1], (int) strlen(u), counter + hidden + tick());
    printf("%d %d %d %d %d %d\n", (int) sizeof(L'x'), (int) L'x', (int) u8'y', (int) s16[1], (int) s32[3], (int) sizeof(U'z'));
    return 0;
}
