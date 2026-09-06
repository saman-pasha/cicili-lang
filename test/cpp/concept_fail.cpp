/* a constraint that does not hold: S has no operator+, so twice(s) is refused where it is instantiated */
template <typename T> concept Number = requires (T a) { a + a; };
template <typename T> requires Number<T> T twice(T x) { return x + x; }
struct S { int v; };
int main() { S s; s.v = 1; twice(s); return 0; }
