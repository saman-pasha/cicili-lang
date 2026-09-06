/* std::vector (M6, the seventh step): the compiler's own <vector>, an own
   block grown by doubling, freed by the destructor; push_back, size, [],
   back, a range-for over it, a vector of structs, a vector by pointer */
#include <stdio.h>
#include <vector>
struct P { int x, y; };
static int total(std::vector<int> *v) { int s = 0; for (int i = 0; i < v->size(); i++) s += (*v)[i]; return s; }
int main() {
    std::vector<int> v;
    for (int i = 1; i <= 10; i++) v.push_back(i * i);
    int s = 0;
    for (int x : v) s += x;
    v[0] = 100;
    v.back() = 1;
    std::vector<P> ps;
    P p;
    p.x = 3; p.y = 4;
    ps.push_back(p);
    p.x = 5;
    ps.push_back(p);
    int px = 0;
    for (P q : ps) px += q.x * q.y;
    printf("%d %d %d %d %d %d %d\n", v.size(), s, v[0], v[9], total(&v), ps.size(), px);
    return 0;
}
