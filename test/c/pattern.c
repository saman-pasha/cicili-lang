typedef struct point { int x; double y; } point_t;
struct node { struct node *next; point_t at; const char *name; };
point_t make(void);
int f(point_t p, struct node *n) {
    { a, b } := p;
    { _, at: { x, y }, name: nm } := n;
    { u, v } := make();
    return a + x + u;
}
