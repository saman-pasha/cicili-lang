#include <iostream>
#include <string>
int main() {
  std::string line;
  std::getline(std::cin, line);
  std::cout << "[" << line << "] " << line.size() << std::endl;
  std::string rest;
  std::getline(std::cin, rest, ',');
  std::cout << "<" << rest << ">" << std::endl;
  char buf[16];
  std::cin.getline(buf, 16);
  std::cout << buf << std::endl;
  int n = 0;
  while (std::getline(std::cin, line)) n++;
  std::cout << n << " " << line.size() << std::endl;
  return 0;
}
