// libc++'s traits and pair over the forms this step opened: is_void of a POINTER (`__remove_cv' of one),
// is_copy_assignable (a type template argument names no declarator), and std::pair's two-argument constructor
// template, chosen by a constexpr static member function template folded at compile time.
#include <utility>
#include <type_traits>
#include <stdio.h>
int main() {
  char *p = 0;
  std::pair<char *, char *> q(p, p);
  printf("%d %d %d %d\n", (int) std::is_void<char *>::value, (int) std::is_void<void>::value,
         (int) std::is_copy_assignable<char *>::value, (int) (q.first == p));
  return (int) std::is_pointer<char *>::value + 2 * (int) std::is_void<const void>::value;
}
