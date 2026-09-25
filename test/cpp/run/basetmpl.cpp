#include <cstdio>
template <class... Ts> struct types {};
template <class, class> struct is_ok { static const bool value = true; };
template <class, class> struct is_no { static const bool value = false; };
template <bool... P> struct all_ { static const bool value = true; };
struct false_type { static const bool value = false; };
template <bool B, class T = void> struct enable_if {};
template <class T> struct enable_if<true, T> { typedef T type; };
template <bool B, class T = void> using enable_if_t = typename enable_if<B, T>::type;
struct base_sf {
  template <template <class, class...> class Trait, class... L, class... R>
  static auto do_test(types<L...>, types<R...>) -> all_<enable_if_t<Trait<L, R>::value, bool>{true}...>;
  template <template <class...> class> static auto do_test(...) -> false_type;
};
template <class T, class U> struct conv : base_sf {
  static const bool value = decltype(do_test<is_ok>(types<T>{}, types<U>{}))::value;
  static const bool no = decltype(do_test<is_no>(types<T>{}, types<U>{}))::value;
};
int main() { printf("%d %d\n", (int) conv<int, int>::value, (int) conv<int, int>::no); return 0; }
