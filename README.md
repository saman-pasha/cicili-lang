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
* **M1 -- the reader.** `cicili(+File, -AST)` reads a C file whole into an
  AST, through a DCG; each `#include` is found on the toolchain's path and
  read too; the knowledge base remembers every file by its modification
  time; a `.pl` included is a set of macros over ASTs with type inference.
  77 checks GREEN, including five real C files from the neighbours read
  entirely with their system headers.

## The reader: `cicili/2`, like `phrase/2`

```prolog
?- use_module(library(cicili)).
?- cicili('test/c/hello.c', AST).
```

reads the whole file -- two DCGs, one over character codes into tokens
that carry their line, one over tokens into terms -- and answers the AST,
or throws a syntax error naming the line the unread item begins on and the
line the grammar gave up at. `cicili(+File, -AST, -Rest)` is the `phrase/3`
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

the AST is (strings shown as text; they are code lists):

```prolog
unit([ include(2, system('stdio.h'),  file('/…/MacOSX.sdk/usr/include/stdio.h',  raw, unit([ … ]))),
       include(3, system('stdlib.h'), file('/…/MacOSX.sdk/usr/include/stdlib.h', raw, unit([ … ]))),
       function(5, none, base([], [int]), main, [], false,
                block([ expr(call(id(printf), [str("hello, %s\n"), str("cicili-lang")])),
                        return(int(0)) ])) ])
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
is unchanged and every header under it is at its remembered time. Run cocolog with the project's store -- a bare `--embed` opens
`./KB` in the working directory -- and each system header is parsed once
per project; the reader's version is part of the key, so a better grammar
re-reads what an older one left partial.

Otherwise the preprocessor is not expanded: any other `#` line is kept
whole as `directive(Line, Text)`, and a typedef name from a header the
reader has not seen is recognised from the tokens around it (`name x;`,
`name *p;` where an expression cannot stand, `(name *)`, `(name){`). What
it reads is C11 plus the GNU and Apple forms system headers and Cicili's
emitted C carry (`__attribute__`, `__asm`, `typeof`, `({ ... })`, `_Nonnull`,
`(^block)`); the C++ forms are not read yet -- they come after the C part
of the compiler is finished, because the libraries are in C++ (`DESIGN.md`,
M5) -- and `cicili/3` says where a file stopped.

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
[macro(square, square, 2), macro(sum, sum, dcg) …]))`, the macro file is a dependency of the includer's
cached read, and a macro that fails or throws stops the read with
`macro_failed(Name, Args)` or `macro_error(Name, Args, Error)`.

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
                         (cicili/2,3 and the objects layer)
library/ccl_syntax.pl    the two grammars: the lexer and the parser, as DCGs; the symbol table
library/ccl_include.pl   #include: the inclusion path, headers read raw or preprocessed, .pl macro
                         files, the knowledge-base cache
library/ccl_infer.pl     what a macro can ask: type inference over the symbol table, sizes, lookups
library/ccl_format.pl    the global macros format, print, println
library/cicili.so        built output; never committed (library/*.pl is)
module/build.sh          CICILI=… COCOLOG=… sh module/build.sh
proof/                   M0: LLVM IR to a native binary, and the script that proves it
test/reader.sh           the reader's gate; test/c/ its C samples
test/objects.sh          the objects layer's gate
tutorials/NN-*.pl        the objects layer's lessons, goal `main', last line `done'
DESIGN.md                the architecture, the four neighbours' roles, the milestones
```

Build and prove:

```sh
CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog sh module/build.sh
sh test/reader.sh
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
