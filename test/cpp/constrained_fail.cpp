// C++20: a constrained auto whose deduced type does not satisfy the concept is refused by the concept's name
template <class T> concept Small = sizeof(T) <= 4;
int main() {
    Small auto x = 1.5;
    return (int) x;
}
