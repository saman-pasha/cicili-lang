#include <stdio.h>
static int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }
int twice(int (*f)(int), int x) { return f(f(x)); }
int inc(int x) { return x + 1; }
void greet(const char *who, int times) { for (int i = 0; i < times; i++) printf("hi %s\n", who); }
double avg(int n, int *xs) { double s = 0; for (int i = 0; i < n; i++) s += xs[i]; return s / n; }
int counter = 0;
void bump(void) { counter++; }
int main(int argc, char **argv) {
    int xs[] = { 1, 2, 3, 4 };
    greet("you", 2);
    bump(); bump();
    printf("%d %d %g %d %d\n", fact(5), twice(inc, 40), avg(4, xs), counter, argc);
    return fact(4) + twice(inc, 0);
}
