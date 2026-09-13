#include <iostream>
int main() {
  std::cout << "hello" << std::endl;
  std::cout << "two" << std::endl << "three" << std::endl;
  std::cout << "four" << std::flush;
  std::cout << std::endl;
  return 0;
}
