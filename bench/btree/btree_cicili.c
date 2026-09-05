/* the B-tree of test/c/run/btree.c at minimum degree 6 (up to 11 keys, 12
   children per node -- BTreeSet's), as a benchmark: N distinct keys inserted
   in a pseudo-random order, N searched (half present), the tree freed. Built
   by cicili -O3; every child is an own array element, the drains generated. */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef struct node node;
struct node {
    int n;                      /* keys held: 5..11 */
    int key[11];
    int leaf;
    own node *C[12];
};
typedef struct tree { own node *root; } tree;

static own node *new_node(int leaf) { own node *x = calloc(1, sizeof(node)); x->leaf = leaf; return x; }
static void move_upper(node *y, node *z) {            /* y full: keys 6..10 and children 6..11 go to z */
    z->n = 5; z->leaf = y->leaf;
    for (int j = 0; j < 5; j++) z->key[j] = y->key[j + 6];
    if (!y->leaf) for (int j = 0; j < 6; j++) z->C[j] = move(y->C[j + 6]);
    y->n = 5;
}
static void split_child(node *x, int i) {
    node *y = x->C[i];
    int mid = y->key[5];
    own node *z = new_node(y->leaf);
    move_upper(y, z);
    for (int j = x->n; j > i; j--) x->C[j + 1] = move(x->C[j]);
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
    if (x->C[i]->n == 11) {
        split_child(x, i);
        if (k > x->key[i]) i++;
    }
    insert_nonfull(x->C[i], k);
}
static void insert(tree *t, int k) {
    if (t->root->n == 11) {
        own node *s = new_node(0);
        s->C[0] = move(t->root);
        t->root = move(s);
        split_child(t->root, 0);
    }
    insert_nonfull(t->root, k);
}
static int contains(node *x, int k) {
    for (;;) {
        int i = 0;
        while (i < x->n && x->key[i] < k) i++;
        if (i < x->n && x->key[i] == k) return 1;
        if (x->leaf) return 0;
        x = x->C[i];
    }
}
static int key_of(int i) { return (int) ((unsigned) i * (unsigned) 2654435761); }
static long now_ms(void) { return (long) (clock() / 1000); }   /* CPU time; the run is one thread */

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 1000000;
    tree t;
    t.root = new_node(1);
    long t0 = now_ms();
    for (int i = 0; i < n; i++) insert(&t, key_of(i));
    long t1 = now_ms();
    int found = 0;
    for (int i = n / 2; i < n / 2 + n; i++) found += contains(t.root, key_of(i));
    long t2 = now_ms();
    free(t.root);                                      /* the drain: every node freed */
    long t3 = now_ms();
    printf("cicili -O3   insert %ld ms  search %ld ms  free %ld ms  found %d\n", t1 - t0, t2 - t1, t3 - t2, found);
    return 0;
}
