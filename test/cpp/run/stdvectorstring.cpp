// M6's thirty-eighth step: A VECTOR OF STRINGS -- libc++ holding libc++, each element owning a heap buffer of its
// own, constructed in the container's raw memory, relocated when it grows and destroyed with it. What it needed:
// a MEMBER INITIALIZER'S OVERLOAD CHOICE that reads the parameter in its own class's words (libc++'s union-class
// writes `__rep(__short __r)' with its holder's nested names, so the clash went unseen and
// `__rep_(std::move(__str.__rep_))' took `__rep(__short)' by arity -- a union into a byte); and A CONVERTING
// CONSTRUCTOR for a parameter that binds a TEMPORARY, a const lvalue reference or an rvalue one, TEMPLATE
// constructors included -- which is the whole of how `v.push_back("alpha")' makes a string out of a `const char *'.
#include <cstdio>
#include <string>
#include <vector>

int main() {
  std::vector<std::string> v;
  v.push_back("alpha");
  v.push_back("beta");
  v.push_back("a rather long string that will not fit inside the object itself");
  v.push_back("delta");                                   // four: the buffer grew twice, the strings relocated

  int total = 0;
  for (int i = 0; i < (int) v.size(); i++) total += (int) v[i].size();
  printf("%d %d %s %s %s\n", (int) v.size(), total, v[0].c_str(), v[1].c_str(), v[3].c_str());
  for (const std::string &s : v) printf("[%d]", (int) s.size());
  printf("\n");
  return 0;
}
