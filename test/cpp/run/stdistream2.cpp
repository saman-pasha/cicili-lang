#include <iostream>
#include <string>
int main() {
  std::cin >> std::ws;
  std::cin.sync();
  char c = 0;
  int i = 0;
  std::streamoff off = std::cin.tellg();
  std::cout << off << std::endl;
  bool ok = (bool) std::cin;
  std::cout << ok << std::endl;
  std::cin >> std::noskipws >> c;
  std::cout << (int) c << std::endl;
  std::cin >> std::skipws >> c;
  std::cout << c << std::endl;
  std::cin >> std::hex >> i;
  std::cout << i << std::endl;
  void *p = 0;
  std::cin >> p;
  std::cout << (p == (void *) 16) << std::endl;
  std::cin >> std::dec >> i;
  std::cout << i << " " << std::cin.fail() << std::endl;
  std::cin.clear();
  std::cin.ignore(100, '\n');
  std::string w;
  std::cin >> w;
  std::cout << w << " " << std::cin.eof() << std::endl;
  return 0;
}
