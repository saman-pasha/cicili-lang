#include <iostream>
#include <string>
int main() {
  int n = 0;
  std::cin >> n;
  std::string line;
  std::getline(std::cin >> std::ws, line);
  std::cout << n << " [" << line << "]" << std::endl;
  std::cin >> std::ws;
  char c = (char) std::cin.get();
  std::cout << c << std::endl;
  std::string w;
  std::cin >> std::ws >> w;
  std::cout << "<" << w << "> " << (std::cin.eof() ? 1 : 0) << std::endl;
  std::cin >> std::ws;
  std::cout << (std::cin.fail() ? 1 : 0) << std::endl;
  return 0;
}
