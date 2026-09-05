#include <stdlib.h>
typedef struct node { int v; } node;
typedef struct list { own node *head; node *cur <*> head; } list;
int main(void) { list l; l.head = malloc(sizeof(node)); l.cur = l.head; free(l.head); return l.cur->v; }
