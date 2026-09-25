#include <cstdio>
#include <functional>
struct Point { int m(); int v; };
int main() {
  typedef int (Point::*PM)();
  typedef int Point::*PV;
  printf("%d %d %d %d %d\n", (int) std::is_member_function_pointer<PM>::value, (int) std::is_base_of<Point, Point>::value,
         (int) std::is_member_pointer<PV>::value, (int) std::is_member_object_pointer<PV>::value, (int) std::is_member_function_pointer<PV>::value);
  return 0;
}
