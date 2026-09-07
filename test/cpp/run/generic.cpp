/* the forms libc++ is made of, on the program's own classes (owner's rule):
   parameter packs, fold expressions, sizeof..., a variadic tuple by partial
   specialization, a full specialization, enable_if over a trait, dependent
   names (typename C::value_type), member templates, a template constructor,
   decltype, the compiler's __is_same */
#include <stdio.h>
template <class... Ts> constexpr int count() { return sizeof...(Ts); }
template <class... Args> int sum(Args... args) { return (args + ... + 0); }
template <class... Args> void show(const char *fmt, Args... args) { printf(fmt, args...); }
template <class... Ts> struct Tuple {};
template <class H, class... T> struct Tuple<H, T...> : Tuple<T...> {
    H head;
    Tuple(H h, T... t) : Tuple<T...>(t...), head(h) {}
};
template <int I, class Tup> struct Getter;
template <class H, class... T> struct Getter<0, Tuple<H, T...>> {
    static H get(const Tuple<H, T...> &t) { return t.head; }
};
template <int I, class H, class... T> struct Getter<I, Tuple<H, T...>> {
    static auto get(const Tuple<H, T...> &t) { return Getter<I - 1, Tuple<T...>>::get(t); }
};
template <class T> struct is_int { static const bool value = false; };
template <> struct is_int<int> { static const bool value = true; };
template <bool B, class T = void> struct enable_if {};
template <class T> struct enable_if<true, T> { typedef T type; };
template <class T, typename enable_if<is_int<T>::value, int>::type = 0> const char *kind(T) { return "int"; }
template <class T, typename enable_if<!is_int<T>::value, int>::type = 0> const char *kind(T) { return "other"; }
struct Ints { typedef int value_type; int data[3]; };
template <class C> typename C::value_type first(const C &c) { return c.data[0]; }
struct Box {
    int v;
    template <class U> Box(U u) : v((int) u) {}
    template <class U> U as() const { return (U) v; }
};
template <class A, class B> auto add(A a, B b) -> decltype(a + b) { return a + b; }
int main() {
    Tuple<int, double, char> t(1, 2.5, 'c');
    show("%d %d %d %d\n", count<int, char, double>(), sum(1, 2, 3, 4), Getter<0, Tuple<int, double, char>>::get(t), (int) Getter<2, Tuple<int, double, char>>::get(t));
    Ints xs = { { 7, 8, 9 } };
    Box b(3.9);
    printf("%s %s %d %d %.1f %d %d\n", kind(1), kind(1.5), first(xs), b.as<int>(), add(1, 2.5), (int) __is_same(int, int), (int) is_int<int>::value);
    return 0;
}
