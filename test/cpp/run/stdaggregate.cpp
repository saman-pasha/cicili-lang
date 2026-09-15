#include <cstdio>
#include <vector>
#include <string>
struct Rec { std::string name; int n; };
struct Grid { int cells[4]; int w; Grid() : cells(), w(2) {} };
struct Grid2 { int cells[3]; std::string tag; };
struct Trio { std::string s[2]; int k; };
struct Names { std::vector<std::string> v; Names(std::initializer_list<std::string> il) : v(il) {} };
int main() {
    std::vector<Rec> v;
    Rec r{"alpha", 1};
    v.push_back(r);
    v.push_back(Rec{"beta", 2});
    v.push_back(r);
    r.name = "changed";
    printf("%d %s %s %s\n", (int) v.size(), v[0].name.c_str(), v[1].name.c_str(), v[2].name.c_str());
    Grid g;
    printf("%d %d %d\n", g.cells[0], g.cells[3], g.w);
    Grid2 g2{};
    printf("%d %d %d\n", g2.cells[0], g2.cells[2], (int) g2.tag.size());
    Grid2 g3 = {{1, 2, 3}, "t"};
    Grid2 g4 = g3;
    printf("%d %d %s\n", g4.cells[1], g4.cells[2], g4.tag.c_str());
    Trio t;
    t.s[1] = "b";
    t.k = 3;
    Trio u = t;
    u.s[0] = "a";
    printf("%s%s %s%s %d\n", t.s[0].c_str(), t.s[1].c_str(), u.s[0].c_str(), u.s[1].c_str(), u.k);
    Names ns = {"x", "yy"};
    printf("%d %s\n", (int) ns.v.size(), ns.v[1].c_str());
    return 0;
}
