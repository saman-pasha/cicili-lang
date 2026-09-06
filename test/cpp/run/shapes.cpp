/* virtual (M6, the third step): a table of function pointers per class, its
   pointer the first member; a call through a pointer or a reference goes by
   the object's own table, a call on a value straight; a virtual destructor
   runs the right one at delete, and the base's after it */
#include <stdio.h>
struct Shape {
    double w, h;
    static int alive;
    Shape(double w0, double h0) : w(w0), h(h0) { alive++; }
    virtual double area() const { return w * h; }
    virtual const char *name() const { return "shape"; }
    void scale(double by) { w = w * by; h = h * by; }
    virtual ~Shape() { alive--; }
};
struct Square : public Shape {
    int sides;
    Square(double side) : Shape(side, side), sides(4) { }
    double area() const override { return w * w; }
    const char *name() const override { return "square"; }
    ~Square() { sides = 0; }
};
struct Circle : public Shape {
    Circle(double r) : Shape(r, r) { }
    double area() const override { return 3 * w * h; }
};
int Shape::alive = 0;
double total(Shape *a, Shape *b) { return a->area() + b->area(); }
int main() {
    Shape s(2, 3);
    Square q(4);
    Shape *p = new Circle(2);
    Shape *r = &q;
    printf("%.1f %.1f %.1f %s %s %d\n", s.area(), r->area(), p->area(), r->name(), p->name(), Shape::alive);
    r->scale(2);
    printf("%.1f %.1f %d\n", total(&s, r), q.area(), q.sides);
    delete p;
    printf("%d\n", Shape::alive);
    return 0;
}
