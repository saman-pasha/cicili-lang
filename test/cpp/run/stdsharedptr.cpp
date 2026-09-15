#include <cstdio>
#include <memory>
struct Tag {
    int n;
    static int live;
    Tag(int k) : n(k) { live++; }
    ~Tag() { live--; }
};
int Tag::live = 0;
int main() {
    std::shared_ptr<int> s = std::make_shared<int>(3);
    printf("%d %d\n", *s, (int) s.use_count());
    {
        std::shared_ptr<int> t = s;
        printf("%d %d\n", *t, (int) s.use_count());
    }
    printf("%d\n", (int) s.use_count());
    std::shared_ptr<Tag> a = std::make_shared<Tag>(8);
    printf("%d %d %d\n", a->n, Tag::live, (int) a.use_count());
    std::weak_ptr<Tag> w = a;
    printf("%d %d\n", (int) w.expired(), (int) w.use_count());
    {
        std::shared_ptr<Tag> b = w.lock();
        printf("%d %d\n", b->n, (int) a.use_count());
    }
    a.reset();
    printf("%d %d\n", Tag::live, (int) w.expired());
    std::shared_ptr<int> c(new int(12));
    printf("%d %d\n", *c, (int) (bool) c);
    return 0;
}
