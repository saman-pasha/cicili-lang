// M6's sixteenth step: the detection libc++'s iterator_traits is built on -- two static member function TEMPLATES,
// one taking an ellipsis and one taking defaulted parameters whose types name the member being looked for, picked by
// SFINAE and read through decltype of the call. The ellipsis is C++'s worst match, so it wins only when nothing else
// fits, and a member that is not there must REFUSE, which is what rejects the other candidate.
#include <cstdio>
template <class...> using void_t = void;
struct false_type { static const bool value = false; };
struct true_type { static const bool value = true; };
struct WithTypedefs { using category = int; using diff = long; };
struct Plain { int x; };
template <class T> struct has_typedefs {
private:
  template <class U> static false_type test(...);
  template <class U> static true_type test(void_t<typename U::category> * = nullptr, void_t<typename U::diff> * = nullptr);
public:
  static const bool value = decltype(test<T>(nullptr, nullptr))::value;
};
int main() {
  printf("%d %d\n", (int) has_typedefs<WithTypedefs>::value, (int) has_typedefs<Plain>::value);
  return 0;
}
