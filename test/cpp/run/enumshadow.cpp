// A LOCAL SHADOWS AN ENUMERATOR (0.94): every enumerator is a global name here, a scoped enum's included, and libc++'s
// <format> declares one named `__ptr' -- so `iterator __r(__ptr)' in the tree's node removal built its iterator from
// the enumerator's value where `__ptr' was the parameter. The lowering and the constant folding ask the locals first.
#include <cstdio>
enum class Kind { none, boolean, ptr };
enum { LIMIT = 40 };
struct Box { int v; Box(int p) : v(p) {} };
static int take(int ptr) { Box b(ptr); return b.v + (int) Kind::ptr; }
static int limit(int LIMIT) { return LIMIT * 2; }
int main() { printf("%d %d %d\n", take(5), limit(7), (int) Kind::ptr + LIMIT); return 0; }
