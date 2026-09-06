/* a real program (M6): the B-tree of bench/btree written the C++ way -- a
   class over Cicili's own pointers, its constructor and destructor, const
   methods, the node helpers file-static -- under the ownership check: a
   node's children are an own array bounded by its last member, a merge moves
   them out and frees the node, the constructor must set every own field, the
   destructor may consume them, and delete on the tree destroys then frees */
#include <stdio.h>
#include <stdlib.h>
enum { T = 6, MINK = 5, MAXK = 11, MAXC = 12 };
struct node { int n; int key[MAXK]; int nc; own node *C[nc]; };
static own node *new_leaf() { return (own node *) calloc(1, sizeof(node)); }
static own node *new_inner() { own node *x = (own node *) calloc(1, sizeof(node) + MAXC * sizeof(node *)); x->nc = MAXC; return x; }
static int scan(node *x, int k) { int i = 0; for (int j = 0; j < x->n; j++) i += x->key[j] < k; return i; }
static int find(node *x, int k) { int i = 0; while (i < x->n && x->key[i] < k) i++; return i; }
static void move_upper(node *y, node *z) {
    z->n = MINK;
    for (int j = 0; j < MINK; j++) z->key[j] = y->key[j + T];
    if (y->nc) for (int j = 0; j < T; j++) z->C[j] = move(y->C[j + T]);
    y->n = MINK;
}
static void split_child(node *x, int i) {
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
static int pred_key(node *y) { while (y->nc) y = y->C[y->n]; return y->key[y->n - 1]; }
static void merge(node *x, int i) {
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
    free(z);
}
static void rotate_from_left(node *x, int i, node *left, node *c) {
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
static void rotate_from_right(node *x, int i, node *c, node *right) {
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
static void fix(node *x, int i) {
    if (i > 0 && x->C[i - 1]->n > MINK) rotate_from_left(x, i, x->C[i - 1], x->C[i]);
    else if (i < x->n && x->C[i + 1]->n > MINK) rotate_from_right(x, i, x->C[i], x->C[i + 1]);
    else if (i < x->n) merge(x, i);
    else merge(x, i - 1);
}
static int del(node *x, int k) {
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
class BTree {
    own node *root;
public:
    BTree() { root = new_leaf(); }
    ~BTree() { free(root); }
    void insert(int k) {
        if (root->n == MAXK) {
            own node *s = new_inner();
            s->C[0] = move(root);
            root = move(s);
            split_child(root, 0);
        }
        insert_nonfull(root, k);
    }
    bool contains(int k) const {
        node *x = root;
        for (;;) {
            int i = find(x, k);
            if (i < x->n && x->key[i] == k) return true;
            if (!x->nc) return false;
            x = x->C[i];
        }
    }
    void remove(int k) {
        del(root, k);
        if (root->n == 0 && root->nc) {
            own node *old = move(root);
            root = move(old->C[0]);
            free(old);
        }
    }
    int end() const { return root->n + root->nc; }
};
static int key_of(int i) { return (int) ((unsigned) i * (unsigned) 2654435761); }
int main() {
    int n = 20000;
    own BTree *t = new BTree();
    for (int i = 0; i < n; i++) t->insert(key_of(i));
    int found = 0;
    for (int i = n / 2; i < n / 2 + n; i++) found += t->contains(key_of(i));
    for (int i = 0; i < n; i += 2) t->remove(key_of(i));
    int left = 0;
    for (int i = 0; i < n; i++) left += t->contains(key_of(i));
    for (int i = 1; i < n; i += 2) t->remove(key_of(i));
    printf("found %d left %d end %d\n", found, left, t->end());
    delete t;
    return 0;
}
