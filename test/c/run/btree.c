/* a B-tree (minimum degree 2: one to three keys, two to four children per
   node) as an ownership test case. Every node is owned by its parent -- the
   first child through `child', the siblings through `next' -- and the root by
   the tree; walks and searches borrow; a search's result is tied to the tree it
   came from; a full node is split by moving its upper half into a new owner;
   the tree is dropped node by node, every owner consumed exactly once. */
#include <stdio.h>
#include <stdlib.h>

typedef struct node node;
struct node {
    int n;                      /* keys held: 1..3 */
    int key[3];
    int leaf;
    own node *child;            /* the first child; null in a leaf */
    own node *next;             /* the next sibling; null in the last */
};
typedef struct tree { own node *root; } tree;

static node *child_at(node *x, int i) <*> x {         /* the i-th child, a borrow of x */
    node *c = x->child;
    while (i-- > 0) c = c->next;
    return c;
}
static own node *take_next(node *c) {                 /* c's next sibling, taken out of the list */
    own node *r = move(c->next);
    c->next = (node *) 0;
    return r;
}
/* y is full: its upper key and its upper children go to a new node z, which follows y among the siblings */
static void split(node *y) {
    own node *z = malloc(sizeof(node));
    z->n = 1; z->key[0] = y->key[2]; z->leaf = y->leaf;
    if (y->leaf) z->child = (node *) 0;
    else z->child = take_next(child_at(y, 1));        /* the third and fourth children */
    z->next = move(y->next);
    y->next = move(z);
    y->n = 1;
}
/* the i-th child of x is full: split it, the middle key going up into x */
static void split_child(node *x, int i) {
    node *c = child_at(x, i);
    int mid = c->key[1];
    split(c);
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
    node *c = child_at(x, i);
    if (c->n == 3) {
        split_child(x, i);
        if (k > x->key[i]) i++;
        c = child_at(x, i);
    }
    insert_nonfull(c, k);
}
static void insert(tree *t, int k) {
    if (t->root->n == 3) {                             /* the root is full: a new root above it */
        own node *s = malloc(sizeof(node));
        s->n = 0; s->leaf = 0; s->next = (node *) 0;
        s->child = move(t->root);
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
    return search(child_at(x, i), k);
}
static int level(node *root, node *x <*> root) {      /* how deep x sits under root */
    int d = 0, k = x->key[0];
    node *c = root;
    while (c != x) {
        int i = 0;
        while (i < c->n && c->key[i] < k) i++;
        c = child_at(c, i);
        d++;
    }
    return d;
}
static void walk(node *x) {                            /* in order */
    for (int i = 0; i < x->n; i++) {
        if (!x->leaf) walk(child_at(x, i));
        printf("%d ", x->key[i]);
    }
    if (!x->leaf) walk(child_at(x, x->n));
}
static int height(node *x) { int h = 1; while (!x->leaf) { x = child_at(x, 0); h++; } return h; }
static void drop(own node *x) {                        /* every node consumed once: children, siblings, itself */
    if (!x) return;
    drop(move(x->child));
    drop(move(x->next));
    free(x);
}

int main(void) {
    tree t;
    t.root = malloc(sizeof(node));
    t.root->n = 0; t.root->leaf = 1; t.root->child = (node *) 0; t.root->next = (node *) 0;
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
