#include <set>
#include <string>
#include <cstdio>
int main() {
  std::set<std::string> s;
  s.insert("pear");
  s.insert("apple");
  s.insert("fig");
  s.insert("apple");
  printf("%zu %zu %zu\n", s.size(), s.count("fig"), s.count("kiwi"));
  for (const auto &x : s) printf("%s ", x.c_str());
  printf("\n");
  auto it = s.find("pear");
  if (it != s.end()) printf("%s %zu\n", it->c_str(), it->size());
  s.erase("apple");
  for (const std::string &x : s) printf("%s ", x.c_str());
  printf("\n%d\n", (int) s.empty());
  return 0;
}
