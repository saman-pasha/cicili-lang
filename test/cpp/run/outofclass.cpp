#include <stdio.h>

/* A class template's members DEFINED OUT OF THE CLASS -- how libc++ writes half of a
   container's members. The class's own member is a declaration; the body comes from the
   definition that follows, under the instance's own arguments. */

int alive = 0;

template <class T> struct Box {
    T v;
    Box();
    ~Box();
    void set(T x);
    T get() const;
    template <class U> U as() const;
};

template <class T> Box<T>::Box() : v() { alive = alive + 1; }
template <class T> Box<T>::~Box() { alive = alive - 1; }
template <class T> void Box<T>::set(T x) { v = x; }
template <class T> T Box<T>::get() const { return v; }
template <class T> template <class U> U Box<T>::as() const { return (U) v; }

int main() {
    int sum = 0;
    {
        Box<int> b;
        b.set(300);
        Box<double> d;
        d.set(2.5);
        sum = b.get() + (int) b.as<char>() + (int) d.get() + alive;
    }
    printf("%d %d\n", sum, alive);
    return 0;
}
