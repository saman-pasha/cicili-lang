#include <cstdio>
template <class... Ts> struct types {};
template <class, class> struct is_ok { static const bool value = true; };
template <bool... P> struct all_ { static const bool value = true; };
struct sf {
  template <template <class, class...> class Trait, class... L, class... R>
  static auto test(types<L...>, types<R...>) -> all_<bool{Trait<L, R>::value}...>;
};
enum class Trait { one, two, three };
template <Trait t, int n, class... Ts> struct holder { static const int value = n + (int) t; };
template <Trait t, class... Ts> struct base2 { static const int value = 2 * (int) t; };
int main() { printf("%d %d %d\n", (int) decltype(sf::test<is_ok>(types<int>{}, types<int>{}))::value, holder<Trait::two, 5>::value, base2<Trait::three, int>::value); return 0; }
