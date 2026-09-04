; a hand-written LLVM IR module: main() returns 42, after printing a line.

@.msg = private unnamed_addr constant [22 x i8] c"cicili-lang reaches C\00"

declare i32 @puts(i8*)

define i32 @main() {
entry:
  %p = getelementptr inbounds [22 x i8], [22 x i8]* @.msg, i64 0, i64 0
  %r = call i32 @puts(i8* %p)
  ret i32 42
}
