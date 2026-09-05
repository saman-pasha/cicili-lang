typedef struct node { int v; } node;
static node *pick(node *h, node *g) <*> h { return g; }
int main(void) { node a = {1}, b = {2}; return pick(&a, &b)->v; }
