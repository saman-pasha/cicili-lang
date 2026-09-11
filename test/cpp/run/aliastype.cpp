#include <stdio.h>

/* An ALIAS of a class template's instance used as a type: libc++ writes
   typedef integral_constant<bool, false> false_type and takes it as a parameter
   (vector::__copy_assign_alloc(const vector &, false_type)). The name must carry
   its instance, or the lowering meets a template-id it cannot take. */

template <class T, T v> struct konst { static const T value = v; T get() const { return v; } };

typedef konst<bool, false> no_t;
typedef konst<bool, true>  yes_t;

static int pick(no_t)  { return 10; }
static int pick(yes_t) { return 20; }

struct Holder {
    int take(no_t)  { return 1; }
    int take(yes_t) { return 2; }
};

int main() {
    no_t n;
    yes_t y;
    Holder h;
    printf("%d %d %d %d %d\n", pick(n), pick(y), h.take(n), h.take(y), (int) y.get());
    return 0;
}
