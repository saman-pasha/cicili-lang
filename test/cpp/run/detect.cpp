// M6's fifteenth step: the detection idiom libc++ builds its allocator traits on -- a detector whose partial
// specialization is chosen by void_t<Op<Args...>> matching void, Op a template template parameter bound to an alias,
// the pattern a non-deduced context evaluated after the other elements bind (a member absent: no match, the default).
#include <cstdio>
template <class...> using void_t = void;
template <class Default, class AlwaysVoid, template <class...> class Op, class... Args>
struct detector { using type = Default; static const int found = 0; };
template <class Default, template <class...> class Op, class... Args>
struct detector<Default, void_t<Op<Args...>>, Op, Args...> { using type = Op<Args...>; static const int found = 1; };
template <class Default, template <class...> class Op, class... Args>
using detected_or_t = typename detector<Default, void, Op, Args...>::type;
template <class T> using pointer_member = typename T::pointer;
struct WithPtr { using pointer = short *; };
struct NoPtr { int x; };
template <class T> using ptr_of = detected_or_t<T *, pointer_member, T>;
int main() {
  ptr_of<WithPtr> a = nullptr;
  ptr_of<NoPtr> b = nullptr;
  printf("%d %d %d %d\n", (int) sizeof(*a), (int) sizeof(*b),
         detector<int, void, pointer_member, WithPtr>::found, detector<int, void, pointer_member, NoPtr>::found);
  return 0;
}
