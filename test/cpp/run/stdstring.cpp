// M6's thirty-first step: std::string from libc++, COMPILED FROM ITS OWN BODY. The short-string optimization is
// the thing it is built on -- `union __rep { __short __s; __long __l; }' with four constructors -- so what it asked
// for first was A UNION WITH CONSTRUCTORS: a class whose members share storage, which goes a class's whole road
// while its layout stays a union's. Beside it: a nested union named as a template argument, a class-scope
// enumerator (`enum { __min_cap = ... }'), a nested class reading its enclosing class's statics, a scoped alias
// (`std::string' is `basic_string<char>') re-entering the type hook, `= default' keeping a class
// default-constructible, a candidate that fits nothing losing to a constructor TEMPLATE, a default argument
// desugared where it is filled in, a `const' local standing as a template argument, and libc++'s own forward
// declaration of `char_traits<char>' losing to its definition.
#include <cstdio>
#include <string>

int main() {
  std::string s = "abc";                                              // short: the object's own bytes
  std::string t = "a rather long string that will not fit inside the object itself";   // long: a buffer, freed by the destructor
  printf("%d %s %c%c | %d %c%c %d\n",
         (int) s.size(), s.c_str(), s[0], s[2],
         (int) t.size(), t[0], t[t.size() - 1], (int) t.empty());
  return 0;
}
