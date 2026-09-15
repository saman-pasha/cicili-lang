#include <cstdio>
#include <memory>
struct Tag {
    int n;
    static int live;
    Tag(int k) : n(k) { live++; }
    ~Tag() { live--; }
    int twice() const { return n * 2; }
};
int Tag::live = 0;
int main() {
    std::unique_ptr<int> p(new int(5));
    printf("%d %d\n", *p, (int) (bool) p);
    *p = 6;
    printf("%d %d\n", *p.get(), *p);
    p.reset();
    printf("%d\n", (int) (bool) p);
    auto q = std::make_unique<int>(7);
    printf("%d\n", *q);
    auto r = std::move(q);
    printf("%d %d %d\n", *r, (int) (bool) q, (int) (bool) r);
    {
        auto t = std::make_unique<Tag>(4);
        printf("%d %d %d\n", t->n, t->twice(), Tag::live);
    }
    printf("%d\n", Tag::live);
    std::unique_ptr<Tag> u(new Tag(9));
    Tag *raw = u.release();
    printf("%d %d %d\n", raw->n, (int) (bool) u, Tag::live);
    delete raw;
    printf("%d\n", Tag::live);
    std::unique_ptr<int> v;
    v = std::make_unique<int>(11);
    printf("%d\n", *v);
    return 0;
}
