#include <cstdio>
#include <memory>
struct Node {
    int n;
    static int live;
    Node(int k) : n(k) { live++; }
    ~Node() { live--; }
};
int Node::live = 0;
struct Killer {
    static int calls;
    void operator()(own Node *p) const { calls++; delete p; }   // a deleter TAKES OWNERSHIP: `own' is how this language says so, and the safe part then demands the delete
};
int Killer::calls = 0;
struct Pair {
    std::unique_ptr<Node> head;
    int tag;
    Pair(int k, int t) : head(std::make_unique<Node>(k)), tag(t) {}
};
int main() {
    std::unique_ptr<int[]> a(new int[4]);
    for (int i = 0; i < 4; i++) a[i] = i * i;
    printf("%d %d %d\n", a[0], a[2], a[3]);
    auto b = std::make_unique<int[]>(3);
    b[0] = 7; b[2] = 9;
    printf("%d %d\n", b[0], b[2]);
    {
        std::unique_ptr<Node, Killer> k(new Node(5));
        printf("%d %d %d\n", k->n, Node::live, Killer::calls);
    }
    printf("%d %d\n", Node::live, Killer::calls);
    auto p = std::make_unique<int>(1);
    auto q = std::make_unique<int>(2);
    p.swap(q);
    printf("%d %d\n", *p, *q);
    std::swap(p, q);
    printf("%d %d\n", *p, *q);
    std::unique_ptr<int> z;
    printf("%d %d\n", (int) (z == nullptr), (int) (p != nullptr));
    int v = 42;
    printf("%d\n", *std::addressof(v));
    {
        Pair pr(6, 3);
        printf("%d %d %d\n", pr.head->n, pr.tag, Node::live);
    }
    printf("%d\n", Node::live);
    std::shared_ptr<Node> s = std::make_shared<Node>(2);
    std::shared_ptr<int> alias(s, &s->n);
    printf("%d %d %d\n", *alias, (int) s.use_count(), Node::live);
    std::weak_ptr<Node> w1(s);
    std::weak_ptr<Node> w2 = w1;
    printf("%d %d\n", (int) w2.expired(), (int) w2.use_count());
    s.reset();
    printf("%d %d %d\n", Node::live, (int) w1.expired(), (int) (alias != nullptr));
    return 0;
}
