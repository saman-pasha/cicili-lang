#include <iostream>
int main() {
  int c = std::cin.get();
  std::cout << c << std::endl;
  char ch = 0;
  std::cin.get(ch);
  std::cout << ch << std::endl;
  char buf[8];
  std::cin.get(buf, 8);
  std::cout << buf << " " << std::cin.gcount() << std::endl;
  std::cin.get(buf, 8, 'y');
  std::cout << buf << " " << std::cin.gcount() << " " << std::cin.peek() << std::endl;
  std::cin.ignore();
  std::cin.unget();
  std::cout << (char) std::cin.get() << std::endl;
  std::cin.putback('Q');
  std::cout << (char) std::cin.get() << std::endl;
  std::cin.ignore(100, '\n');
  int n = 0;
  while (std::cin.get() != std::char_traits<char>::eof()) n++;
  std::cout << n << " " << (std::cin.eof() ? 1 : 0) << " " << (std::cin.fail() ? 1 : 0) << std::endl;
  return 0;
}
