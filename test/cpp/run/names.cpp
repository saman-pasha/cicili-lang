/* C++ that is C with names (M6, the first step): namespaces flattened, using,
   qualified names, extern "C", bool, nullptr, references bound and passed */
#include <stdio.h>
namespace geo {
    int twice(int x) { return 2 * x; }
    namespace inner { int one = 1; }
}
namespace { int hidden = 2; }
using namespace geo;
using geo::twice;
using count_t = unsigned long;
extern "C" int c_one(void) { return 1; }
int g = 3;
bool flag = true;
int *none = nullptr;
int &alias(int &x) { return x; }
void bump(int &x) { x = x + 1; }
int main() {
    int y = geo::twice(3) + ::g + inner::one + hidden + c_one();
    bool ok = !false;
    bool big = y;
    auto z = y + 1;
    count_t n = 4;
    int &r = y;
    r = r + 10;
    bump(r);
    alias(y) = alias(y) + 100;
    printf("%d %d %d %d %d %lu %d %d\n", y, (int) flag, (int) ok, (int) big, z, n, none == nullptr, r);
    return 0;
}
