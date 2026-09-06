/* std::string (M6, the eighth step): the compiler's own <string>, an own
   buffer grown by doubling; built from a literal, appended a char, a C
   string and a string -- the operator chosen by the argument's type --
   indexed by reference, compared, handed by reference and by pointer */
#include <stdio.h>
#include <string>
static int vowels(const std::string &s) { int k = 0; for (int i = 0; i < s.size(); i++) { char c = s[i]; k += c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'; } return k; }
static void shout(std::string *s) { *s += "!"; }
int main() {
    std::string s = "hello";
    std::string w("world");
    s += ' ';
    s += w;
    s += ", again";
    shout(&s);
    s[0] = 'H';
    std::string e;
    printf("%s %d %d %d %d %d %d\n", s.c_str(), s.size(), vowels(s), (int) e.empty(), (int) (w == "world"), (int) (w == s), (int) (s != "x"));
    return 0;
}
