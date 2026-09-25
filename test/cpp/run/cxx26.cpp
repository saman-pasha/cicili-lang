#include <cstdio>

// C++26 (-std=c++26): pack indexing as a type and as an expression, `= delete("why")', the
// placeholder `_' declared twice, a structured binding as a condition and as an init-statement,
// variadic friends, contract assertions (read and ignored), the relocation words on a class
// head, and #embed in C++.
template <class... Ts> struct First { using type = Ts...[0]; };
template <class... Ts> int second(Ts... args) { return args...[1]; }
struct NoCopy {
    int v;
    NoCopy(int x) : v(x) {}
    NoCopy(const NoCopy &) = delete("no copies");
};
struct Res {
    int code;
    explicit operator bool() const { return code != 0; }
};
Res get(int c) { return Res{c}; }
template <class... Fs> struct Friendly trivially_relocatable_if_eligible { friend Fs...; int secret = 3; };
int inc(int x) pre(x > 0) post(r: r > x) { return x + 1; }
int main() {
    First<double, int>::type d = 2.5;
    int _ = 1;
    int _ = 2;
    if (auto [code] = get(5)) printf("code %d\n", code); else printf("none\n");
    if (auto [code] = get(0)) printf("code %d\n", code); else printf("none\n");
    if (auto [c2] = get(7); c2 > 6) printf("c2 %d\n", c2);
    NoCopy n(4);
    Friendly<NoCopy> fr;
    static const unsigned char bytes[] = {
#embed "embed26.txt"
    };
    printf("%.1f %d %d %d %d %d %d\n", d, second(7, 8, 9), n.v, fr.secret, (int) sizeof bytes, bytes[0], inc(1));
    return 0;
}
