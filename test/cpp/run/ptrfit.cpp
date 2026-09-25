// A POINTER TO A CLASS TAKES A POINTER TO THAT CLASS OR A CLASS DERIVED FROM IT ([conv.ptr]; 0.94): any class pointer took
// any, so libc++ 18's `__has_destroy<allocator<__tree_node>, string *>' held and the node's destructor ran on the string's
// address -- in the scoring, the template acceptance and the arity-only last resort, where the detection idiom is decided.
#include <cstdio>
#include <type_traits>
#include <utility>
struct A { int a; };
struct B { int b; };
struct D : A { int d; };
struct Alloc { void destroy(A *p) { p->a = 1; } };
template <class Al, class P, class = void> struct has_destroy : std::false_type {};
template <class Al, class P> struct has_destroy<Al, P, decltype((void) std::declval<Al>().destroy(std::declval<P>()))> : std::true_type {};
static int g(A *) { return 1; }
static int g(B *) { return 2; }
static int g(int *) { return 3; }
int main() {
  A aa; B bb; D dd; int n = 0;
  printf("%d %d %d %d\n", (int) has_destroy<Alloc, A *>::value, (int) has_destroy<Alloc, B *>::value, (int) has_destroy<Alloc, D *>::value, (int) has_destroy<Alloc, int *>::value);
  printf("%d %d %d %d\n", g(&aa), g(&bb), g(&dd), g(&n));
  return 0;
}
