#include <iostream>
#include <string>
struct P {
  int x, y;
  friend std::ostream &operator<<(std::ostream &os, const P &p) { return os << "(" << p.x << "," << p.y << ")"; }
};
struct Q {
  int v;
  template <class S> friend S &operator<<(S &os, const Q &q) { return os << "Q" << q.v; }
};
int main() {
  std::cout << P{1, 2} << " " << Q{7} << std::endl;
  short s = -3; unsigned short us = 65535; int i = -42; unsigned ui = 42u; long l = -1L; unsigned long ul = 18446744073709551615UL;
  long long ll = -9007199254740993LL; unsigned long long ull = 1ULL << 63;
  float f = 2.5f; double d = 3.25; bool b = true; char c = 'z'; unsigned char uc = 'Q'; signed char sc = 'k';
  std::cout << s << ' ' << us << ' ' << i << ' ' << ui << ' ' << l << ' ' << ul << ' ' << ll << ' ' << ull << '\n';
  std::cout << f << ' ' << d << ' ' << b << ' ' << c << ' ' << uc << ' ' << sc << std::endl;
  std::cout << (const void *) 4096 << std::endl;
  std::cout << nullptr << std::endl;
  std::string str = "str";
  std::cout << str << ' ' << str.c_str() << std::endl;
  std::cout.write("write\n", 6);
  std::cout.put('P').put('\n');
  std::cout.flush();
  std::cerr.rdbuf(std::cout.rdbuf());
  std::cerr << "to cerr" << std::endl;
  std::clog.rdbuf(std::cout.rdbuf());
  std::clog << "to clog" << std::endl;
  std::streamoff pos = std::cout.tellp();
  std::cout << pos << std::endl;
  std::cout << std::cout.good() << std::cout.fail() << std::cout.bad() << std::cout.eof() << std::endl;
  std::cout << (std::cout.tie() == nullptr) << ' ' << (std::cin.tie() == &std::cout) << std::endl;
  return 0;
}
