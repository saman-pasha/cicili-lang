// M6's thirty-third step: A CANDIDATE'S PARAMETER TYPE IS WRITTEN IN ITS OWN CLASS'S WORDS and must be read there.
// Overloads are scored at the CALL SITE, where the class context is the caller's or none at all, so a parameter
// naming a class-scope typedef -- `List<value_type>' below, `initializer_list<value_type>' on libc++'s
// `basic_string::operator+=' -- resolved to nothing and scored as if it were some other class. Here that picks the
// `List<char>' overload for a `List<int>' argument and LLVM refuses the call; in libc++ it made an instance keyed
// by the free name `value_type', whose own `typedef _Ep value_type' then became a typedef of itself. The rule a
// member template's signature has had since M6's twentieth step, now for the plain overloads too.
#include <cstdio>

template <class E> struct List { E v; };

template <class T> struct Box {
    typedef T value_type;
    int f(List<char> l) const { return 20 + (int) l.v; }        // declared FIRST, so a tie on score would take it
    int f(List<value_type> l) const { return 10 + (int) l.v; }  // written in Box's words: List<int> for Box<int>
};

int main() {
    Box<int> b;
    List<int> li;
    li.v = 5;
    List<char> lc;
    lc.v = 3;
    printf("%d %d\n", b.f(li), b.f(lc));
    return 0;
}
