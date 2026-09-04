point { int x; double y; }
node { node *next; point at; };
int f(void) { point p = { 1, 2.5 }; node n = { 0, p }; { a, b } := p; return a + n.at.x; }
