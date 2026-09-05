/* the B-tree of bench/btree at minimum degree 2 (one to three keys, two to
   four children per node), with deletion, as the ownership test case: every
   node owns its children through an own array bounded by its `nc'; a split
   moves the upper children into a new owner, a merge moves a sibling's
   children over and frees it, a rotation moves one child across, the root
   shrinks to its only child; freeing the root drains whatever is left. At
   this degree every rotation and merge fires on two dozen keys. */
#include <stdio.h>
#include <stdlib.h>

enum { T = 2, MINK = 1, MAXK = 3, MAXC = 4 };
typedef struct node node;
struct node { int n; int key[MAXK]; int nc; own node *C[nc]; };   /* nc: 0 in a leaf, MAXC in an inner node */
typedef struct tree { own node *root; } tree;

static own node *new_leaf(void) { return calloc(1, sizeof(node)); }
static own node *new_inner(void) { own node *x = calloc(1, sizeof(node) + MAXC * sizeof(node *)); x->nc = MAXC; return x; }
static int scan(node *x, int k) { int i = 0; for (int j = 0; j < x->n; j++) i += x->key[j] < k; return i; }   /* branchless */
static int find(node *x, int k) { int i = 0; while (i < x->n && x->key[i] < k) i++; return i; }             /* early exit */

/* ---- insertion: a full node met on the way down is split first ---- */
static void move_upper(node *y, node *z) {                  /* y is full: its upper keys and children go to z */
    z->n = MINK;
    for (int j = 0; j < MINK; j++) z->key[j] = y->key[j + T];
    if (y->nc) for (int j = 0; j < T; j++) z->C[j] = move(y->C[j + T]);
    y->n = MINK;
}
static void split_child(node *x, int i) {                   /* x->C[i] is full: its middle key goes up into x, z after it */
    node *y = x->C[i];
    int mid = y->key[T - 1];
    own node *z = y->nc ? new_inner() : new_leaf();
    move_upper(y, z);
    for (int j = x->n; j > i; j--) x->C[j + 1] = move(x->C[j]);
    x->C[i + 1] = move(z);
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
        own node *s = new_inner();
        s->C[0] = move(t->root);
        t->root = move(s);
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
    own node *z = move(x->C[i + 1]);
    node *y = x->C[i];
    int m = y->n;
    y->key[m] = x->key[i];
    for (int j = 0; j < z->n; j++) y->key[m + 1 + j] = z->key[j];
    if (y->nc) for (int j = 0; j <= z->n; j++) y->C[m + 1 + j] = move(z->C[j]);
    y->n = m + 1 + z->n;
    for (int j = i; j < x->n - 1; j++) x->key[j] = x->key[j + 1];
    for (int j = i + 1; j < x->n; j++) x->C[j] = move(x->C[j + 1]);
    x->n--;
    free(z);                                                /* its children moved out: nothing left to drain */
}
static void rotate_from_left(node *x, int i, node *left, node *c) {   /* c = x->C[i] gains a key from x, x one from left = x->C[i-1] */
    for (int j = c->n; j > 0; j--) c->key[j] = c->key[j - 1];
    c->key[0] = x->key[i - 1];
    if (c->nc) {
        for (int j = c->n + 1; j > 0; j--) c->C[j] = move(c->C[j - 1]);
        c->C[0] = move(left->C[left->n]);
    }
    c->n++;
    x->key[i - 1] = left->key[left->n - 1];
    left->n--;
}
static void rotate_from_right(node *x, int i, node *c, node *right) {  /* c = x->C[i] gains a key from x, x one from right = x->C[i+1] */
    c->key[c->n] = x->key[i];
    if (c->nc) {
        c->C[c->n + 1] = move(right->C[0]);
        for (int j = 0; j < right->n; j++) right->C[j] = move(right->C[j + 1]);
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
        own node *old = move(t->root);
        t->root = move(old->C[0]);
        free(old);
    }
}
static void walk(node *x) { for (int i = 0; i < x->n; i++) { if (x->nc) walk(x->C[i]); printf("%d ", x->key[i]); } if (x->nc) walk(x->C[x->n]); }
static int count(node *x) { int c = x->n; if (x->nc) for (int i = 0; i <= x->n; i++) c += count(x->C[i]); return c; }
static int height(node *x) { int h = 1; while (x->nc) { x = x->C[0]; h++; } return h; }

int main(void) {
    tree t;
    t.root = new_leaf();
    int keys[24] = { 12, 5, 19, 3, 8, 15, 22, 1, 4, 6, 9, 13, 17, 20, 24, 2, 7, 10, 11, 14, 16, 18, 21, 23 };
    for (int i = 0; i < 24; i++) insert(&t, keys[i]);
    printf("n %d h %d: ", count(t.root), height(t.root)); walk(t.root); printf("\n");
    int gone[6] = { 12, 1, 24, 8, 15, 19 };                 /* a root key, both ends, inner keys: predecessors, rotations, merges */
    for (int i = 0; i < 6; i++) {
        remove_key(&t, gone[i]);
        printf("-%d n %d h %d: ", gone[i], count(t.root), height(t.root)); walk(t.root); printf("\n");
    }
    for (int k = 1; k <= 24; k++) remove_key(&t, k);        /* all, the gone ones again: absent, unharmed */
    printf("empty %d %d\n", t.root->n, t.root->nc);
    free(t.root);
    return 0;
}
