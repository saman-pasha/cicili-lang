#include <iostream>
#include <iomanip>
int main() {
  std::cout << std::hex << 255 << ' ' << std::oct << 8 << ' ' << std::dec << 10 << std::endl;
  std::cout << std::showbase << std::hex << 255 << std::noshowbase << std::dec << ' ' << std::uppercase << std::hex << 255 << std::nouppercase << std::dec << std::endl;
  std::cout << std::boolalpha << true << ' ' << std::noboolalpha << true << std::endl;
  std::cout << std::setw(6) << 42 << '|' << std::left << std::setw(6) << 42 << '|' << std::right << std::setfill('*') << std::setw(6) << 42 << std::setfill(' ') << '|' << std::internal << std::setw(6) << -42 << '|' << std::right << std::endl;
  std::cout << std::fixed << std::setprecision(3) << 3.14159 << ' ' << std::scientific << 314.159 << ' ' << std::defaultfloat << std::setprecision(6) << 2.5 << std::endl;
  std::cout << std::showpos << 5 << std::noshowpos << ' ' << std::showpoint << 1.0 << std::noshowpoint << ' ' << 1.0 << std::endl;
  std::cout << std::setbase(16) << 255 << std::setbase(10) << ' ' << std::setiosflags(std::ios_base::hex) << 255 << std::resetiosflags(std::ios_base::hex) << ' ' << 255 << std::endl;
  std::cout.width(4);
  std::cout << 7 << '|' << std::cout.width() << std::endl;
  std::cout.precision(2);
  std::cout << 1.23456 << ' ' << std::cout.precision() << std::endl;
  std::cout.fill('-');
  std::cout << std::setw(5) << 1 << std::endl;
  std::cout.setf(std::ios_base::hex, std::ios_base::basefield);
  std::cout << 255 << std::endl;
  std::cout.unsetf(std::ios_base::hex);
  std::cout << 255 << std::endl;
  std::cout << ((std::cout.flags() & std::ios_base::dec) ? 1 : 0) << std::endl;
  return 0;
}
