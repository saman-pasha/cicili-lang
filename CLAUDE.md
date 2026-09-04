# cicili-lang -- how this repository is worked on

cicili-lang is a **Safe Modern C compiler to LLVM, written on cocolog**: a
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
                         half -- cicili_ast/2,3 (the reader's door) and the objects layer
library/ccl_syntax.pl    the lexer and the parser, two DCGs; COMMITTED (library/*.so is not)
library/ccl_include.pl   #include: the inclusion path (asked of clang), resolution, the
                         nested read (raw, else clang -E -dD), .pl macro files, the cycle
                         guard, the KB cache
library/ccl_infer.pl     the macro facilities: ccl_type_of/2 and lookups over the symbol table
library/ccl_format.pl    format, print, println: the global macros, Rust's holes
library/ccl_ir.pl        cicili_ir/2: the lowering to LLVM IR text, one clause per construct
library/ccl_build.pl     cicili_compile/3 (the embedded LLVM, else clang -c -x ir), cicili_link/3 (cc)
library/ccl_check.pl     the safe part: owners (own), move, the flow walk; run first by cicili_ir
test/c/safe/             programs the check must REFUSE, each with the error its .expect names
test/compile.sh          the compiler's gate: every test/c/run/*.c built and run, its output checked
module/build.sh          CICILI=… COCOLOG=… sh module/build.sh  ->  library/cicili.so
module/ccl_llvm.cicili   the embedded LLVM: a cocolog module in Cicili over llvm-c; parse,
                         verify, target, passes, object (ccl_llvm_compile/3, ccl_llvm_check/2)
module/build-llvm.sh     LLVM=… sh module/build-llvm.sh  ->  library/ccl_llvm.so (Homebrew's LLVM)
proof/forty2.ll, run.sh  M0: LLVM IR through clang to a native binary, exit 42
test/config.sh           the neighbours and the library path, sourced by every gate
test/reader.pl           the reader's gate: a cocolog program, one clause per check (71),
                         one process over one fresh store, every header parsed once
test/reader.sh           runs it, and adds the check only a second process can make
test/c/                  the gate's fixtures: hello.c, rich.c, the macro, :=, pattern,
                         format and shorthand samples, the bad ones
test/objects.sh          the objects layer's gate
tutorials/NN-*.pl        the objects layer's lessons; goal `main', last line `done'
DESIGN.md                the architecture, the neighbours' roles, M0..M4
```

Build and prove, always in this order:

```sh
CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog sh module/build.sh
sh test/reader.sh
sh test/compile.sh
sh proof/run.sh
```

**The surface is four predicates** (owner's rule): `cicili_ast(+File, -AST)`
(and `/3`), `cicili_ir(+Units, -IR)`, `cicili_compile(+IR, +ObjFile, +Flags)`,
`cicili_link(+Objects, +Flags, +Out)`. Everything else is `ccl_`.

**Nothing is claimed before its GREEN line.** A rule is a `check` in a gate;
a milestone has a proof that runs. Run the gate the change touches, not
everything, every time. A change to `library/*.pl` needs no rebuild -- the
`.so` only wraps it; a change to `module/cicili.cicili` does.

## Names

**Every predicate and function this library defines is `ccl_`-prefixed;
only `cicili` itself keeps its own name.** cocolog has one namespace, and a
grammar full of `expr` and `id` would collide with any program's. The AST's
functors (`unit`, `function`, `id`, `expr` ...) are bare: they are data.
Internals are `'$ccl_…'`. The repository is `cicili-lang`, the library
`library(cicili)`, the language's C name in prose `cicili-lang`.

## How the reader is implemented, and why that way

`cicili_ast(+File, -AST)` mirrors `phrase/2`: the whole file or an error;
`cicili_ast/3` mirrors `phrase/3`, answering the tokens left. Two DCGs in
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
compound literal `(T){…}` a `compound_lit/2`; and what Apple's SDK headers
add: `__asm("…")` after a declarator, `_Nonnull` and kin as qualifiers,
`(^block)` pointers, a `#define` inside a struct body or a declarator list
(clang -E -dD keeps them where they stood). C++ is not read yet.

**An `#include` is read as it is met** (`library(ccl_include)`): the
parser calls `ccl_include/2` at the directive, which resolves the name on
the inclusion path (the including file's directory for a quoted name; then
`ccl_include_dir/1`, `$CICILI_INCLUDE`, and clang's list from `clang -E -x c
-v /dev/null`, cached in `'$ccl_incpath'`), reads the file raw with the
same reader, and only if raw does not read whole runs THAT file through
`clang -E -dD` and reads the result; `file(Path, raw|preprocessed, Unit)`,
or `missing`, or `cyclic(Path)` through a `'$ccl_reading'/1` guard. The
included unit's typedef names are appended to the includer's Env. The
current file is a global, `'$ccl_file'`, saved and restored with `'$ccl_env'`
and `'$ccl_far'` around a nested read (`ccl_with_file/2`).

**A `.pl` included is a macro file** (owner's rule): every predicate it
defines is a macro; `name(a, b)` in C with `name/3` among them runs NOW as
`name(ASTa, ASTb, R)` and R replaces the call (`ccl_call_or_macro/3` in the
postfix grammar; a statement-shaped R is unwrapped by `ccl_stmt_of/2`; a
list R is `'$splice'/1`, spliced by `ccl_splice/3` in blocks and at file
scope; a file-scope call `name(args);` is its own `ccl_external` clause). A
DCG rule `name(R) --> …` is `dcg(name)`: called as `phrase(name(R), Args)`.
The file is loaded with `ensure_loaded/1` (a reload replaces; under the
store its clauses stay in the process) and its heads are found by splitting
its text into clauses and `term_to_atom/2` on each (`ccl_pl_clauses/2`),
because `current_predicate/1` does not list consulted clauses. The registry
is the global `'$ccl_macros'`, saved and restored with the others.

**The symbol table is kept while parsing**, for the macros: `'$ccl_scope'`
(frames of Name-Type, innermost first; pushed by `ccl_compound` and at a
function's parameters, only when `{` is next), `'$ccl_typedefs'`
(Name-Type), `'$ccl_tags'` (Tag-Members; enumerators declared as int).
`ccl_note_item/1` feeds them from every declaration, typedef, tag and
function the grammar produces, and `ccl_include_scope/1` from every
included unit. `library(ccl_infer)` reads them: `ccl_type_of/2` with the
usual arithmetic conversions, `ccl_resolve_type/2`, `ccl_size_of/2` (LP64).

**`name := expr;` is a declaration by inference** (owner's rule): the lexer
has `:=` as a punctuator; `ccl_infer_decl/4` takes `ccl_type_of/2` of the
right-hand side, decays arrays and functions, strips top-level qualifiers,
and builds `declaration(L, none, Base, [var(N, T, E)])`; `unknown` throws
`error(cannot_infer(N, E), here(File, L))`. It is a clause of
`ccl_external`, `ccl_block_item` and `ccl_for_init`, before the others.
**The left may be a pattern** (owner's rule): `ccl_pattern//1` reads
`{ a, _, f: b, g: { c } }` into bind/skip/field/sub terms and
`ccl_destructure/4` turns it into one inferred declaration per binding
(`member/2` or `arrow/2` accesses, by position through `ccl_nth_member/4`
or by name through `ccl_member_access/6`), a `ccl_gensym` temporary first
when the right-hand side is not an `id/1`; the result is a `'$splice'/1`.
Errors: `no_member(Field | position(I), Type)` with `here/2`.

**`name { members }` at file scope is `typedef struct name { members } name;`**
(owner's rule): a `ccl_external` clause on `ccl_id(N), ccl_peek(p, '{')`,
before the others; the members are read with `ccl_members//2` (where
`name *` is a type), the name joins the Env, and the item is the plain
`typedef/2` that `typedef struct` would give.

**`defer(a, b) { body }` is a statement** (owner's rule: scope-bound, like
Cicili's cleanup, the first of the three ways to lower it -- a static
cleanup chain with a destination slot, no runtime): `ccl_statement` on
`ccl_id(defer), ccl_p('('), ids, ccl_p(')'), ccl_peek(p, '{')`, so a call
named defer without a block stays a call; the node is
`defer(Line, [id(V) …], block(...))`. It runs at every exit of its scope,
LIFO, over the variables' values at that moment.

**`format`, `print`, `println` are global macros** (owner's rule):
`library/ccl_format.pl` is a macro file registered by `ccl_standard_macros/0`
at the start of every unit (found on `$COCOLOG_LIBRARY`, which is also on
the inclusion path). Rust's holes over `ccl_type_of/2`; a struct by its
members. A predicate named `ccl_macro_X` in a macro file is the macro `X`
(`ccl_macro_cname/2`), since `format/2,3` is a builtin; the registry entry
is `macro(CName, Pred, Arity | dcg)`. `ccl_type_of/2` of a statement
expression puts its declarations in scope for its last expression, which
is how `s := format(...)` is a `char *`.

**The knowledge base is the cache.** A file read whole is
`'$ccl_ast'(Path, key(MTime, Version), meta(What, Count, Deps))` plus one
`'$ccl_item'(Path, Key, Index, Item)` per top-level item, an include inside
it stored as `ref(Path, How)` and re-linked on load through
`ccl_include_read/2`; `ccl_kb_cached/3` checks `time_file/2`,
`ccl_reader_version/1`, every dep's remembered key, and the item count.
Both predicates are declared dynamic by `ccl_kb_ready/0`. A bare `--embed` is `./KB` in the working directory -- the
per-project store. BUMP `ccl_reader_version/1` whenever the grammar
changes, or a partial read from an older grammar stays cached. The reader
gate is one process over one fresh `--embed`, so every header is parsed
once; `test/reader.sh` then asks a second process for what the first read.

## How the lowering is implemented

`library(ccl_ir)`: `ccl_ir_units/2` rebuilds the symbol table from the units
(`ccl_items_note/1`) and emits text. Per function, globals hold the state:
`'$ir_body'` (lines, reversed), `'$ir_allocas'` (the entry block's),
`'$ir_env'` (frames of Name-loc(Addr, Type)), `'$ir_defers'` (frames of
defer bodies), `'$ir_loops'` (break/continue targets with the defer depth
at entry), `'$ir_term'` (is the current block terminated). `ir_expr/3` gives
a value and its C type, `ir_lval/3` an address, `ir_cond/2` an i1,
`ir_convert/4` C's conversions; `ir_ins/1` opens a dead block after a
terminator so every block ends once. `defer`: `ir_run_defers/1` inlines a
scope's bodies LIFO at its end, at `break`/`continue` (the frames inside the
loop) and at `return` (all). Doubles print as LLVM's hex (`ir_double/2`);
structs are named types registered once; an anonymous struct is keyed by
its members. Externals used get `declare` lines from their prototypes.
Not lowered yet: bitfields, unions' members, static locals, VLAs, `_Complex`,
`long double` (as double) -- each `error(not_lowered(What), where(F))`.

## How the safe part is checked

`library(ccl_check)`: `ccl_check_units/1` walks every function of the
given units before lowering. The reader gives `own` as a qualifier (on the
pointee, C's grammar: `own char *p` is `ptr([], base([own], [char]))`, and
`ck_own_type/1` looks in both places) and `move(E)` as a node. The state is
`st(Frames)`, a frame `fr([Name-live|moved|partial ...], Defers)`; `ck_stmt/3`
threads it, `dead` for a path that ended. A join (`ck_merge/3`) makes an
owner `partial` when the sides differ; `partial` is refused on use and
counts as leaked. Scope end and `return` run the frames' defers
(`ck_run_defers`) then demand every owner moved (`ck_leaks`). Loops:
`ck_no_moves_across/3` refuses an outer owner consumed in the body; a
`break`/`continue` closes the frames inside the loop and joins the loop's
exits (`'$ck_loops'`). `ck_consumes/2`: free, fclose, and any callee whose
i-th parameter is `own`. The lowering treats `move(E)` as `E`.

## How the LLVM module is written (the Cicili module pattern)

Every C function a Cicili module calls that is not in Cicili's std is
declared with `(decl) (func Name ((Type arg) ...) (out Type))`, mirroring
the header (compatible types, one token each -- `LLVMBool`,
`LLVMContextRef`, `char **`; `unsigned` needs an alias,
`(@define (code "uint_t unsigned"))`). An enum constant or a `static inline`
from a header cannot be named in Cicili at all: it goes behind a one-line
raw C helper, `(code "static T ccl_ll_x(...) { ... }")`, itself declared with
`(decl)` -- the numpy module's way. `(cof p)` is `*p`, `(? c a b)` the
conditional, `(cond ((test) ...) ...)` a chain. A parameter may not be
named `asm`. The build mirrors `module/build.sh` plus `llvm-config
--cflags/--ldflags`, `-lLLVM-C` and an rpath to LLVM's lib.

## Findings about the neighbours, worked around here

* **A `catch/3` whose goal succeeds leaves a live frame: a later `throw/1`
  runs that catch's recovery and then continues after the catch** (in
  cocolog; `catch((catch(nb_getval(k, X), _, X = none), throw(x(X))), x(G),
  true)` gives `G = none`). A cut after the catch, `once(catch(...))`, or
  the catch as an if-then-else condition pops the frame. So NO BARE
  `catch/3` anywhere in this repository: every one is `once/1`-wrapped or a
  condition. The older finding that a `throw/1` inside `forall/2` escapes
  the `catch/3` around it is probably the same defect seen from the other
  side; loops that can raise stay plain recursion, and `new/3` checks its
  initial values BEFORE the instance exists.
* **Consulting a file of about 70 facts whose arguments carry goals into
  an embedded store segfaults cocolog**, so the gate's checks are clauses
  (`k1 :- check(Name, Goal).`), not facts driven by `findall/3`.
* **`atomic_list_concat/2` with an unbound element segfaults cocolog**
  (exit 139, no message) instead of raising an instantiation error; the
  gate's `k17` did that before its scratch directory was bound.
* **`atomic_list_concat/2` dies silently once its result passes about
  8 KB** (no error term; a later message may show garbage), while
  `atom_codes/2` takes hundreds of KB: anything long is joined as codes
  (`ir_join/3`) and made an atom once.
* **An unset global throws** (`nb_getval/2`: existence_error), so a global
  is read through `ccl_global/3` or a `once(catch(...))`.
* cocolog has `abolish/1`, `clause/2` on consulted clauses and `retract/1`
  of them, `nb_setval/2`, `dynamic/1`, `read_file_to_codes/2`, `phrase/2,3`,
  `number_codes/2`; it has no `predicate_property/2`, `flag/3`, `recorda/2`,
  `prolog_load_context/2`, `term_expansion`, and no `consult/1` as a goal.
* `0'"` and `0''` read badly in cocolog; the lexer writes 34, 39, 92 as
  numbers. `( A -> B ; C )` inside a DCG body is avoided in favour of
  `( A, ! ; C )`.
* **A predicate with ONE clause over about 8 KB loses EVERY clause in the
  embedded store, silently** -- the ones asserted before it and after it
  too (a list of 1000 integers survives a process, 2000 do not, and a small
  fact beside the big one is gone as well). Nothing large goes in one
  clause: a unit is stored one clause per item, with its count. (An earlier
  note here blamed `:- dynamic` in a library's text; that was wrong -- such
  a predicate persists like any other, which is the next finding.)
* **Every dynamic predicate persists under `--embed`, a library's too**, so
  what must be per process -- the units read, the cycle guard, the macro
  files loaded -- is a global (`nb_setval/2`), never a clause: a persisted
  "already loaded" fact once told a later process a macro file was loaded
  when it was not.
* `current_predicate/1` does not list the predicates a consulted file
  (`ensure_loaded/1`) defines, only a dozen builtins; `ensure_loaded/1`
  exists (`consult/1`, `load_files/2`, `open/3` do not), loading a file
  again replaces its clauses, and under `--embed` they are not stored.
* `::` is right-associative, so `geometry::rect::square(3, S)` reads as
  `geometry::(rect::square(3, S))`; the objects dispatcher has a clause for
  a receiver that is a module rather than an object.

## Commits

Commit and push only when the owner asks. Every commit ends with

    Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01FUuQ3oBiKs3XpXAEHLCL1F

and the push is `git push git@github.com:saman-pasha/cicili-lang.git main:main`.
Never commit `library/*.so`, `module/*.c`, `module/sdk.cicili` or `proof/forty2`.
