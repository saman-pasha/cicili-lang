#include <stdio.h>
int main(void) {
    int i, sum = 0;
    for (i = 0; i < 10; i++) { if (i % 2) continue; if (i > 6) break; sum += i; }
    printf("for %d %d\n", i, sum);
    int n = 3; while (n > 0) { n--; sum++; } printf("while %d %d\n", n, sum);
    do { sum += 10; } while (sum < 40); printf("do %d\n", sum);
    for (int k = 0; k < 3; k++) sum += k;
    switch (sum % 5) {
        case 0: printf("zero\n"); break;
        case 1: printf("one\n");
        case 2: printf("one or two\n"); break;
        default: printf("other %d\n", sum % 5);
    }
    if (sum > 100) printf("big\n"); else if (sum > 40) printf("medium\n"); else printf("small\n");
    int j = 0;
again:
    j++;
    if (j < 3) goto again;
    printf("goto %d\n", j);
    return sum > 40 ? 1 : 0;
}
