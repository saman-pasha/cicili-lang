/* a B-tree (minimum degree 2: one to three keys, two to four children per
   node) as an ownership test case. Every node is owned by its parent through
   an own array of children, `own node *C[4]', and the root by the tree; walks
   and searches borrow; a search's result is tied to the tree it came from; a
   full node is split by moving its upper children into a new owner; freeing a
   node drains its children -- the lowering's generated ccl_drain_node -- so
   the tree goes with its root, every node freed exactly once. */
#include <stdio.h>
#include <stdlib.h>

typedef struct node node;
struct node {
    int n;                      /* keys held: 1..3 */
    int key[3];
    int leaf;
    own node *C[4];             /* the children: null or owned, drained with the node */
};
typedef struct tree { own node *root; } tree;

static own node *new_node(int leaf) {                 /* calloc: the children null from birth */
    own node *x = calloc(1, sizeof(node));
    x->leaf = leaf;
    return x;
}
/* y is full: its upper key and its upper children go to z, a fresh node */
static void move_upper(node *y, node *z) {
    z->n = 1; z->key[0] = y->key[2]; z->leaf = y->leaf;
    if (!y->leaf) { z->C[0] = move(y->C[2]); z->C[1] = move(y->C[3]); }
    y->n = 1;
}
/* the i-th child of x is full: split it, its middle key going up into x, z after it among the children */
static void split_child(node *x, int i) {
    node *y = x->C[i];                                 /* a borrow of x's children */
    int mid = y->key[1];
    own node *z = new_node(y->leaf);
    move_upper(y, z);
    for (int j = x->n; j > i; j--) x->C[j + 1] = move(x->C[j]);   /* the slots shift: each moved out, its old holder null */
    x->C[i + 1] = move(z);
    for (int j = x->n - 1; j >= i; j--) x->key[j + 1] = x->key[j];
    x->key[i] = mid;
    x->n++;
}
static void insert_nonfull(node *x, int k) {
    int i = x->n - 1;
    if (x->leaf) {
        while (i >= 0 && x->key[i] > k) { x->key[i + 1] = x->key[i]; i--; }
        x->key[i + 1] = k;
        x->n++;
        return;
    }
    while (i >= 0 && x->key[i] > k) i--;
    i++;
    if (x->C[i]->n == 3) {
        split_child(x, i);
        if (k > x->key[i]) i++;
    }
    insert_nonfull(x->C[i], k);
}
static void insert(tree *t, int k) {
    if (t->root->n == 3) {                             /* the root is full: a new root above it */
        own node *s = new_node(0);
        s->C[0] = move(t->root);
        t->root = move(s);
        split_child(t->root, 0);
    }
    insert_nonfull(t->root, k);
}
static node *search(node *x, int k) <*> x {           /* the node holding k, or null: a borrow of x */
    int i = 0;
    while (i < x->n && x->key[i] < k) i++;
    if (i < x->n && x->key[i] == k) return x;
    if (x->leaf) return (node *) 0;
    return search(x->C[i], k);
}
static int level(node *root, node *x <*> root) {      /* how deep x sits under root */
    int d = 0, k = x->key[0];
    node *c = root;
    while (c != x) {
        int i = 0;
        while (i < c->n && c->key[i] < k) i++;
        c = c->C[i];
        d++;
    }
    return d;
}
static void walk(node *x) {                            /* in order */
    for (int i = 0; i < x->n; i++) {
        if (!x->leaf) walk(x->C[i]);
        printf("%d ", x->key[i]);
    }
    if (!x->leaf) walk(x->C[x->n]);
}
static int height(node *x) { int h = 1; while (!x->leaf) { x = x->C[0]; h++; } return h; }
static void drop(own node *x) { free(x); }             /* the children go with it: the drain */

int main(void) {
    tree t;
    t.root = new_node(1);
    int keys[20] = { 50, 20, 70, 10, 30, 60, 80, 25, 35, 65, 90, 5, 15, 55, 75, 85, 95, 40, 45, 1 };
    for (int i = 0; i < 20; i++) insert(&t, keys[i]);
    walk(t.root);
    printf("\n");
    printf("height %d\n", height(t.root));
    node *f = search(t.root, 65);                      /* f borrows t.root */
    printf("65 %s, level %d\n", f ? "found" : "missing", f ? level(t.root, f) : -1);
    node *g = search(t.root, 42);
    printf("42 %s\n", g ? "found" : "missing");
    drop(move(t.root));                                /* f and g dangle from here, unused */
    return 0;
}
