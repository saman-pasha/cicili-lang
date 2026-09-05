/* templates: function and class templates, template-id types, explicit arguments, aliases */
template <typename T> T max2(T a, T b) { return a > b ? a : b; }
template <typename T, int N> struct Buf { T d[N]; int size() const { return N; } };
template <class K, class V = int> class Map { K k; V v; };
using Ints = Buf<int, 8>;
namespace std { template <typename T> struct vector { T *p; int n; }; }
int main() {
    Buf<int, 4> b;
    Map<char> m;
    std::vector<int> v;
    std::vector<std::vector<int>> vv;
    Ints buf8;
    int x = max2<int>(1, 2);
    int y = max2(3, 4);
    return b.size() + x + y;
}
