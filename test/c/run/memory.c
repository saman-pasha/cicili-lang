#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int table[5] = { 10, 20, 30 };
const char *names[] = { "zero", "one", "two" };
int main(void) {
    char buf[16] = "hello";
    char *heap = malloc(32);
    strcpy(heap, buf); strcat(heap, ", heap");
    int *p = table + 1;
    p[1] = 33; *p += 1;
    int local[4] = { [1] = 5, [3] = 7 };
    printf("%s %s %d %d %d %d\n", heap, names[2], table[1], table[2], local[1], local[3]);
    printf("%lu %lu %lu %d %ld\n", sizeof(int), sizeof buf, sizeof(table) / sizeof(table[0]), (int) strlen(heap), (long)(p - table));
    char *q = buf; while (*q) q++;
    printf("%ld %c %d\n", (long)(q - buf), buf[1], q == buf + 5);
    free(heap);
    return (int) strlen(buf);
}
