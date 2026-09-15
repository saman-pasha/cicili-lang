// The detection idiom libc++'s __weak_result_type is written on: two static
// member functions of one name, one variadic and one a template over the base
// being looked for, read through a decltype at CLASS SCOPE -- where there is no
// `this' at all and an ellipsis is C++'s worst match ([over.ics.ellipsis]).
#include <cstdio>
template <class A, class R> struct UF { typedef A argument_type; typedef R result_type; };
template <class T> struct Der {
private:
  static void find(...);
  template <class A, class R> static UF<A, R> find(const volatile UF<A, R> *);
public:
  using type = decltype(find(static_cast<T *>(nullptr)));
  static const bool value = !__is_same(type, void);
};
struct Q : UF<int, long> {};
struct Z {};
template <class T, bool = Der<T>::value> struct Maybe : Der<T>::type {};
template <class T> struct Maybe<T, false> {};
int main() {
    printf("%d %d\n", (int) Der<Q>::value, (int) Der<Z>::value);
    Maybe<Q>::result_type r = 42;                  // the base's typedef, inherited where it was found
    printf("%d %d\n", (int) r, (int) sizeof(Maybe<Q>::argument_type));
    return 0;
}
