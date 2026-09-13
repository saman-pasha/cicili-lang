// M6's thirtieth step: a vector of THE PROGRAM'S OWN CLASS -- libc++'s container holding objects the safe part
// owns. What it needed past 0.61's vector of int: a TEMPORARY of a class with a destructor must be DESTROYED at
// the end of its full expression (`v.push_back(Name("a"))' left it alive for good, and a class over an own pointer
// leaked one buffer per call); a parameter's type must be read THROUGH AN ALIAS to see its value category, since
// libc++ writes `push_back(const_reference)' beside `push_back(value_type &&)' and the const lvalue overload won
// every temporary; and a STATEMENT EXPRESSION IS A PLACE, so a reference binds to the temporary itself rather than
// to a copy -- two holders of one owner, one of them freed under the other.
#include <cstdio>
#include <vector>
#include <stdlib.h>
#include <string.h>

class Name {                                        // a string of the program's own, over own memory
    own char *d;
    int n;
public:
    Name(const char *s) : d(nullptr), n(0) { n = (int) strlen(s); d = (own char *) malloc(n + 1); memcpy(d, s, n + 1); }
    Name(Name &&o) : d(move(o.d)), n(o.n) { o.d = nullptr; o.n = 0; }   // moved, never copied: a class with a destructor
    ~Name() { free(d); }
    const char *c_str() const { return d; }
    int size() const { return n; }
};

struct Tag {                                        // the constructions and destructions, counted
    int id;
    static int live;
    Tag(int i) : id(i) { live++; }
    Tag(const Tag &t) : id(t.id) { live++; }
    ~Tag() { live--; }
};
int Tag::live = 0;

int main() {
  std::vector<Name> v;
  v.push_back(Name("a"));                           // a temporary: the move overload, and destroyed here
  v.push_back(Name("bb"));
  v.push_back(Name("ccc"));
  v.push_back(Name("dddd"));
  v.push_back(Name("eeeee"));                       // five: the buffer grew three times, the objects relocated
  int total = 0;
  for (int i = 0; i < (int) v.size(); i++) total += v[i].size();
  printf("%d %d %s %s\n", (int) v.size(), total, v[0].c_str(), v[4].c_str());
  for (const Name &x : v) printf("[%s]", x.c_str());
  printf("\n");

  {
    std::vector<Tag> t;
    t.push_back(Tag(1));
    t.push_back(Tag(2));
    t.push_back(Tag(3));
    printf("%d %d %d %d live=%d\n", (int) t.size(), t[0].id, t[1].id, t[2].id, Tag::live);
  }
  printf("after live=%d\n", Tag::live);
  return 0;
}
