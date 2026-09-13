#include <map>
#include <cstdio>
int main() {
  std::multimap<int, int> mm;
  mm.insert({1, 10});
  mm.insert({1, 11});
  mm.insert({2, 20});
  printf("%zu %zu\n", mm.size(), mm.count(1));
  auto r = mm.equal_range(1);
  for (auto i = r.first; i != r.second; ++i) printf("%d:%d ", i->first, i->second);
  printf("\n");
  return 0;
}
