#include <cstdio>
template <unsigned long... Is> struct idx {};
template <class T, T... Vs> struct iseq { template <unsigned long S> using to_idx = idx<(Vs + S)...>; };
template <unsigned long E, unsigned long S = 0> using mkidx = typename __make_integer_seq<iseq, unsigned long, E - S>::template to_idx<S>;
template <class... Ts> struct types {};
template <class T, class I> struct flat;
template <template <class...> class Tu, class... Ts, unsigned long... Is> struct flat<Tu<Ts...>, idx<Is...>> {
  template <class T> using ap = types<__type_pack_element<Is, Ts...>...>;
  static const int n = sizeof...(Is);
};
template <class... Ts> struct tup {};
template <class T> struct count;
template <class... Ts> struct count<types<Ts...>> { static const int n = sizeof...(Ts); };
int main() { printf("%d %d %d %d\n", flat<tup<int, char>, mkidx<2>>::n, flat<tup<int>, mkidx<0>>::n, count<flat<tup<int, char>, mkidx<2>>::ap<int>>::n, count<flat<tup<int>, mkidx<0>>::ap<int>>::n); return 0; }
