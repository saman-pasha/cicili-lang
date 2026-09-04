# cicili-cpp

**A Safe Modern C compiler to LLVM, written on cocolog.**

cicili-cpp is a new implementation of [Cicili](https://github.com/saman-pasha/cicili)'s
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
  AST, through a DCG. 32 checks GREEN, including five real C files from the
  neighbours read entirely.

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
    printf("hello, %s\n", "cicili-cpp");
    return 0;
}
```

the AST is (strings shown as text; they are code lists):

```prolog
unit([ directive(2, '#include <stdio.h>'),
       directive(3, '#include <stdlib.h>'),
       function(5, none, base([], [int]), main, [], false,
                block([ expr(call(id(printf), [str("hello, %s\n"), str("cicili-cpp")])),
                        return(int(0)) ])) ])
```

A function-pointer parameter comes out inside out, the way C means it --
`int (*f)(int)` is `param(ptr([], fn(base([], [int]), [param(base([], [int]), anon)], false)), f)`
-- and a C99 compound literal from Cicili's own emitted C, `(Parcel){ id, w }`,
is `compound_lit(base([], [typedef('Parcel')]), init([item([], id(id)), item([], id(w))]))`.
The full AST vocabulary is at the top of `library/ccl_syntax.pl`.

The preprocessor is not expanded: a `#` line is kept whole as
`directive(Line, Text)`, and a typedef name from a header the reader has
not seen is recognised from the tokens around it (`name x;`, `name *p;` in
a parameter or a struct, `(name *)`, `(name){`), which is how the neighbour
files read whole without their headers. What it reads is C11 plus the GNU
forms Cicili emits (`__attribute__`, `typeof`, `({ ... })`); the C++ forms are
not read yet, and `cicili/3` says where a file stopped.

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
library/ccl_syntax.pl    the two grammars: the lexer and the parser, as DCGs
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
