# cicili-lang

**A Safe Modern C compiler to LLVM, written on cocolog.**

cicili-lang is a new implementation of [Cicili](https://github.com/saman-pasha/cicili)'s
philosophy -- Safe Modern C: memory-safe, ownership checked at compile
time, zero runtime overhead, no garbage collector -- as a compiler that
reads C, checks it, and lowers it straight to **LLVM IR**. It is not a
transpiler: no C is emitted. The compiler's own work -- read, type, check,
lower -- is cocolog clauses, and LLVM turns the IR into a native binary.

It uses [Cicili](https://github.com/saman-pasha/cicili),
[ZiguratIP](https://github.com/saman-pasha/ziguratip) and
[cocolog](https://github.com/saman-pasha/cocolog), and **modifies none of
them**. `DESIGN.md` is the architecture and the milestones; this file is
what runs today.

## What runs today

* **M0 -- the LLVM path.** `proof/run.sh`: a hand-written LLVM IR module,
  compiled by the system `clang` (which consumes textual IR and drives the
  LLVM backend, no LLVM install) to a native binary that exits 42. GREEN.
* **M3 -- the safe part.** `own` pointers are linear, `move` hands them
  on, a borrow dangles when its owner is consumed and may not escape, and
  use after move, the double free, a leak on any path, a move inside a
  loop, a dangling borrow are compile errors naming the statement's line.
  GREEN: the owners programs run, fourteen programs are refused each with
  its error.
* **M2 -- the lowering.** `cicili_ir/2`, `cicili_compile/3`, `cicili_link/3`:
  C11's core -- every type but bitfields and unions, every statement and
  operator, calls and variadic calls, structs by value and by pointer,
  `defer` -- lowered to LLVM IR and run. `test/compile.sh`: eleven programs
  built, run and checked, GREEN.
* **M1 -- the reader.** `cicili_ast(+File, -AST)` reads a C file whole into an
  AST, through a DCG; each `#include` is found on the toolchain's path and
  read too; the knowledge base remembers every file by its modification
  time; a `.pl` included is a set of macros over ASTs with type inference.
  80 checks GREEN, including five real C files from the neighbours read
  entirely with their system headers.

## The `cicili` command

`bin/cicili` takes clang's arguments, so nothing about it is new:

```sh
cicili prog.c -o prog              # read, check, lower, compile, link
cicili -c prog.c                   # prog.o        cicili -S prog.c   # prog.s
cicili -emit-llvm -c prog.c        # prog.ll       cicili -fsyntax-only prog.c
cicili -O2 a.c b.c util.o -lm -o app
cicili -shared -O1 lib.c -o lib.dylib
cicili -I include prog.c           cicili -ast-dump prog.c           cicili --version
```

`--version` prints the version, which every commit raises, with the
versions of the cocolog it runs on and of the back end. A diagnostic is `file:line: error: what`, the exit status 1 when there is
one. The knowledge base is `~/.cicili/KB`, the user's (or `$CICILI_KB`;
`--no-kb` keeps everything in memory): the first call is the initialization
phase, reading the C standard library, the OS's and POSIX's headers
**once**; every later call, in any project, the tests included, is served
from it as static data, until the SDK or the reader's grammar changes. A
grammar change starts a new store (`KB.version` beside it names the
reader's version): every row of the old one is dead, and the store keeps
what is retracted. `test/driver.sh` is its gate.

## The compiler, in four predicates

```prolog
?- use_module(library(cicili)).
?- cicili_ast('prog.c', AST),                     % the file, read whole, headers and all
   cicili_ir([AST], IR),                          % the units lowered to one LLVM IR module (text)
   cicili_compile(IR, 'prog.o', ['-O1']),          % the object file, through LLVM
   cicili_link(['prog.o'], [], 'prog').           % the binary (or a library: ['-shared'])
```

`cicili_ir` rebuilds the symbol table from the units the way the parser
builds it and lowers with the same inference the macros use: allocas in the
entry block, C's usual conversions, `defer` as the static cleanup chain,
structs laid out as LLVM named types, calls through the prototypes the
headers gave. `cicili_compile` parses, verifies, optimizes and emits through
the embedded LLVM, `library(ccl_llvm)`, a cocolog module over `llvm-c` built
by `module/build-llvm.sh` from Homebrew's LLVM; where that module is not
built it goes through `clang -c -x ir`, the same backend by another door.
`cicili_link` drives the system linker. Errors: `not_lowered(What)` with the function,
`compile_failed(Message)`, `link_failed(Message)`. `test/compile.sh` builds
and runs the programs under `test/c/run/` and checks what they print and
return.

## The embedded LLVM: `library(ccl_llvm)`

A cocolog module written in Cicili over LLVM's C API: `ccl_llvm_version/1`,
`ccl_llvm_triple/1`, `ccl_llvm_check(+IR, -Report)` (`ok`, or what the
parser or the verifier said, with its line), and `ccl_llvm_compile(+IR,
+File, +Flags)`: the IR text parsed in a fresh context, verified, given the
host's target machine and data layout, run through `default<On>` for the
`-O` flag given (`-O1` if none; `-O0` runs nothing), and written as an
object file, or assembly with `-S`. LLVM is Homebrew's (`brew install
llvm`; Apple's toolchain ships no `llvm-c`):

```sh
LLVM=/usr/local/opt/llvm sh module/build-llvm.sh     # -> library/ccl_llvm.so
```

## The reader: `cicili_ast/2`, like `phrase/2`

```prolog
?- use_module(library(cicili)).
?- cicili_ast('test/c/hello.c', AST).
```

reads the whole file -- two DCGs, one over character codes into tokens
that carry their line, one over tokens into terms -- and answers the AST,
or throws a syntax error naming the line the unread item begins on and the
line the grammar gave up at. `cicili_ast(+File, -AST, -Rest)` is the `phrase/3`
form: the AST of what parsed and the tokens that remain.

For this file:

```c
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    printf("hello, %s\n", "cicili-lang");
    return 0;
}
```

the AST is (strings shown as text; they are code lists; every statement
carries its line first):

```prolog
unit([ include(2, system('stdio.h'),  file('/…/MacOSX.sdk/usr/include/stdio.h',  raw, unit([ … ]))),
       include(3, system('stdlib.h'), file('/…/MacOSX.sdk/usr/include/stdlib.h', raw, unit([ … ]))),
       function(5, none, base([], [int]), main, [], false,
                block([ expr(6, call(id(printf), [str("hello, %s\n"), str("cicili-lang")])),
                        return(7, int(0)) ])) ])
```

where each `unit([ … ])` is the header's own AST, its nested includes inside
it the same way.

A function-pointer parameter comes out inside out, the way C means it --
`int (*f)(int)` is `param(ptr([], fn(base([], [int]), [param(base([], [int]), anon)], false)), f)`
-- and a C99 compound literal from Cicili's own emitted C, `(Parcel){ id, w }`,
is `compound_lit(base([], [typedef('Parcel')]), init([item([], id(id)), item([], id(w))]))`.
The full AST vocabulary is at the top of `library/ccl_syntax.pl`.

**An `#include` is found and read too.** Each one becomes
`include(Line, Spec, file(Path, How, Unit))`: the header is found on the
inclusion path -- the including file's directory for a quoted name, then
`ccl_include_dir/1` facts, `$CICILI_INCLUDE`, and the toolchain's own list,
asked of `clang -E -v` once -- and read with the same reader, recursively.
`How` is `raw` when the file as written reads whole (a local header, a
wrapper like this SDK's `stdio.h`); a system header full of conditionals is
run through `clang -E -dD` and the result read, `preprocessed`, its
`#define`s kept as directives. A header nowhere on the path is `missing`;
a header that includes itself through another is cut as `cyclic(Path)`.
The typedef names an included unit declares are known to the rest of the
including file, and `ccl_declares(+Unit, +Name, -Item)` finds a declaration
anywhere under a unit -- `printf` under `<stdio.h>`, `malloc` under
`<stdlib.h>`, as `fn(ptr([], void), [param(size_t, __size)], false)`.

**The knowledge base remembers every file read.** A file read whole is
kept in the store keyed by its modification time and the reader's version,
one clause per top-level item, so under `--embed` it is there for the next
process and is loaded from there instead of re-read while the file's time
is unchanged and every header under it is at its remembered time. The
store is the user's, `~/.cicili/KB`: the first call is the initialization
phase, when the system headers -- the C standard library, the OS's,
POSIX's -- are parsed once; every later run, in any project, is served from
it, the gates included; the reader's version is part of the key, so a
better grammar re-reads what an older one left partial -- into a new store,
since cocolog's store never reclaims a retracted row and a store grown fat
slows every predicate's first call in a process (`KB.version` beside the
store is the reader's version; `bin/cicili` and `test/config.sh` start
afresh when it differs).

Otherwise the preprocessor is not expanded: any other `#` line is kept
whole as `directive(Line, Text)`, and a typedef name from a header the
reader has not seen is recognised from the tokens around it (`name x;`,
`name *p;` where an expression cannot stand, `(name *)`, `(name){`). What
it reads is C11 plus the GNU and Apple forms system headers and Cicili's
emitted C carry (`__attribute__`, `__asm`, `typeof`, `({ ... })`, `_Nonnull`,
`(^block)`); the C++ forms are not read yet -- they come after the C part
of the compiler is finished, because the libraries are in C++ (`DESIGN.md`,
M5) -- and `cicili_ast/3` says where a file stopped.

## Macros: `#include "m.pl"`

A Prolog file is included the way a header is, and **every predicate it
defines is a macro function over ASTs**: a call `name(a, b)` in the C
source, with `name/3` among them, runs at parse time as
`name(ASTa, ASTb, Result)` and `Result` takes the call's place. In an
expression the result is an expression; as a statement it may be a
statement (`swap(a, b);` below becomes a block); at file scope it may be a
declaration; a list result is spliced in. An identifier argument arrives
as `id(Name)`, a number as `int(N)`. A predicate written as a DCG rule,
`name(R) --> …`, is a macro whose **arguments are the list it parses**, so
it is variadic: `sum(a, 2, 3)` below folds to `(a + 2) + 3`.

```prolog
square(X, bin('*', X, X)).
swap(A, B, block([ declaration(0, none, base([], [int]), [var(T, base([], [int]), A)]),
                   expr(assign('=', A, B)), expr(assign('=', B, id(T))) ])) :- ccl_gensym(tmp, T).
sum(R) --> [X], sum_rest(X, R).
sum_rest(A, R) --> [X], !, sum_rest(bin('+', A, X), R).
sum_rest(A, A) --> [].
typename(X, str(Codes)) :- ccl_type_of(X, T), term_to_atom(T, A), atom_codes(A, Codes).
```

**Inside a macro the parser's symbol table is open** (`library(ccl_infer)`):
the scope of declared names as it stands at the call, the typedef
definitions and the struct tags, filled as the file and its headers are
read. `ccl_type_of(+Expr, -Type)` infers an expression's type through the
usual arithmetic conversions, members, pointers, indexing and calls;
`ccl_resolve_type/2` unwraps typedefs, `ccl_declared/2`, `ccl_typedef_of/2`,
`ccl_tag/2`, `ccl_members_of/2` look things up, `ccl_size_of/2` is LP64
layout, `ccl_gensym/2` makes a fresh temporary, `ccl_here/2` says where the
parser is, `ccl_macro_error/1` stops the read with a message. In the gate,
`typename(n->at.x)` answers `base([],[int])` through a pointer, a typedef
and a member, and `size(p)` of a struct of an int and a double is 16.

The include node is `include(Line, local('m.pl'), macros(Path,
[macro(square, square, 2), macro(sum, sum, dcg) …]))`, and the macro file
is a dependency of the includer's cached read.

**An error in a macro names both places.** A macro that fails or throws
stops the read with `error(macro_failed(Name, Args) | macro_error(Name,
Args, Error), here(File, Line, in_macro(Pred, MacroFile)))`: where it was
called, and where it went wrong; the command prints the error at the call
site and a note with the macro, its file and its arguments, the Prolog
error said plainly (`the macro calls no_such_predicate/1, which does not
exist`). And every expansion is recorded in the unit, `'$expansions'([
expansion(Line, Name, Args) …])` as its last item, so when the ownership
check or the lowering refuses something a macro produced, the diagnostic
on that line carries `note: expanded from macro`:

```
safe/macro_double_free.c:3: error: use after move of 'p' in call(id(free),[id(p)]) (function main)
safe/macro_double_free.c:3: note: expanded from macro 'freeit' on id(p)
```

## `:=` declares by inference

`name := expr;` declares `name` with the type of `expr`, inferred by the
same `ccl_type_of/2` the macros use, over the scope as it stands; the AST
holds an ordinary `declaration/4` with the concrete type, so nothing after
the reader knows the difference. It stands in a block, at file scope, and
in a `for`. Arrays and functions decay to pointers, a top-level `const` is
dropped (the new variable is its own), and a right-hand side whose type is
unknown stops the read with `cannot_infer(Name, Expr)` and the line.

```c
n := 42;            // int
d := n + 1.5;       // double
q := &p;            // point_t *
y := q->y;          // double, through the pointer and the typedef
for (i := 0; i < n; i++) { ... }
```

**The left of `:=` may be a pattern**, a match over a struct or a pointer
to one: a name binds the member at its position, `_` skips one, `field:
name` binds the member called `field`, and a nested `{ … }` destructures a
member that is a struct itself. Each binding is a declaration by
inference; a right-hand side that is not a variable is evaluated once,
into a temporary.

```c
{ a, b } := p;                          // int a = p.x; double b = p.y;
{ _, at: { x, y }, name: nm } := n;     // int x = n->at.x; double y = n->at.y; const char *nm = n->name;
{ u, v } := make();                     // point_t tmp_1 = make(); int u = tmp_1.x; double v = tmp_1.y;
```

A pattern longer than the struct, or a field it has not, stops the read
with `no_member(What, Type)` and the place.

## `name { … }` declares a struct type

At file scope, an identifier followed by a brace is a struct type with
that name as its tag and its typedef, in one: `point { int x; double y; }`
is `typedef struct point { int x; double y; } point;`. The name is a type
inside its own members (`node { node *next; … }`) and from then on; the
AST holds the plain `typedef/2`.

## `defer(a, b) { … }`: scope-bound, like cleanup

A `defer` is a statement: its block runs at every exit of the enclosing
scope, on the way out, last registered first, over the named variables as
they then are, the way Cicili's `cleanup` attribute hands the variable to
its function. The list names what the block depends on, for the checker.
The reader keeps it as `defer(Line, [id(V) …], Body)`; the lowering (M2)
is a static cleanup chain in the IR, no runtime, so a `return` from inside
the loop below frees the buffer and closes the file, in that order.

```c
FILE *f = fopen(path, "r");
if (f == NULL) return -1;
defer(f) { fclose(f); }

buf := malloc(max);                 // void *, from <stdlib.h>'s prototype
if (buf == NULL) return -2;
defer(buf) { free(buf); }

while (fgets(buf, max, f) != NULL)
    if (++n > 1000) return n;       // free(buf), then fclose(f)
return n;
```

## The safe part: `own` and `move`

`own char *p = malloc(n);` declares an **owner**. An owner is linear: it is
consumed exactly once on every path, by `free(p)` or `fclose(p)`, by
`move(p)` into another owner or as an argument, by `return p`, or by
passing it to a function whose parameter is `own`; a `defer(p) { free(p); }`
consumes it at the scope's exit, on every path, as it is lowered. A consumed
owner may own again by assignment. `cicili_ir` checks this before lowering
anything, flow-sensitively, and refuses with `error(ownership(Kind, Name,
Form), where(Function, line(L)))`, the form named:

| refused as | when |
|---|---|
| `use_after_move` | a consumed owner is read, passed, or freed again (the double free) |
| `borrow_after_move` | a borrow -- a plain pointer that took its value from an owner -- is used after the owner was consumed |
| `borrow_escapes` | a borrow is returned from the function, whose owner is consumed by then |
| `owner_leaked` | an owner is live, on any path, at its scope's end or at a `return` |
| `move_in_loop` | an owner from outside a loop is consumed inside it and not re-owned |
| `move_of_non_owner` | `move(x)` of something not declared `own` |
| `owner_overwritten` | assignment to a live owner, which would leak what it held |
| `goto_with_owners` | a `goto` in a function that has owners, not followed yet |

A **borrow** is a plain pointer whose value came from an owner: `char *q =
p`, `q = p + 1`, `&p[i]`, `&p->x`, or another borrow. It is bound to the
owner: the moment the owner is consumed the borrow dangles and a use of it
is refused, and a borrow may not be returned; assigning it from something
else unbinds it. Every error names the statement's line.

`test/c/run/owners.c` does all of it and runs, `own_struct.c` with a struct
on the heap (an `own point *` parameter takes the struct over, a `const
point *` one only looks), `borrows.c` with borrows; the programs under
`test/c/safe/` are each refused with the error their `.expect` names.
Not tracked yet: owners inside structs, owners through function pointers,
borrows stored into structs or globals.

## `format`, `print`, `println`: global macros

They are there in every file, without an include, like `:=`. The format
string has Rust's holes: `{}` is the next argument, `{0}` the argument at
that index, `{name}` the variable of that name in scope; `{{` and `}}` are
braces. Each hole becomes the `printf` conversion for the inferred type of
its argument, and a struct is printed by its members, from the symbol
table, nested structs the same way:

```c
p := (point_t){ 1, 2.5 };
println("n = {} name = {name} p = {p}", n);
// printf("n = %d name = %s p = point_t { x: %d, y: %g }\n", n, name, p.x, p.y);
s := format("{} + {} = {}", 1, 2, 3);      // char *, asprintf'd in a statement expression
```

`print` is `printf`, `println` adds the newline, `format` is an expression
of type `char *`. A hole with no argument, or a name not in scope, stops
the read with `macro_error(no_argument(I) | cannot_format(Expr), here(File,
Line))`. They live in `library/ccl_format.pl`, a macro file like any other;
a predicate named `ccl_macro_X` there is the macro `X`, which is how
`format` can be a macro although `format/2` is a Prolog builtin.

## Also in `library(cicili)`: objects and modules

The module also carries an objects-and-modules layer over cocolog --
`:- object(Name).` ... `:- end_object.`, `new/3`, `Inst::Msg`, inheritance,
everything as clauses in the store so an instance outlives its process --
written before the compiler's direction was settled. It is gated
(`test/objects.sh`, GREEN) and taught (`tutorials/`); whether it becomes
the compiler's authoring layer or is set aside is decided after the design.

## What lives here

```
module/cicili.cicili     the module: registration, ccl_version/1, and the Prolog half
                         (cicili_ast/2,3 and the objects layer)
library/ccl_syntax.pl    the two grammars: the lexer and the parser, as DCGs; the symbol table
library/ccl_include.pl   #include: the inclusion path, headers read raw or preprocessed, .pl macro
                         files, the knowledge-base cache
library/ccl_infer.pl     what a macro can ask: type inference over the symbol table, sizes, lookups
library/ccl_format.pl    the global macros format, print, println
library/ccl_ir.pl        cicili_ir: the lowering, the AST to LLVM IR text
library/ccl_build.pl     cicili_compile and cicili_link
library/ccl_check.pl     the safe part: the ownership check cicili_ir runs first
library/ccl_driver.pl    what the cicili command does; bin/cicili reads the arguments
test/driver.sh           the command's gate
module/ccl_llvm.cicili   the embedded LLVM, a cocolog module over llvm-c (module/build-llvm.sh)
test/compile.pl, .sh     the compiler's gate: one process builds test/c/run/*.c and refuses
                         test/c/safe/*.c; the shell runs the binaries and compares
library/cicili.so        built output; never committed (library/*.pl is)
module/build.sh          CICILI=… COCOLOG=… sh module/build.sh
proof/                   M0: LLVM IR to a native binary, and the script that proves it
test/reader.pl           the reader's gate, a cocolog program: 71 checks in one process
test/reader.sh           runs it; test/c/ holds its fixtures
test/objects.sh          the objects layer's gate
tutorials/NN-*.pl        the objects layer's lessons, goal `main', last line `done'
DESIGN.md                the architecture, the four neighbours' roles, the milestones
```

Build and prove:

```sh
CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog sh module/build.sh
sh test/reader.sh
sh test/compile.sh
sh test/driver.sh
sh proof/run.sh
```

## Rules of the house

* **The three neighbours are used, never edited.** A change one of them
  needs is a request to its own repository, not a patch here.
* **Every predicate and function this library defines is `ccl_`-prefixed;
  only `cicili` itself keeps its name.** cocolog has one namespace.
* **No transpiler.** The compiler lowers to LLVM IR; C is read, never
  written.
* **Nothing is claimed before its GREEN line.** A rule is a check in
  `test/`, a milestone has a proof that runs.
