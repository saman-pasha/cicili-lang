# cicili-cpp -- how this repository is worked on

cicili-cpp is a **Safe Modern C compiler to LLVM, written on cocolog**: a
new implementation of Cicili's philosophy. It reads C, checks it, lowers it
to LLVM IR; no C is ever emitted. Read `README.md` for what runs today and
`DESIGN.md` for the architecture and the milestones.

## The three neighbours are used, never edited

[Cicili](https://github.com/saman-pasha/cicili) is the philosophy and the
reference for what every form must mean, and the language any native piece
here is written in; [cocolog](https://github.com/saman-pasha/cocolog) is the
host: every pass is cocolog clauses, loaded through `COCOLOG_LIBRARY`;
[ZiguratIP](https://github.com/saman-pasha/ziguratip) is the store under
cocolog. **Nothing in this repository changes any of them.** A limitation
met in one of them is worked around here and written down as a finding
(below), and raised with the owner as a request to THAT repository. The
checkouts are named by `CICILI`, `COCOLOG` and `ZIGURATIP` in the
environment, defaulting to `~/Projects/GitHub/<name>`; `test/config.sh`
reads them and puts this checkout's `library/` at the FRONT of
`COCOLOG_LIBRARY`, keeping whatever the caller had behind it.

## Where things are

```
module/cicili.cicili     the module: the C side (registration, ccl_version/1) and the Prolog
                         half -- cicili/2,3 (the reader's door) and the objects layer
library/ccl_syntax.pl    the lexer and the parser, two DCGs; COMMITTED (library/*.so is not)
module/build.sh          CICILI=… COCOLOG=… sh module/build.sh  ->  library/cicili.so
proof/forty2.ll, run.sh  M0: LLVM IR through clang to a native binary, exit 42
test/config.sh           the neighbours and the library path, sourced by every gate
test/reader.sh           the reader's gate; test/c/hello.c and rich.c its samples
test/objects.sh          the objects layer's gate
tutorials/NN-*.pl        the objects layer's lessons; goal `main', last line `done'
DESIGN.md                the architecture, the neighbours' roles, M0..M4
```

Build and prove, always in this order:

```sh
CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog sh module/build.sh
sh test/reader.sh
sh proof/run.sh
```

**Nothing is claimed before its GREEN line.** A rule is a `check` in a gate;
a milestone has a proof that runs. Run the gate the change touches, not
everything, every time. A change to `library/*.pl` needs no rebuild -- the
`.so` only wraps it; a change to `module/cicili.cicili` does.

## Names

**Every predicate and function this library defines is `ccl_`-prefixed;
only `cicili` itself keeps its own name.** cocolog has one namespace, and a
grammar full of `expr` and `id` would collide with any program's. The AST's
functors (`unit`, `function`, `id`, `expr` ...) are bare: they are data.
Internals are `'$ccl_…'`. The repository is `cicili-cpp`, the library
`library(cicili)`, the language's C name in prose `cicili-cpp`.

## How the reader is implemented, and why that way

`cicili(+File, -AST)` mirrors `phrase/2`: the whole file or an error;
`cicili/3` mirrors `phrase/3`, answering the tokens left. Two DCGs in
`library(ccl_syntax)`: `ccl_lex//2` over character codes -> tokens
`tok(Kind, Value, Line)`; `ccl_externals//2` over tokens -> the AST (its
vocabulary is the file's header). Precedence is a level per operator
class; declarators are parsed inside out and folded onto the base type by
`ccl_mk_type/4`. The preprocessor is NOT expanded -- a `#` line is a
`directive/2` node -- so a typedef name from a header is unknown; it is
recognised from context instead (`name x`, `name *p` where an expression
cannot stand, `(name *)`, `(name){`, `name *p = …` in a block), plus a seed
of the standard typedef names. Typedefs the file itself declares are
threaded as an Env and mirrored in `nb_setval('$ccl_env')` for the casts
deep inside expressions. `ccl_p`, `ccl_kw`, `ccl_id` note the farthest line
reached, so an error says `line(Start), near(GaveUp)`.

The GNU forms Cicili's own emitted C carries are read: `__attribute__((…))`
dropped, `typeof(…)` a specifier, `({ … })` a `stmt_expr/1`, and C99's
compound literal `(T){…}` a `compound_lit/2`. C++ is not read yet.

## Findings about the neighbours, worked around here

* **A `throw/1` inside `forall/2` escapes the `catch/3` around it** in
  cocolog. Every loop in the Prolog half that can raise an error is plain
  recursion, and `new/3` checks its initial values BEFORE the instance
  exists.
* cocolog has `abolish/1`, `clause/2` on consulted clauses and `retract/1`
  of them, `nb_setval/2`, `dynamic/1`, `read_file_to_codes/2`, `phrase/2,3`,
  `number_codes/2`; it has no `predicate_property/2`, `flag/3`, `recorda/2`,
  `prolog_load_context/2`, `term_expansion`, and no `consult/1` as a goal.
* `0'"` and `0''` read badly in cocolog; the lexer writes 34, 39, 92 as
  numbers. `( A -> B ; C )` inside a DCG body is avoided in favour of
  `( A, ! ; C )`.
* `::` is right-associative, so `geometry::rect::square(3, S)` reads as
  `geometry::(rect::square(3, S))`; the objects dispatcher has a clause for
  a receiver that is a module rather than an object.

## Commits

Commit and push only when the owner asks. Every commit ends with

    Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01FUuQ3oBiKs3XpXAEHLCL1F

and the push is `git push git@github.com:saman-pasha/cicili-cpp.git main:main`.
Never commit `library/*.so`, `module/*.c`, `module/sdk.cicili` or `proof/forty2`.
