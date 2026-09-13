#include <map>
#include <string>
#include <cstdio>
int main() {
  std::map<std::string, int> w;
  w["apple"] = 8;
  w["banana"] = 7;
  w["cherry"] = 1;
  printf("%zu %zu\n", w.count("banana"), w.count("durian"));
  auto it = w.find("cherry");
  if (it != w.end()) printf("%s %d\n", it->first.c_str(), it->second);
  w.erase("apple");
  for (auto &kv : w) printf("%s ", kv.first.c_str());
  printf("\n");
  return 0;
}
