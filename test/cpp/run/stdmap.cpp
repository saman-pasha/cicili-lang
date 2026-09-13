#include <map>
#include <cstdio>
int main() {
  std::map<int, int> m;
  m[3] = 30;
  m[1] = 10;
  m[2] = 20;
  printf("%zu %d %zu\n", m.size(), m[2], m.count(5));
  auto it = m.find(3);
  if (it != m.end()) printf("%d:%d\n", it->first, it->second);
  m.erase(1);
  for (auto &kv : m) printf("%d=%d ", kv.first, kv.second);
  printf("\n");
  m.insert({4, 40});
  m.insert(std::make_pair(5, 50));
  for (auto it2 = m.begin(); it2 != m.end(); ++it2) printf("%d ", it2->first);
  printf("\n%d %d %d\n", (int) m.empty(), m.at(4), m.lower_bound(3)->first);
  m.clear();
  printf("%zu\n", m.size());
  return 0;
}
