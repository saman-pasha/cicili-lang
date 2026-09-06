/* move semantics (M6, the ninth step), over the program's own Name and
   Bag<T> of bag.h: an element with a destructor is pushed by move --
   std::move is Cicili's move, which empties its source at run time so the
   source's destructor frees nothing -- and destroyed where it leaves the
   bag by an explicit destructor call; walked by reference, indexed, its
   elements' methods called through the index; overloads chosen by type */
#include <stdio.h>
#include "bag.h"
int main() {
    Bag<Name> v;
    Name a = "alpha";
    Name b("beta");
    v.push(std::move(a));
    v.push(std::move(b));
    v.push(Name("gamma"));
    int letters = 0;
    for (Name &s : v) letters += s.size();
    v[1] += "!";
    v[1] += '?';
    int last = v[2].size();
    v.pop();
    printf("%d %d %s %s %d %d\n", v.size(), letters, v[0].c_str(), v[1].c_str(), last, (int) (v[0] == "alpha"));
    return 0;
}
