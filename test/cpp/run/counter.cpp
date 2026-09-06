/* classes (M6, the second step): data members, methods over this, constructors
   at the declaration, destructors as the scope's defers, a base as the first
   member, static members, operators, default arguments, new and delete */
#include <stdio.h>
struct Shape {
    double w, h;
    Shape(double w0, double h0) : w(w0), h(h0) { }
    double area() const { return this->w * this->h; }
    void scale(double by);
};
struct Square : public Shape {
    Square(double side) : Shape(side, side) { }
    double perimeter() const { return 4 * w; }
};
class Counter {
public:
    Counter() : n(0) { made++; }
    explicit Counter(int start) : n(start) { made++; }
    ~Counter();
    int get() const { return n; }
    void add(int k = 1) { n += k; }
    static int made;
    Counter &operator+=(int k) { n += k; return *this; }
    int operator[](int i) const { return n + i; }
private:
    int n;
    int limit = 100;
};
int Counter::made = 0;
Counter::~Counter() { made--; }
void Shape::scale(double by) { w = w * by; h = h * by; }
Counter operator+(const Counter &a, const Counter &b) { return Counter(a.get() + b.get()); }
int main() {
    Shape s(2, 3);
    Square q{4};
    q.scale(2);
    Shape *p = new Square(5);
    int made_inside;
    {
        Counter c;
        c.add();
        c.add(2);
        c += 3;
        Counter d(10);
        Counter e = c + d;
        made_inside = Counter::made;
        printf("%d %d %d %d\n", c.get(), d[5], e.get(), made_inside);
    }
    printf("%.1f %.1f %.1f %.1f %d\n", s.area(), q.area(), q.perimeter(), p->area(), Counter::made);
    delete p;
    return 0;
}
