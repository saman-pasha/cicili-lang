#include <stdio.h>
typedef struct point { int x; double y; } point_t;
struct node { struct node *next; point_t at; const char *name; };
enum color { RED, GREEN = 5, BLUE };
point_t origin = { 1, 2.5 };
point_t shift(point_t p, int dx) { p.x += dx; p.y *= 2; return p; }
int sum_x(struct node *n) { int s = 0; while (n) { s += n->at.x; n = n->next; } return s; }
int main(void) {
    point_t a = origin, b = shift(a, 10);
    struct node n2 = { 0, { 4, 0.5 }, "two" }, n1 = { &n2, b, "one" };
    point_t *pp = &a;
    pp->x = 3;
    point_t arr[2] = { { 7, 7.5 }, { 8, 8.5 } };
    point_t lit = (point_t){ 9, 9.5 };
    enum color c = BLUE;
    printf("%d %g %d %g %d %s %d\n", a.x, b.y, sum_x(&n1), arr[1].y, lit.x, n1.next->name, c);
    printf("%lu %lu\n", sizeof(point_t), sizeof(struct node));
    return a.x + b.x + (c == BLUE);
}
