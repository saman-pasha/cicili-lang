/* the tie operator <*>: x <*> y, x lives within y -- on a local, a struct
   member, a parameter, a function's result, and after := */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct node { int v; } node;
typedef struct list { own node *head; node *cur <*> head; int n; } list;   /* cur borrows head, in every list */
typedef struct view { const char *s; int n; } view;

static node *find(node *head, int n, int k) <*> head {      /* the result borrows head */
    node *p = head;
    for (int i = 0; i < n; i++, p++) if (p->v == k) return p;
    return (node *) 0;
}
static int gap(node *head, node *cur <*> head) { return (int) (cur - head); }   /* cur within head, checked at every call */
static void show(view v) { printf("%.*s\n", v.n, v.s); }

int main(void) {
    own char *buf = malloc(16);
    strcpy(buf, "hello, tie");
    view v <*> buf = { buf + 7, 3 };            /* v, and what it holds, lives within buf */
    show(v);
    int a = 5;
    double b <*> a = 2.5;                       /* b lives within a */
    printf("%d %g\n", a, b);

    list l;
    l.head = malloc(4 * sizeof(node));
    for (int i = 0; i < 4; i++) l.head[i].v = i * 10;
    l.n = 4;
    l.cur = l.head + 2;                         /* a borrow of the tie, stored in the tied field */
    printf("cur %d\n", l.cur->v);
    node *f = find(l.head, l.n, 30);            /* f borrows l.head */
    printf("found %d at %d\n", f->v, gap(l.head, f));
    m := find(l.head, l.n, 99);
    printf("%s\n", m ? "found" : "none");
    free(l.head);                               /* l.cur, f and m dangle here, unused after */
    free(buf);                                  /* and v */
    return 0;
}
