/* a vector of strings (M6, the ninth step): an element that has a destructor
   is pushed by move -- std::move is Cicili's move, which empties its source
   at run time so the source's destructor frees nothing -- and destroyed
   where it leaves the vector; walked by reference, indexed, its elements'
   methods called through the index */
#include <stdio.h>
#include <string>
#include <vector>
int main() {
    std::vector<std::string> v;
    std::string a = "alpha";
    std::string b("beta");
    v.push_back(std::move(a));
    v.push_back(std::move(b));
    v.push_back(std::string("gamma"));
    int letters = 0;
    for (std::string &s : v) letters += s.size();
    v[1] += "!";
    int last = v[2].size();
    v.pop_back();
    printf("%d %d %s %s %d %d\n", v.size(), letters, v[0].c_str(), v[1].c_str(), last, (int) (v[0] == "alpha"));
    return 0;
}
