// M6's twenty-ninth step: std::vector<int> from libc++, COMPILED FROM ITS OWN BODY, linked and run. What it needed
// past the object file of 0.60: ITANIUM NAME MANGLING for what a library header only declares (libc++ ships
// `__ZNSt3__122__libcpp_verbose_abortEPKcz', and every name this compiler emitted was unmangled, so the link found
// nothing); a REFERENCE MEMBER BOUND rather than assigned (`__destroy_vector' holds a `vector &'); PLACEMENT NEW,
// which is what `std::__construct_at' is and every container's way of making an element; and a CAST TO A REFERENCE
// TYPE read as a bind rather than a conversion (`static_cast<_Tp &&>(__t)' is std::forward's whole body).
#include <cstdio>
#include <vector>

int main() {
  std::vector<int> v;
  for (int i = 0; i < 10; i++) v.push_back(i * i);          // ten pushes: the slow path, __split_buffer, the relocation
  int s = 0;
  for (int i = 0; i < (int) v.size(); i++) s += v[i];
  printf("%d %d %d %d %d\n", (int) v.size(), (int) (v.capacity() >= v.size()), s, v.front(), v.back());

  std::vector<double> d;                                     // a second element type: the whole machinery again
  d.push_back(1.5);
  d.push_back(2.25);
  printf("%g %g %d\n", d[0], d[1], (int) d.size());
  return 0;
}
