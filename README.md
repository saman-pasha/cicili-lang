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
  on, a borrow dangles when its owner is consumed and may not escape, a
  struct's own fields are owners that go with it, a borrow or an owner
  stored where the check cannot follow it is refused, and use after move,
  the double free, a leak on any path, a move inside a loop, a dangling
  borrow are compile errors naming the statement's line; a plain pointer
  parameter is a borrow of the caller's, never stored, freed or moved.
  GREEN: the owners programs run, twenty-seven programs are refused each with
  its error.
* **M2 -- the lowering.** `cicili_ir/2`, `cicili_compile/3`, `cicili_link/3`:
  C11's core -- every type, bitfields, unions and static locals included,
  every statement and
  operator, calls and variadic calls, structs by pointer and by value --
  across a call as the platform ABI has it, the same pieces, `byval` and
  `sret` clang uses, proven against clang-built code both ways --
  `defer` -- lowered to LLVM IR and run. `test/compile.sh`: eighteen
  programs built, run and checked, GREEN.
* **M5 -- the preprocessor, in cocolog.** No clang, no LLVM binary
  anywhere (owner's rule): a header the raw reader cannot take goes
  through `library(ccl_pp)` -- directives, conditional groups, macro
  expansion with `#`, `##` and `__VA_ARGS__`, `#include_next`, the
  built-ins, the target's predefined macros as data -- and the inclusion
  path comes from the SDK's and LLVM's conventional places. `<stdio.h>`'s
  closure of 38 files in two seconds, the declarations the same as
  clang's; GREEN in every gate, `test/c/run/pp.c` the proof.
* **M4 -- the cache.** Every file read whole is in the user's store,
  `~/.cicili/KB`, keyed by its time and the reader's version, and so is
  the IR of every file built, keyed by everything it came from; a rebuild
  that touches one file checks and lowers that one and serves the rest.
  GREEN: `test/driver.sh` builds two files, touches one, sees one redone.
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
reader's and the lowering's versions): every row of the old one is dead,
and the store keeps what is retracted. The IR of every file built joins
the store beside its unit, under a signature of everything it came from
(the file, every header and macro file it reached, the lowering's version,
the host), so a rebuild that touches one file checks and lowers that one
and serves the others: `cicili -v` says `served main.c from the store`.
`test/driver.sh` is its gate.

## `cicili++`: the C++ reader (M5)

`bin/cicili++` is `cicili` for C++, as `clang++` is `clang` for C++: the
same arguments, every input read as C++, the link through `c++`. M5 is the
reader: a C++ file is read whole, `-ast-dump` shows it, `-fsyntax-only`
says nothing when it reads, and a C++ file that is C builds; the check and
the lowering of the C++ forms are M6, so a file using them is refused at
the first form the lowering does not have. What is read, each with its AST
node:

| C++ | AST |
|---|---|
| `namespace N { … }`, `inline namespace`, anonymous | `namespace(L, N, Items)` |
| `using namespace N;`, `using N::x;`, `using T = type;` | `using(L, namespace(Q))`, `using(L, name(Q))`, a `typedef` |
| `extern "C" { … }`, `extern "C" decl` | `extern_c(L, Items)` |
| `template <typename T, int N = 4> item` | `template(L, [tparam(type, T, none), tparam(int, N, int(4))], Item)` |
| `struct S : public B { … }`, `class C { public: … }` | `class(Kind, N, [base(Access, B)], Members)`; a struct of fields alone stays `struct(N, Ms)` |
| a method, a constructor with its initializers, a destructor | `method(L, Quals, Ret, Name, Ps, Var, Body)`, `ctor(L, Quals, Ps, [init(N, Args)], Body)`, `dtor(L, Quals, Body)`; Quals from virtual, static, explicit, const, override, final, noexcept; Body a block, `none`, `pure`, `default`, `delete` |
| `public:`, `int limit = 100;`, `friend`, `using` in a class | `access(A)`, `default_init(N, E)`, `friend(L)`, `using(L)` |
| `Shape::scale(…) { }`, `Counter::~Counter() { }`, `int Counter::made = 0;` | a `function` or `var` named `scoped([Shape], scale)`, `dtor_def(L, C, Quals, Body)`, `ctor_def(…)` |
| `operator+`, `operator[]`, `operator+=` | the name `operator('+')` |
| `T &x`, `T &&x`, `int f(int k = 1)` | `ref(Q, T)`, `rref(Q, T)`, `param(T, k, int(1))` |
| `A::b`, `::g`, `std::vector<int>`, `Buf<int, 4>`, `max2<int>(1, 2)`, `t.item<float>()` | `scoped([A], b)`, `scoped([global], g)`, `scoped([std], tmpl(vector, [int]))`, `tmpl('Buf', [int, int(4)])`, `call(tmpl(max2, [int]), …)`, `call(member(t, tmpl(item, [float])), [])` |
| `Shape s(2, 3)`, `Square q{4}`, `new T(args)`, `new T[n]`, `delete p`, `delete[] p` | `var(s, T, ctor(Args))`, `init(…)`, `new(T, Args)`, `new_array(T, N)`, `delete(E)`, `delete_array(E)` |
| `this`, `true`, `nullptr`, `static_cast<T>(e)`, `unsigned(k)` | `this`, `bool(true)`, `nullptr`, `ccast(static, T, E)`, `ccast(functional, T, E)` |
| `auto x = e;` | inferred as `:=` infers, else `var(x, base([], [auto]), E)` |
| `for (auto &x : xs) S` | `for_each(L, var(x, ref([], auto), none), Range, S)` |
| `try { } catch (Err e) { } catch (...) { }`, `throw e` | `try(L, Body, [catch(param(T, e), B), catch(any, B)])`, `throw(E)` |
| `[k, &t](int a) mutable -> int { }` | `lambda([cap(val, k), cap(ref, t)], Params, Ret, Body)` |
| `enum class Color : int { … }` | `enum_class('Color', Enumerators)` |

A C++ library header, `<cstdio>` and kin, is flattened by one run of the
preprocessor (`library(ccl_pp)`, the same one C's headers get; `_Pragma`
operators dropped as `clang -E` drops them) and read once, as far as it
reads, never raw: a `<sstream>` attempted raw, header by header, took ten
minutes. What it contributes is its
declarations, not its text, so it is **summarized to one file**,
`~/.cicili/cpp/<name>-<fold>.sum`: the functions and globals, typedefs,
tags with their members (bodies dropped), enumerators, template and type
names the reader found, keyed by the reader's version and the time of
every file the preprocessor pulled; the next run loads the summary in
place of preprocessing and reading forty thousand lines, a second build of
`hello.cpp` taking seconds where the first took thirty. cocolog's store is not
involved, since it cannot hold units that size (a finding in
`CLAUDE.md`), so `cicili++` runs `--no-kb`. `test/cpp.sh` is the gate:
`test/cpp.pl`'s 21 checks over `test/cpp/*.cpp`, the six C++ files of
Cicili's own test suite -- `objects.cpp`, `emit_report.cpp` with
`<sstream>`, `specialise.cpp`, `syntax.cpp` with `<vector>` and
`<stdexcept>`, `torch.cpp` and `torch-fragment.cpp` over a libtorch stub --
read whole, `hello.cpp` built and run, and built again from the
summaries: 30 seconds served, two minutes the first time.

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
by `module/build-llvm.sh` from Homebrew's LLVM -- the whole back end
(owner's rule: no clang and no LLVM binary is run, by the reader or the
build; where the module is not built the compile is the error
`no_embedded_llvm`). `cicili_link` drives the system linker through `cc`
(`c++` for cicili++), the one system tool left: `llvm-c` has no linker to
embed. Errors: `not_lowered(What)` with the function,
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

reads the whole file -- a lexer over character codes into tokens that
carry their line, a DCG over tokens into terms -- and answers the AST,
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
`ccl_include_dir/1` facts, `$CICILI_INCLUDE`, and the toolchain's
directories where the conventions put them, no tool run: the C++ library
(`$LLVM`'s or Homebrew's `include/c++/v1`, else the SDK's), this
compiler's own freestanding headers (`library/include`: `stddef.h`,
`stdarg.h`, `stdbool.h`, `float.h`, `iso646.h`, `stdalign.h`,
`stdnoreturn.h`), `/usr/local/include`, then the SDK (`$SDKROOT`, the
Command Line Tools', Xcode's) or `/usr/include` -- and read with the same
reader, recursively. `How` is `raw` when the file as written reads whole
(a local header, a wrapper like this SDK's `stdio.h`); a system header
full of conditionals goes through **the preprocessor, `library(ccl_pp)`,
written in cocolog** -- directives, conditional groups with their
constant expressions, `defined`, macro expansion with `#`, `##`,
`__VA_ARGS__` and hide sets, `#include` and `#include_next` on the same
path, `#pragma once`, `__has_include`, `__FILE__`/`__LINE__`/`__COUNTER__`,
the target's predefined macros as data (both architectures, and C++'s) --
and the result is read, `preprocessed`. It works line by line, lexing only
the lines of the groups taken and a macro's body on its first use, and
skips a guarded header on its second include; `<stdio.h>`'s closure of 38
files takes two seconds. `__has_feature`, `__has_attribute` and kin
answer 0 so a header takes its plainest path, `__has_builtin` 1 (libc++'s
other branch is an `#error`). A header nowhere on the path is `missing`;
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

**`#cocolog` ... `#end` writes the macro file in place.** The lines between
are cocolog, not C -- clauses, rules, DCG rules -- loaded and registered
exactly as `#include "m.pl"` would load them, so every predicate they
define is a macro from that line on; the block stays in the AST as
`cocolog(Line, Text)`, which the check and the lowering pass over.

```c
#cocolog
twice(X, bin('*', X, int(2))).
sum(R) --> [A], sum_rest(A, R).
sum_rest(A, R) --> [B], !, sum_rest(bin('+', A, B), R).
sum_rest(A, A) --> [].
#end
int main(void) { printf("%d %d\n", twice(21), sum(1, 2, 3, 4)); return 0; }   /* 42 10 */
```

A block that reaches the end of the file without `#end` ends there.
`test/c/run/cocolog.c` runs it, and `infer.c` shows the macros asking
`ccl_type_of/2` for their argument's type: `show(e)` picks printf's
conversion by it, `swap(a, b)` declares its temporary with it, `bytes(e)`
folds `ccl_size_of/2` of it to a literal.

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

`name := expr <*> y;` ties the new variable to `y` (the tie operator, in
the safe part below).

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
owner may own again by assignment; one declared without a value, or given a
null, holds nothing yet and may be given something. `cicili_ir` checks this
before lowering anything, flow-sensitively, and refuses with
`error(ownership(Kind, Name, Form), where(Function, line(L)))`, the form
named:

| refused as | when |
|---|---|
| `use_after_move` | a consumed owner is read, passed, or freed again (the double free) |
| `owner_unset` | an owner is read, passed, freed or moved before it was given anything |
| `borrow_after_move` | a borrow -- a plain pointer that took its value from an owner -- is used after the owner was consumed |
| `borrow_escapes` | a borrow is returned from the function, whose owner is consumed by then |
| `borrow_stored` | a borrow is stored where the check cannot follow it: a plain struct field, an element, a global, through a pointer, or into an own slot |
| `borrow_consumed` | a borrow is freed, or passed where an owner is taken: a parameter freed in its callee |
| `borrow_incomplete` | an own field of the struct a parameter points to was freed or moved out and not replaced by the return |
| `owner_stored` | an owner's pointer is stored into a plain slot, where its ownership would be lost |
| `owner_leaked` | an owner is live, on any path, at its scope's end or at a `return`; or a field, when its struct is freed |
| `move_in_loop` | an owner from outside a loop is consumed inside it and not re-owned |
| `move_of_non_owner` | `move(x)` of something not declared `own` |
| `owner_overwritten` | assignment to a live owner, which would leak what it held |
| `goto_with_owners` | a `goto` in a function that has owners, not followed yet |
| `tie_unknown` | `x <*> y` where no `y` is declared before it: in scope, an earlier parameter, an earlier member |
| `tie_outlived` | an owner tied to `y` is still live when `y` is consumed |
| `tie_escapes` | a tied owner moved beyond its tie: into an untied slot, to an untied own parameter, returned with no result tie |
| `tie_mismatch` | a value not within the tie of the slot, the parameter or the result it is given to |
| `unconsumed` | a plain pointer holding fresh memory, never consumed: at its scope's end, a `return`, or overwritten |
| `untied` | a slot the check cannot follow -- a global, a field, an element, `*p`, an initializer item, a struct by value -- given a value with no owner behind it |
| `own_unbounded` | an own pointer with no owner to name: behind a plain pointer (`own T **p`), in an array with no constant bound, as an array parameter |
| `own_array_by_value` | a struct with an own array held by value, or copied: its copy would own the elements twice |
| `own_array_untagged` | an own array in a struct without a tag, which names its drain |
| `array_unset` | an own array not zeroed at birth: a struct from `malloc` or `realloc`, a local without an initializer |

**A struct's own fields are owners too**, named by their path: `p->name`
under an own pointer, `c.name` in a struct held by value, `c.inner.name`
through a member held by value. They go with the struct: freeing it demands
its fields consumed first (else the field leaks), moving it -- to an own
parameter, into another owner, by `return` -- demands them complete, live or
null, and moves them along; a struct copied by value moves its fields into
the copy; `move(p->name)` takes a field out. An own pointer from `malloc`
has unset fields, to be given something before the struct is returned; one
from any other call is complete. What a plain pointer to a struct reaches is
C's, not tracked.

A **borrow** is a plain pointer whose value came from an owner: `char *q =
p`, `q = p + 1`, `&p[i]`, `&p->x`, `a->name`, or another borrow. It is
bound to the owner: the moment the owner is consumed the borrow dangles and
a use of it is refused, and a borrow may not be returned; assigning it from
something else unbinds it. A borrow, or an owner's pointer, may only be held
by a local plain pointer: stored into a plain field, an element, a global or
through a pointer it could not be followed, so that is refused; an own slot
receives an owner (moved in), a null, or a fresh value, never a borrow.
Every error names the statement's line.

**A plain pointer parameter is a borrow of the caller's.** Inside its
function it may be read, passed on and returned -- the caller still owns
what it points to -- but not stored, freed or moved: `own` is the one way
memory comes in, so a borrow handed to any function is safe. What it
reaches, a member, an element, what it points to, is borrowed from the
same. An own field of the struct it points to may be freed and replaced
(`free(p->name); p->name = dup(s);`), and must be whole again when the
function returns. A callee's prototype is read the same way through a
function pointer, so an owner passed through one is consumed.

`test/c/run/owners.c` does all of it and runs, `own_struct.c` with a struct
on the heap (an `own point *` parameter takes the struct over, a `const
point *` one only looks), `own_fields.c` with owners inside structs,
`borrows.c` with borrows, `params.c` with parameters; the programs under
`test/c/safe/` are each refused with the error their `.expect` names. Not
opened for ownership: what a plain pointer reaches beyond its own fields.

**The tie operator, `<*>`: `x <*> y` declares `x` to live within `y`**
(owner's rule). It goes after a declarator, and `y` is something declared
before it: a name in scope for a local, an earlier parameter, an earlier
member of the struct. `x` is dead the moment `y` is consumed, or `y`'s
scope ends: a tied plain value is a borrow of `y` whatever its type -- it
dangles when `y` goes, may not escape, and takes only values whose owner
outlives `y` -- and a tied owner must be consumed before `y` is, and may
be moved only into a slot within `y`.

```c
int a; double b <*> a;                       /* b lives within a */
own char *buf = malloc(16);
view v <*> buf = { buf + 7, 3 };             /* v holds borrows of buf */
struct list { own node *head; node *cur <*> head; };   /* in every list, cur borrows head */
node *find(node *head, int k) <*> head;      /* the result borrows head */
int gap(node *head, node *cur <*> head);     /* cur within head, checked at every call */
m := find(l.head, 3) <*> l;                  /* after := too */
```

A struct member tied to an earlier member is a tied slot in every
instance, the one place a borrow is stored: `l.cur = l.head + 2` is fine,
and `l.cur` dangles when `l.head` is freed. A struct instance tied to an
owner may hold borrows of it in any plain field. On a prototype the tie is
a contract: a parameter tied to an earlier one is checked at every call,
the argument within the argument; a result tied to a parameter makes the
caller's variable a borrow of that argument (`node *f = find(l.head, 30)`
borrows `l.head`, which nothing inferred before), and the callee's returns
are checked against it. A tie to a plain local anchors it -- a root that
nothing consumes, ending with its scope, so what is tied to it dangles
there; `&x` of a plain local and a local array used as a pointer are
anchored the same way, so `int *p = &x; return p;` is refused, while `&x`
stored into a plain field stays what C always allowed. Refused as
`tie_unknown`, `tie_outlived`, `tie_escapes`, `tie_mismatch` (the table
above); `test/c/run/tie.c` does all of it and runs, eight `safe/tie_*.c`
are refused.

**`clone(p)` hands a function a copy.** For `own T *p`, `f(clone(p))` gives
`f`'s own parameter a fresh copy of what `p` points to -- `malloc(sizeof
T)`, the struct copied -- so `p` is not consumed; `own T *q = clone(p)`
keeps one. It is a global macro (`library/ccl_format.pl`); `malloc` must be
declared. A struct with an own member cannot be cloned, its copy would own
the same memory twice. `test/c/run/clone.c` runs it.

**Every pointer has an ownership path, or the program is refused** (owner's
rule). A plain pointer local given fresh memory -- `char *p = malloc(8)`,
`FILE *f = fopen(...)`, the result of an untied function -- is *loose*:
memory with no owner behind it, followed as an owner without the word.
`free(p)`, `realloc`, an own parameter, `return p`, storing it into a slot,
or an own pointer taking it over (`own char *q = p`) consumes it, and a
borrow of it dangles when it is freed, as an owner's would. Where it is
still unconsumed -- its scope's end, a `return`, an overwrite -- it is
refused as `unconsumed`, where `own` would have said `owner_leaked`. A slot
the check cannot follow -- a global, a field, an element, `*p`, an item of
an initializer, a struct by value -- given such a value is refused at the
binding as `untied`. There is no flag against either; what the check
accepts is a statement it can follow: `own`, a tie, a consume point, a
value taken from an owner, a borrow, a parameter, or static storage.

A function returning a pointer to static storage says so with a tie to
that storage, a static local of its own or a global: `static struct pt
*origin(void) <*> o { static struct pt o; ...; return &o; }`. The caller's
variable is then a borrow of static storage, which nothing ends and
nothing may free. And a null test refines an owner: after `if (!p)
return;` or `if (p == NULL)`, `p` is null on that path, its own fields
with it, so `drop(own node *x) { if (!x) return; ... free(x); }` is
accepted as written.

**An own array, `own node *C[4]`, holds owners the check cannot tell
apart** -- which one `C[i]` names is not known at compile time -- so it
is one owner with an invariant, *every element is null or owned*, that
the lowering keeps with code the source did not write: when the struct
holding the array is freed, every non-null element is freed first, its own
struct drained before it, through one generated function per struct type,
`ccl_drain_<tag>`, recursive as the type is; a local array is drained the
same way at every exit of its scope, as a `defer`; the old element is
freed when a slot is overwritten; and the slot is nulled when an element
is moved out or handed to `free`, `fclose` or an own parameter. The check
asks the rest: an element takes an owner (`move`), a null or a fresh
value, never a borrow; it leaves by `move`, `free` or an own parameter,
and every borrow of the array dangles when any element goes; the array is
zeroed at birth, `calloc`, an initializer, or a call that built it; it
lives as a local or in a tagged struct behind an own pointer, never by
value; and an own pointer sits nowhere its owner cannot be named, not
behind a plain pointer, not in an array without a constant bound, not as
an array parameter. Refused as `own_unbounded`, `own_array_by_value`,
`own_array_untagged`, `array_unset`. A struct with an own array cannot be
cloned either. One bound more the check can name: a struct's last member
may be `own node *C[nc]` with `nc` an earlier integer member of the same
struct -- a flexible array the developer allocates room for and counts,
`calloc(1, sizeof(node) + k * sizeof(node *))`, `x->nc = k` -- and the
drain loops to `nc`. A leaf of a tree is then allocated without children
at all, 56 bytes, while an inner node has its slots in place: BTreeSet's
layout without its unsafe cast. `test/c/run/flex.c` runs it.

**Beating BTreeSet.** `bench/btree/run.sh` builds the same B-tree three
ways -- cicili `-O3`, the same algorithm in plain C for clang `-O3`, and
Rust's `BTreeSet` -- at BTreeSet's fanout, eleven keys per node, and runs
a million distinct keys inserted in a pseudo-random order, a million
searched with half present, half of the keys deleted, a million searched
again, the rest deleted. On an i9-9880H, the minimum of eleven interleaved
rounds, in ms:

| | insert | search | delete half | search again | delete the rest |
|---|---|---|---|---|---|
| cicili `-O3` | 94 | 90 | 62 | 92 | 66 |
| clang `-O3`, the same tree in C | 92 | 91 | 60 | 98 | 67 |
| Rust `BTreeSet` | 107 | 96 | 60 | 95 | 63 |

The node holds its keys in one cache line and its children in the bounded
own array, the keys are scanned without a branch where a key is placed,
every address is `inbounds` and every signed add `nsw`; deletion takes the
key out of its leaf and fixes only a node left short on the way back up,
as BTreeSet does. Insert and search are won, deletion is a tie.

**Compile time.** `bench/compile/run.sh` times `cicili++`, `clang++` and
`rustc` building the same two programs -- a hello with one `printf`, and
the B-tree of `bench/btree` (cicili's own for `cicili++`, the C mirror with
its two `calloc`s cast for `clang++`, `BTreeSet` for `rustc`) -- at `-O0`
and `-O3`, five runs each with the caches in place, the minimum and the
median of the wall clock; `cicili++`'s first run comes first, the init
phase, when the C++ headers are preprocessed and summarized into a fresh
`HOME`; then the front ends alone, to an object and to nothing. On the
same i9-9880H, the minimum of five, in seconds:

| | hello `-O0` | hello `-O3` | B-tree `-O0` | B-tree `-O3` | B-tree `-c` | B-tree, read only |
|---|---|---|---|---|---|---|
| `cicili++`, the first run (init phase) | 3.0 | | 8.1 | | | |
| `cicili++`, after it | 0.80 | 0.82 | 1.40 | 1.50 | 1.07 | 0.68 |
| `clang++` | 1.07 | 1.06 | 1.10 | 1.21 | 0.41 | 0.38 |
| `rustc` | 0.51 | 0.49 | 0.61 | 0.76 | 0.33 | |

`rustc` is the fastest on both programs; `cicili++` after its init phase
builds the hello faster than `clang++` and takes 1.27 times `clang++` on
the B-tree. For scale, a compiler written in another interpreted
language: the script also runs the Python ones this Mac can, when `PY`
names a python3 with them installed. `pycparser`, the C parser in Python
(a parser only, `clang -E` over its fake headers inside), reads the hello
in 0.30 s and the B-tree in 0.33 s where `cicili++ -fsyntax-only` takes
0.46 s and 0.68 s -- with the check, the C++ headers' summaries and
cocolog's start in those. ShivyC, a C compiler in Python to x86-64
assembly, refuses macOS and takes a small subset of C (no `enum`, no
`?:`, no `sizeof` of a type, no variadic prototype: the B-tree does not
compile); its front end driven to assembly past the check turns the
hello in 3 ms, plus 0.07 s to start Python, where `cicili++ -S` takes
0.50 s. Where `cicili++`'s time goes, measured piece by piece: cocolog
starts in 0.06 s and the library's clauses load in 0.03 s; the command's
shell is a floor of its own, a fork per `$(...)` and per pipe, so
`bin/cicili` forks six times where it forked twenty; a header's summary
is parsed in 30 ms; the raw parse of the 170 lines takes 0.1 s (the
lexer, since it went native, 20 ms; the parser one look per token); the
check 0.08 s and the lowering 0.17 s (46,000 predicate calls of the type
machinery and the emission, at cocolog's 5 µs a call), the embedded LLVM
and the link the rest -- `c++` links in 0.3 s, and `clang++`'s own link
is 0.7 of its 1.1 s. No process is spawned but the linker: the arch the
module was compiled on answers for `uname -m`, which cost 0.14 s a spawn,
twice a build. The init phase is paid once per header, 3 s for
`<stdio.h>`'s closure of 38 files and 8 s for the three headers the
B-tree includes. Eight floors went in turn, each measured before it was
touched -- the lexer (the DCG ran at 0.15 ms a token, the native one 600
times faster: 0.3 s of a build), the summaries' parse (0.5 s each, a
free-position `sub_atom/5` a line; 30 ms bound), the floor (the spawns
and the forks: an empty file's read from 0.62 to 0.39 s, in C mode over
the store from 1.05 to 0.1 s), the check and the lowering (`nb_getval/2`
copies what it answers, and the symbol table was read 4000 times: the
file scope in a global of its own, the answers cached, 1.0 s to 0.46 s),
the parser (sixty-two thousand token matches for two thousand tokens,
one look per token now, 0.3 s to 0.1 s), the lowering again (its text
joined by a walk over the codes, a quarter of it; the type resolution
chosen by its functor; the ABI classification cached: 0.4 to 0.21 s), the
LLVM type carried with every value (`ir_expr/4`, so the conversions,
stores and arithmetic stop deriving it from the C type: a tenth of the
calls, 0.21 to 0.19 s) and the inference (a global per name for the
caches whose values are large, the own-array test answered per tag, a
plain type resolved in one clause: a third of its calls, and the clock
within its noise) -- and the B-tree's build went from 3.64 to 1.40 s,
`test/compile.sh`'s eighteen programs and forty refusals from 37 to
26 s. What is left is the check's walk and the lowering's emission, at
cocolog's 5 µs a call.

`test/c/run/btree.c` and `btree_del.c` are the ownership test case: a
B-tree whose every node owns its children through an own array, fixed in
the first, bounded by the node's count in the second, and the root belongs
to the tree; walks and searches borrow, a search's result is tied to the
tree it came from, a parameter is tied to an earlier one, a full node is
split by moving its upper children into a new owner, a merge moves a
sibling's children over and frees it, a rotation moves one child across,
the root shrinks to its only child, and freeing the root drains whatever
is left, every node freed exactly once (`leaks` finds none, and the
degree-2 fixture's output is the sanitized C mirror's). `slots.c` does the
same with a local array. One shape the tree taught: an element is moved
OUT of a struct only through a name the check has a key for, a parameter
or an own local, never a local borrow, so a merge takes the node that goes
into an own local first and the rotations take both siblings as
parameters. Diagnostics, errors and warnings alike, are on stderr, as clang's;
`cicili -v`'s lines and `cicili: ok` on stdout.

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
module/cicili.cicili     the module: registration, ccl_version/1, the native lexer (C, in Cicili),
                         and the Prolog half (cicili_ast/2,3 and the objects layer)
library/ccl_syntax.pl    the two grammars: the lexer (the DCG, the specification the native one
                         follows token for token) and the parser; the symbol table
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
