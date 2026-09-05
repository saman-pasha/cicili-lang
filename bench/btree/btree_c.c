/* the same tree in plain C, for clang -O3: the B-tree of test/c/run/btree_del.c at minimum degree 6 (up to 11 keys,
   12 children per node -- BTreeSet's), as a benchmark: N distinct keys
   inserted in a pseudo-random order, N searched (half present), half of them
   deleted, N searched again, the rest deleted. Built by clang -O3, the free written by hand. A node's
   children are an own array bounded by its `nc', the last member: a leaf is
   allocated without it, 56 bytes, one cache line; an inner node has its slots
   in place. Every child is an own array element: a merge moves them out of
   the node that goes and frees it, the generated drain finding nothing left. */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum { T = 6, MINK = 5, MAXK = 11, MAXC = 12 };             /* the minimum degree: MINK..MAXK keys, up to MAXC children */
typedef struct node node;
struct node { int n; int key[MAXK]; int nc; node *C[]; };   /* nc: 0 in a leaf, MAXC in an inner node */
typedef struct tree { node *root; } tree;

static node *new_leaf(void) { return calloc(1, sizeof(node)); }
static node *new_inner(void) { node *x = calloc(1, sizeof(node) + MAXC * sizeof(node *)); x->nc = MAXC; return x; }
static int scan(node *x, int k) { int i = 0; for (int j = 0; j < x->n; j++) i += x->key[j] < k; return i; }   /* branchless */
static int find(node *x, int k) { int i = 0; while (i < x->n && x->key[i] < k) i++; return i; }             /* early exit */

/* ---- insertion: a full node met on the way down is split first ---- */
static void move_upper(node *y, node *z) {                  /* y is full: its upper keys and children go to z */
    z->n = MINK;
    for (int j = 0; j < MINK; j++) z->key[j] = y->key[j + T];
    if (y->nc) for (int j = 0; j < T; j++) z->C[j] = y->C[j + T];
    y->n = MINK;
}
static void split_child(node *x, int i) {                   /* x->C[i] is full: its middle key goes up into x, z after it */
    node *y = x->C[i];
    int mid = y->key[T - 1];
    node *z = y->nc ? new_inner() : new_leaf();
    move_upper(y, z);
    for (int j = x->n; j > i; j--) x->C[j + 1] = x->C[j];
    x->C[i + 1] = z;
    for (int j = x->n - 1; j >= i; j--) x->key[j + 1] = x->key[j];
    x->key[i] = mid;
    x->n++;
}
static void insert_nonfull(node *x, int k) {
    for (;;) {
        int i = scan(x, k);
        if (!x->nc) {
            for (int j = x->n; j > i; j--) x->key[j] = x->key[j - 1];
            x->key[i] = k;
            x->n++;
            return;
        }
        if (x->C[i]->n == MAXK) {
            split_child(x, i);
            if (k > x->key[i]) i++;
        }
        x = x->C[i];
    }
}
static void insert(tree *t, int k) {
    if (t->root->n == MAXK) {                               /* the root is full: a new root above it */
        node *s = new_inner();
        s->C[0] = t->root;
        t->root = s;
        split_child(t->root, 0);
    }
    insert_nonfull(t->root, k);
}
static int contains(node *x, int k) {
    for (;;) {
        int i = find(x, k);
        if (i < x->n && x->key[i] == k) return 1;
        if (!x->nc) return 0;
        x = x->C[i];
    }
}

/* ---- deletion: the key comes out of its leaf (an inner key first replaced by
   its predecessor, then that one out of its leaf), and only a node left with
   fewer than MINK keys is fixed on the way back up -- a key from a sibling
   with one to spare, else a merge with a sibling, which moves the sibling's
   keys and children over and frees it; the root shrinks to its only child ---- */
static int pred_key(node *y) { while (y->nc) y = y->C[y->n]; return y->key[y->n - 1]; }
static void merge(node *x, int i) {                         /* x->C[i] takes x->key[i] and everything of x->C[i+1], which goes */
    node *z = x->C[i + 1];
    node *y = x->C[i];
    int m = y->n;
    y->key[m] = x->key[i];
    for (int j = 0; j < z->n; j++) y->key[m + 1 + j] = z->key[j];
    if (y->nc) for (int j = 0; j <= z->n; j++) y->C[m + 1 + j] = z->C[j];
    y->n = m + 1 + z->n;
    for (int j = i; j < x->n - 1; j++) x->key[j] = x->key[j + 1];
    for (int j = i + 1; j < x->n; j++) x->C[j] = x->C[j + 1];
    x->n--;
    free(z);                                                /* its children moved out: nothing left to drain */
}
static void rotate_from_left(node *x, int i, node *left, node *c) {   /* c = x->C[i] gains a key from x, x one from left = x->C[i-1] */
    for (int j = c->n; j > 0; j--) c->key[j] = c->key[j - 1];
    c->key[0] = x->key[i - 1];
    if (c->nc) {
        for (int j = c->n + 1; j > 0; j--) c->C[j] = c->C[j - 1];
        c->C[0] = left->C[left->n];
    }
    c->n++;
    x->key[i - 1] = left->key[left->n - 1];
    left->n--;
}
static void rotate_from_right(node *x, int i, node *c, node *right) {  /* c = x->C[i] gains a key from x, x one from right = x->C[i+1] */
    c->key[c->n] = x->key[i];
    if (c->nc) {
        c->C[c->n + 1] = right->C[0];
        for (int j = 0; j < right->n; j++) right->C[j] = right->C[j + 1];
    }
    c->n++;
    x->key[i] = right->key[0];
    for (int j = 0; j < right->n - 1; j++) right->key[j] = right->key[j + 1];
    right->n--;
}
static void fix(node *x, int i) {                           /* x->C[i] is short of a key */
    if (i > 0 && x->C[i - 1]->n > MINK) rotate_from_left(x, i, x->C[i - 1], x->C[i]);
    else if (i < x->n && x->C[i + 1]->n > MINK) rotate_from_right(x, i, x->C[i], x->C[i + 1]);
    else if (i < x->n) merge(x, i);
    else merge(x, i - 1);
}
static int del(node *x, int k) {                            /* k out of x's subtree; whether x is short now */
    int i = scan(x, k);
    if (i < x->n && x->key[i] == k) {
        if (!x->nc) {
            for (int j = i; j < x->n - 1; j++) x->key[j] = x->key[j + 1];
            x->n--;
        } else {
            int p = pred_key(x->C[i]);
            x->key[i] = p;
            if (del(x->C[i], p)) fix(x, i);
        }
    } else if (x->nc) {
        if (del(x->C[i], k)) fix(x, i);
    }
    return x->n < MINK;
}
static void remove_key(tree *t, int k) {
    del(t->root, k);
    if (t->root->n == 0 && t->root->nc) {                   /* the root emptied: its only child is the root */
        node *old = t->root;
        t->root = old->C[0];
        free(old);
    }
}
static void drop(node *x) { if (x->nc) for (int i = 0; i <= x->n; i++) drop(x->C[i]); free(x); }
static int key_of(int i) { return (int) ((unsigned) i * (unsigned) 2654435761); }
static long now_ms(void) { return (long) (clock() / 1000); }   /* CPU time; the run is one thread */

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 1000000;
    tree t;
    t.root = new_leaf();
    long t0 = now_ms();
    for (int i = 0; i < n; i++) insert(&t, key_of(i));
    long t1 = now_ms();
    int found = 0;
    for (int i = n / 2; i < n / 2 + n; i++) found += contains(t.root, key_of(i));
    long t2 = now_ms();
    for (int i = 0; i < n; i += 2) remove_key(&t, key_of(i));       /* half of the keys */
    long t3 = now_ms();
    int left = 0;
    for (int i = 0; i < n; i++) left += contains(t.root, key_of(i));
    long t4 = now_ms();
    for (int i = 1; i < n; i += 2) remove_key(&t, key_of(i));       /* the rest */
    long t5 = now_ms();
    int end = t.root->n + t.root->nc;
    drop(t.root);
    printf("clang -O3    insert %ld  search %ld  del-half %ld  srch-half %ld  del-rest %ld ms  found %d left %d end %d\n", t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4, found, left, end);
    return 0;
}
