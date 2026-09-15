#include <cstdio>
#include <string>
int main() {
    std::string a = "hello";
    std::string b = a + ", " + "world";
    printf("%s %d\n", b.c_str(), (int) b.size());
    printf("%s|%s\n", b.substr(7).c_str(), b.substr(0, 5).c_str());
    printf("%d %d %d\n", (int) b.find("world"), (int) b.find('o'), (int) (b.find("zzz") == std::string::npos));
    printf("%d\n", (int) b.rfind('o'));
    std::string c = a;
    c.append("!!");
    c.push_back('?');
    printf("%s %d\n", c.c_str(), (int) c.length());
    c.insert(0, ">> ");
    c.erase(0, 1);
    printf("%s\n", c.c_str());
    c.replace(0, 2, "<");
    printf("%s %c %c\n", c.c_str(), c.front(), c.back());
    printf("%d %d %d\n", (int) (a == "hello"), (int) (a < b), a.compare("hellp"));
    std::string d;
    for (char ch : a) d += ch;
    printf("%s %d %d\n", d.c_str(), (int) d.empty(), (int) a.at(1));
    d.clear();
    printf("%d %s\n", (int) d.empty(), std::to_string(42).c_str());
    return 0;
}
