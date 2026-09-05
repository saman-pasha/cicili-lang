/* classes: access, fields, methods, constructors, destructors, inheritance, this, new, operators, defaults */
struct Shape {
    double w, h;
    Shape(double w0, double h0) : w(w0), h(h0) { }
    virtual double area() const { return this->w * this->h; }
    virtual void scale(double by);
    virtual ~Shape() { }
};
struct Square : public Shape {
    Square(double side) : Shape(side, side) { }
    double area() const override { return w * h; }
};
class Counter {
public:
    Counter() : n(0) { }
    explicit Counter(int start) : n(start) { }
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
    Shape *p = new Square(5);
    int *xs = new int[8];
    Counter c;
    c.add();
    c.add(2);
    double a = p->area() + s.area();
    delete p;
    delete[] xs;
    return (int) a + c.get();
}
