#include <iostream>
#include <string>
int main() {
  short s; unsigned short us; int i; unsigned int ui; long l; unsigned long ul; long long ll; unsigned long long ull;
  float f; double d; bool b; char c; unsigned char uc;
  std::cin >> s >> us >> i >> ui >> l >> ul >> ll >> ull >> f >> d >> b >> c >> uc;
  std::cout << s << ' ' << us << ' ' << i << ' ' << ui << ' ' << l << ' ' << ul << ' ' << ll << ' ' << ull << ' ' << f << ' ' << d << ' ' << b << ' ' << c << ' ' << uc << std::endl;
  char word[16];
  std::cin >> word;
  std::cout << word << std::endl;
  std::string line;
  std::getline(std::cin >> std::ws, line);
  std::cout << "[" << line << "]" << std::endl;
  char buf[6];
  std::cin.read(buf, 5);
  buf[5] = 0;
  std::cout << buf << " " << std::cin.gcount() << std::endl;
  std::streamsize k = std::cin.readsome(buf, 3);
  std::cout << k << std::endl;
  return 0;
}
