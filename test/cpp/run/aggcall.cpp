// `_Algorithm()(a, b, c)': an AGGREGATE temporary -- a class with no constructor, libc++'s algorithm dispatch
// tags -- called through its templated operator(), and an `auto' local taking the result.
#include <stdio.h>
template <class A, class B> struct pr { A first; B second; };
struct alg {
  template <class I, class O> pr<I, O> operator()(I first, I last, O out) const {
    while (first != last) { ++first; ++out; }
    return pr<I, O>{first, out};
  }
};
template <class Alg, class I, class O> int run(I first, I last, O out) {
  auto result = Alg()(first, last, out);
  return (int) (result.second - out) + (int) result.first;
}
int main() { int n = run<alg>(2, 5, 10); printf("%d\n", n); return n; }
