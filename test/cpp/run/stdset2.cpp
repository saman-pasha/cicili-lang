#include <set>
#include <vector>
#include <functional>
#include <cstdio>
int main() {
  std::vector<int> v = {4, 1, 3, 1};
  std::set<int> s(v.begin(), v.end());
  printf("%zu\n", s.size());
  for (auto i = s.rbegin(); i != s.rend(); ++i) printf("%d ", *i);
  printf("\n");
  std::set<int> t = s;
  t.emplace(9);
  t.insert(t.end(), 12);
  printf("%d %d %zu\n", (int) (s == t), (int) (s != t), t.size());
  t.erase(t.find(3), t.end());
  for (int x : t) printf("%d ", x);
  printf("\n");
  s.swap(t);
  printf("%zu %zu\n", s.size(), t.size());
  std::set<int, std::greater<int>> g = {2, 8, 5};
  for (int x : g) printf("%d ", x);
  printf("\n%d %d\n", (int) g.key_comp()(3, 1), (int) (g.begin() == g.end()));
  std::multiset<int> ms = {1, 1, 2};
  ms.emplace(1);
  printf("%zu %d\n", ms.count(1), *ms.rbegin());
  return 0;
}
