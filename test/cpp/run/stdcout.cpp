// <iostream> as it ships: std::cout, the library's own object, written to through libc++'s
// basic_ostream, its sentry, ostreambuf_iterator, __pad_and_output and the streambuf's
// virtuals -- every declared-only member by its Itanium name, the stream's virtual base laid
// out as the ABI lays it, the locale returned through sret. The first C++ program of this
// compiler's to speak to the standard library's runtime.
#include <iostream>
int main() {
  std::cout << "hello, cicili++\n";
  std::cout << "one " << "two\n";
  return 0;
}
