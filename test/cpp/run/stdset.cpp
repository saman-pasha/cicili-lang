#include <set>
#include <vector>
#include <cstdio>
int main() {
  std::set<int> s;
  auto r = s.insert(3);
  printf("%d %d\n", *r.first, (int) r.second);
  r = s.insert(3);
  printf("%d %d\n", *r.first, (int) r.second);
  s.insert(1);
  s.insert({5, 2, 9});
  printf("%zu %zu %zu\n", s.size(), s.count(2), s.count(4));
  for (int x : s) printf("%d ", x);
  printf("\n");
  auto it = s.find(5);
  if (it != s.end()) printf("found %d\n", *it);
  s.erase(1);
  s.erase(s.find(9));
  printf("%d %d\n", *s.lower_bound(3), *s.upper_bound(3));
  for (auto i = s.begin(); i != s.end(); ++i) printf("%d ", *i);
  printf("\n%d\n", (int) s.empty());
  std::vector<int> v = {7, 4, 7};
  s.insert(v.begin(), v.end());
  printf("%zu %zu\n", s.size(), s.count(7));
  s.clear();
  printf("%zu %d\n", s.size(), (int) s.empty());
  std::multiset<int> ms;
  ms.insert(2);
  ms.insert(2);
  ms.insert(1);
  printf("%zu %zu\n", ms.size(), ms.count(2));
  auto er = ms.equal_range(2);
  for (auto i = er.first; i != er.second; ++i) printf("%d ", *i);
  printf("\n%zu\n", ms.erase(2));
  return 0;
}
