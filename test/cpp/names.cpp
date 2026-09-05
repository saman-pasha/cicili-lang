/* namespaces, using, qualified names, extern "C", bool, nullptr, references, auto */
namespace geo {
    int twice(int x) { return 2 * x; }
    namespace inner { int one = 1; }
}
namespace { int hidden = 2; }
using namespace geo;
using geo::twice;
using count_t = unsigned long;
extern "C" {
    int c_add(int a, int b);
    void c_hook(void);
}
extern "C" int c_one(void) { return 1; }
int g = 3;
bool flag = true;
int *none = nullptr;
int &alias(int &x) { return x; }
void take(const geo::inner::what &w, int &&r);
int main() {
    int y = geo::twice(3) + ::g + inner::one;
    bool ok = !false;
    auto z = y + 1;
    count_t n = 4;
    int &r = y;
    return r;
}
