#include <stdlib.h>
typedef struct node { int v; } node;
static int gap(node *head, node *cur <*> head) { return (int) (cur - head); }
int main(void) { own node *a = malloc(sizeof(node)); own node *b = malloc(sizeof(node)); int g = gap(a, b); free(a); free(b); return g; }
