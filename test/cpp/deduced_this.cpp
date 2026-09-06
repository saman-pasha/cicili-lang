/* C++23's deducing this with a deduced type: a member template, not done -- refused by name */
struct Node { int v; int get(this auto &&self) { return self.v; } };
int main() { Node n = { 3 }; return n.get(); }
