#include <map>
#include <string>
#include <cstdio>
int main() {
  std::map<std::string, int> w;
  w["apple"] = 3;
  w["banana"] = 7;
  w["apple"] += 5;
  w["cherry"]++;
  for (const auto &[k, v] : w) printf("%s=%d ", k.c_str(), v);
  printf("\n%zu\n", w.size());
  return 0;
}
