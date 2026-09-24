#include <cstdio>
#include <type_traits>
typedef const char *const ccp;
int main() {
  printf("%d %d %d %d %d\n", (int) __is_constructible(const char *, const char *const), (int) std::is_constructible<const char *, const char *const>::value,
         (int) std::is_constructible<const char *, ccp>::value, (int) __is_constructible(char *, const char *), (int) std::is_constructible<int, const int>::value);
  return 0;
}
