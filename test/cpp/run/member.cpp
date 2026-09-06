/* a member of class type (M6, the tenth step): a struct holding a Name is
   constructed with its holder -- an implicit constructor constructs the
   members, an initializer list constructs one with its arguments, an
   aggregate initializer constructs each from its item -- and destroyed with
   it, the members in reverse order; a bag of such structs holds and frees
   them; moved, never copied */
#include <stdio.h>
#include "bag.h"
struct Person {
    Name name;
    int age;
    int born(int year) const { return year - age; }
};
class Team {
    Name title;
    Bag<Person> members;
public:
    Team(const char *t) : title(t) { }
    void add(const char *n, int a) { Person p = { n, a }; members.push(std::move(p)); }
    int size() const { return members.size(); }
    const char *who(int i) { return members[i].name.c_str(); }
    int total() const { int s = 0; for (int i = 0; i < members.size(); i++) s += members[i].age; return s; }
    const char *name() const { return title.c_str(); }
};
int main() {
    Person p = { "ann", 30 };
    p.name += "e";
    Team t("crew");
    t.add("bob", 40);
    t.add("cy", 50);
    t.add(p.name.c_str(), p.age);
    printf("%s %d %s %d %s %s %d %d\n", p.name.c_str(), p.born(2026), t.name(), t.size(), t.who(0), t.who(2), t.total(), p.age);
    return 0;
}
