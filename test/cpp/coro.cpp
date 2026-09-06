/* a coroutine: read, and refused by name -- the safe part has no runtime to suspend into */
struct Task { struct promise_type { }; };
Task count() { co_return; }
int main() { return 0; }
