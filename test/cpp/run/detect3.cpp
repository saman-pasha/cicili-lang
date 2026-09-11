// M6's twentieth step: the detection trait libc++'s allocator_traits picks max_size with -- a VARIABLE template of
// two parameters whose specialization is matched by a decltype of a member call on a declared-only 'declval'. It asks
// three things: a function template that is declared and never defined instantiates for its TYPE; a member call on a
// class that has no such member REFUSES, which is the rejection; and a member of a reference is a member of what it
// refers to.
#include <cstdio>
template <class T> T &&declval() noexcept;
template <class A, class = void> inline const bool has_max = false;
template <class A> inline const bool has_max<A, decltype((void) declval<A &>().max_size())> = true;
struct WithMax { unsigned long max_size() const { return 7; } };
struct NoMax { int x; };
int main() { printf("%d %d %d\n", (int) has_max<WithMax>, (int) has_max<NoMax>, (int) has_max<const WithMax>); return 0; }
