# cicili-lang — a Safe Modern C compiler to LLVM, written on cocolog

**Status: M0 (the LLVM path), M1 (the reader, with includes and the
knowledge-base cache) and M1b (macros and the symbol table) are built and
GREEN; M2, the first function lowered to a binary, is next.**

cicili-lang is a compiler for Safe Modern C — C source, extended by macros
written in Prolog — that lowers straight to **LLVM IR** and produces a
native object. It is **not a transpiler**: it does not emit C. Cicili (the existing
one) emits C text and hands it to a C compiler; cicili-lang does the
compiler's own work — parse, type, check ownership, lower to IR — and reaches
a binary through LLVM. The C compiler, where it appears, is only the
assembler and linker driver for the IR, the way Cicili drives `cc` for
source.

It is written on cocolog, and **uses cicili, ZiguratIP and cocolog without
touching any of them.**

## Why this shape

A compiler is unification, grammar rules, and a lot of small case-by-case
lowering laws — which is what Prolog is for, and cocolog is a Prolog with a
store that suspends to disk and an object-and-module layer already built
here. LLVM is the backend that turns a typed, checked IR into fast native
code without our writing a register allocator. Cicili is the language we are
implementing and the reference for what every form must mean. Each neighbour
does the thing it is best at, and none is modified.

## The four neighbours, each used and never edited

| neighbour | its job here | how it is used, not touched |
|---|---|---|
| **cicili** | the LANGUAGE and its meaning: `func`, `struct`, `let`, `letin`, ownership, `maybe`/`either`, generics. Its `doc/DOC-C.md` and `doc/DOC-CPP.md` are the spec cicili-lang compiles to the same meaning. And it is the language any NATIVE piece of cicili-lang is written in — the LLVM binding and the driver are Cicili modules. | we read its docs and reuse its surface; we never edit its Common Lisp transpiler. cicili-lang is a second, independent back end for the same language: LLVM where the original is C. |
| **cocolog** | the compiler's HOST. Every pass is cocolog clauses: the reader → an AST of terms, the type checker (unification), the ownership and lifetime checker (the "safe"), and the lowering to LLVM IR. Its DCG reads the surface; its store holds the symbol tables; the objects-and-modules module already here may structure the passes. | the compiler is a set of `.pl` files and, where a pass needs C speed, cocolog modules — all loaded through `COCOLOG_LIBRARY`, none of cocolog's own source changed. |
| **ZiguratIP** | through cocolog's store: a PERSISTENT compilation cache. A module's checked AST and its emitted IR, keyed by the hash of its source, live in the store, so a rebuild recompiles only what changed — cocolog's suspend-to-store nature applied to compilation. | reached only as cocolog's backing store, never directly. A design proposal, not required for M0–M2. |
| **LLVM** | the TARGET and the optimizer and the code generator. cicili-lang emits LLVM IR; LLVM lowers it to native code. | reached first as textual IR + `clang` as assembler/linker (PROVEN, see M0), since M2 as the in-memory `llvm-c` binding written as a Cicili cocolog module (`library(ccl_llvm)`: parse, verify, passes, object) -- and ONLY so: owner's rule (M5), no clang and no LLVM binary is run by anything here; the reader has its own preprocessor in cocolog, and the link through `cc` is the one system tool left, `llvm-c` having no linker. |

## The pipeline

```
Cicili source  ──reader──▶  AST (cocolog terms)
                                │
                     ┌──────────┴───────────┐
                     │  resolve: names, modules, types declared vs used
                     │  type-check: unification over the AST, Cicili's rules
                     │  check (THE SAFE PART): ownership, move, lifetime,
                     │     bounds — a violation is a compile error at the form
                     └──────────┬───────────┘
                                │  a typed, checked AST
                           lower to LLVM IR   (one clause per form → IR)
                                │
                          emit  module.ll
                                │
             library(ccl_llvm)  (the embedded LLVM: IR → native .o; cc links)
                                │
                             a binary
```

Each stage is cocolog clauses over terms. Lowering is a relation
`ir(+TypedForm, -Instrs)` with one clause per construct, the way Cicili has
one emit rule per clause — but the target is SSA IR, not C text, so the
checker's guarantees are carried into typed IR rather than re-proved by a C
compiler.

## The source surface: C, read by a DCG (decided)

The input is a **C/C++ source file**, read whole. `cicili_ast(+File, -AST)`
acts like `phrase/2`: it reads the file entirely and, through a DCG, answers
its AST; `cicili_ast/3` is the `phrase/3` form, answering what remained. The
grammars are `library/ccl_syntax.pl`: a lexer over character codes into
tokens that carry their line, and a parser over tokens into terms. The
preprocessor is cocolog's own (M5): the file and its headers go through
it, a `#define` or an `#include` stays a node so the macro files and the
`#cocolog` blocks are the reader's, and typedef names from unseen headers
are recognised from the tokens around them. This is M1, and
it is done (see below); the checker and the lowering take the AST from here.

## Milestones

* **M0 — the LLVM path runs. DONE.** `proof/forty2.ll`, a hand-written LLVM
  IR module, compiled by Apple's `clang` to a native Mach-O binary that
  prints a line and exits 42. No LLVM install: Apple clang consumes textual
  IR and drives the backend. This proves the target end of the pipeline on
  this machine before any of the compiler exists.
* **M1 — the reader. DONE.** `cicili_ast/2,3` over two DCGs (the lexer
  since native, a cocolog module in Cicili, the DCG its specification): C11 plus the GNU
  forms Cicili's emitted C carries (`__attribute__`, `typeof`, `({…})`,
  compound literals), every `#include` found and read, the knowledge base
  as the cache. `test/reader.sh`: 80 checks GREEN, one per construct,
  the error positions, and five real C files from the neighbours
  (`cicili/test/c/main.c`, `shared.c`, `macro.c`, `example/cimath.c`,
  `numpy_example.c`) read entirely.
* **M1b — macros and the symbol table. DONE.** `#include "m.pl"` makes
  every predicate of a Prolog file a macro over ASTs (a DCG rule a variadic
  one), run at parse time; the parser keeps the scope, the typedefs and the
  tags as it reads, and `library(ccl_infer)` gives a macro type inference
  and layout over them. This is Cicili's macro philosophy -- the language
  extended in the language that compiles it -- with Prolog as the macro
  language and C as the surface.
* **M2 — the lowering. DONE.** `cicili_ir/2` lowers the units to an LLVM
  IR module, `cicili_compile/3` makes the object, `cicili_link/3` the
  binary: C11's core (every type but bitfields and unions, every statement
  and operator, variadic calls, structs by value and by pointer, `defer` as
  the static cleanup chain) built and run by `test/compile.sh`, which
  checks each program's output and exit code -- through the embedded
  LLVM, `library(ccl_llvm)`, a cocolog module over `llvm-c` (parse, verify,
  target, passes, object), the only back end (the `clang -c -x ir` door
  of M2 closed in M5 by the owner's rule).
* **M3 — structs and the safe part. DONE.** Structs, scopes and `defer`
  lower (M2); the first ownership check is in: `own` pointers are linear,
  `move` hands them on, and use after move, the double free, a leak on any
  path, a move in a loop, an overwritten owner are compile errors naming
  the form (`library(ccl_check)`, run first by `cicili_ir`); borrows -- a
  plain pointer copied from an owner -- dangle when the owner is consumed
  and may not escape; every statement carries its line, so the place is
  the statement's. Owners inside structs: an own field is an owner named by
  its path (`p->name`, `c.name`), going with its struct -- consumed before
  the struct is freed, complete when it is moved, moved into a copy; a
  borrow or an owner's pointer stored into a plain field, an element, a
  global or through a pointer is refused, since the check could not follow
  it. Structs by value cross a call as the platform ABI has it: SysV
  x86-64's eightbytes, byval and sret, proven against clang-built code in
  both directions (`test/c/link/abi_*`); AAPCS64's i64 pairs, HFAs and
  indirect copies are written on the same classification and unproven, no
  arm64 being at hand. A plain pointer parameter is a borrow of the
  caller's: read, passed on, returned, never stored, freed or moved, so a
  borrow handed to any function is safe; an own field of the struct it
  points to may be replaced and must be whole again at the return; a
  callee's prototype is read through a function pointer too. The C core's
  last gaps -- unions, bitfields, static locals -- lower as C lays them out,
  the bitfield struct and the union in the ABI check with clang.
  **The tie operator, `x <*> y` (owner's):** x lives within y -- a local
  within another, a member within an earlier member, a parameter within an
  earlier one, a function's result within a parameter -- and the check
  makes a tied value a borrow of y whatever its type, a tied owner one that
  must go before y and may move only within y, a tied member a slot where a
  borrow is stored, and a prototype's ties a contract checked on both
  sides: the caller's arguments and the callee's returns. `clone(p)` copies
  what an owner points to, for an own parameter. Every pointer has an
  ownership path or the program is refused: a plain pointer holding fresh
  memory is followed to its consume point, and a slot the check cannot
  follow takes no such value; a result may be tied to static storage; a
  null test refines an owner. An own array of constant bound, `own node
  *C[4]`, is one owner whose elements are null or owned, an invariant the
  lowering keeps with generated drains -- at the holder's free, at a
  local's scope end, at an overwrite -- and the check completes: no borrow
  stored, zeroed at birth, behind an own pointer in a tagged struct, an own
  pointer nowhere its owner cannot be named; a struct's last member may be
  bounded by an earlier member instead, `own node *C[nc]`, a flexible
  array the drain loops to. `test/c/run/btree.c` and `btree_del.c`, a
  B-tree on such an array with insertion and deletion, are the ownership
  test case, and `bench/btree/` the proof that the language costs nothing:
  the same tree beats Rust's `BTreeSet` at its own fanout on insert and
  search and ties it on deletion.
  **`defer` is decided (owner):** scope-bound, like
  Cicili's `cleanup`, `defer(a, b) { free(a); }`, lowered the static way --
  each scope a cleanup block running its defers last-first and branching
  to the enclosing scope's; a `return`, `break`, `continue` or `goto` out
  parks its value and destination in slots and jumps into the chain, whose
  end switches on the destination; a defer registered conditionally gets an
  `i1` flag. After `mem2reg` the slots and the switch fold away: the
  deferred calls sit inline on each path, zero overhead, exactly what the
  cleanup attribute means in Cicili's emitted C. Go's accumulating defer
  would need a runtime list and is not this; `longjmp` skips defers, as it
  skips destructors, and the checker will call that unsafe.
* **M4 — the cache. DONE.** Every file read whole -- the source and every
  header under it -- is in the store as `'$ccl_ast'(Path, key(MTime,
  ReaderVersion), …)` and loaded from there while the file's time is
  unchanged (`library(ccl_include)`); the store is the user's,
  `~/.cicili/KB`, stamped with the reader's and the lowering's versions
  and started afresh when either changes. The IR of every file built joins
  it beside the unit, under a signature of everything it came from -- the
  file's key, the key of every header and macro file its AST reaches, the
  lowering's version, the host -- so a rebuild that touches one file
  checks and lowers that one and serves the others' IR, the check having
  passed when it was made (`library(ccl_driver)`, `dr_ir/3`; the gate
  builds two files, touches one, and sees one redone). The store's own
  costs are cocolog's: every predicate's first call
  under `--embed` probed the store in proportion to its bytes (fixed in
  cocolog 1.2.2 by indexing the string keys), and a process that writes a
  predicate still grows the store by that predicate's whole row count,
  never reclaimed -- hence one item predicate per file here, and
  compaction raised with cocolog.
* **M5 — the C++ reader. IN PROGRESS: the first slice DONE**, as
  `bin/cicili++`, a separate command: the reader in a C++ mode reads
  namespaces, using, `extern "C"`, templates (declarations, template-id
  types, explicit arguments), classes with access labels, methods,
  constructors and their initializers, destructors, inheritance, operators,
  default arguments, references, `new`/`delete`, `this`, the casts,
  lambdas, range-for, try/catch/throw, `auto` by inference, enum class;
  gated by `test/cpp.sh` (21 constructs, the six C++ files of Cicili's test
  suite read whole, a C++ file that is C built through `c++`). **The
  preprocessor is cocolog's own** (`library(ccl_pp)`, owner's rule: no
  clang, no LLVM binary, the embedded LLVM alone): directives, conditional
  groups, macro expansion, `#include_next`, the built-ins, the target's
  predefined macros as data; it replaced every `clang -E` and `clang++
  -E`, and the inclusion path comes from the SDK's and LLVM's conventional
  places. The user's own file goes through it too, its macros and the
  headers' expanded, a header's macro table kept beside its unit in the
  store or in its summary. A library header is flattened by
  it, read once, and SUMMARIZED to one file under `~/.cicili/cpp`
  -- its declarations, not its text -- which the next run loads instead:
  cocolog's store cannot hold units that size (the finding in
  `CLAUDE.md`), and the summary is what the passes need of a header
  anyway. The plan: the reader
  grows the C++ forms, because the libraries are in C++: classes
  with member functions, constructors and destructors and access labels;
  `namespace` and `::`; references; `new`/`delete`; templates, on
  declarations and in type names (which needs the symbol table to tell
  `vec<int>` from a comparison); `auto`; lambdas; `operator` functions;
  default arguments; `extern "C"`. Gated the same way: a sample per
  construct, then a real C++ file from the neighbours read whole (Cicili's
  emitted C++ first); `<vector>` and friends preprocess to tens of
  thousands of lines and are a one-time cost per project through the cache.
  `:=` and the patterns extend to classes as they are; `ccl_type_of/2`
  learns `this`, bases and overloads.
* **M6 — the check and the lowering of the C++ forms, IN STEPS: eleven
  DONE.** The forms that are C with names: a namespace flattened
  to its bare names, `extern "C"`, `using`, `bool`, `nullptr`, the casts,
  `enum class`, a range-for over an array as the `for` it stands for, a
  reference as a pointer bound once (a borrow to the check, an address
  loaded through by the lowering), `new` and `delete` as `malloc` and
  `free` under the ownership check; two programs built through
  `cicili++`, run and checked in `test/cpp.sh`. Then classes, DESUGARED
  to that C before the check by one typed rewrite of the AST
  (`library/ccl_cpp.pl`): a class a struct of its data members with its
  base first, a method a function over `this`, a constructor called at
  the declaration and a destructor a defer of the scope, a static member
  a global, `new` and `delete` constructing and destroying, operators and
  default arguments by name and arity -- so the check and the lowering
  see only the C they have. Then `virtual`, the same way: a struct of
  function pointers per class and a global table of them, the object's
  first member pointing at its class's table, set by every constructor;
  a call through a pointer or a reference dispatches through it, a
  virtual destructor too. Then templates: instantiated on use, a copy of
  the item with the parameters substituted, named by its arguments, a
  class template at every template-id met and a function template at a
  call with its arguments explicit or deduced, the instances joining the
  unit's items -- no template from a header's summary, whose body is
  gone. Then lambdas: a class of the captures with `operator()` its
  body, made and desugared like a class written out, a call of the
  object going to the operator. Then a real program: the B-tree the
  C++ way, a class over `own` pointers, which taught the check the
  object's lifecycle -- a constructor's `this` fresh, a destructor's
  dying -- so a class holds what a struct held. Then, over a string
  and a container the program wrote: a header's classes and templates
  reach every unit that includes it, emitted once (`linkonce_odr`); a
  class with a destructor is never copied, it is MOVED: `std::move` is
  Cicili's `move`, a struct moved whole empties its owners behind it,
  an element leaves a container by an explicit destructor call; a
  member of class type is constructed and destroyed with its holder,
  implicitly where the holder wrote no constructor or destructor. THE
  STANDARD LIBRARY IS libc++'s, never the compiler's own (the owner's
  rule; the C freestanding headers were the one exception, on the C
  side), C++17 the baseline and the next majors after: `-std=c++20`
  (and 23, 26) selects the level's predefined macros, which libc++'s
  headers key on, and the C++20 forms are read and, where they can
  become C, compiled -- concepts checked at instantiation, abbreviated
  templates, `<=>`, `if constexpr`, `using enum`; coroutines refused --
  then C++23's: `if consteval`, an explicit object parameter (the
  function's first, the object passed as declared; a lambda's is the
  closure, so a lambda recurses), `a[i, j]`, `auto(x)`, the delimited
  escapes, `#elifdef`; deducing `this` with a deduced type on a class's
  method refused, a member template. libc++'s containers await the
  forms their bodies use, which is the road ahead.
  `try` is refused
  by name; exceptions come last, if at all, since the safe part has no
  unwinding to offer. What the steps leave: the forms named in
  `CLAUDE.md` under each step.
* **Later — the objects layer's fate (below)**, and, on the LLVM module
  already here, ORC JIT: a macro running C at compile time.

Nothing is claimed before its GREEN line, the same rule as the neighbours.

## What happens to the objects-and-modules module already here

Deferred, by your call, until this design settles. It is a working
objects-and-modules layer over cocolog (`module/cicili.cicili`,
`test/objects.sh` GREEN). Two futures for it, to decide once M1 is real:

* **The compiler's authoring layer** — each pass an object, the AST an
  object graph — so the compiler is written in the objects it provides.
* **A model of the source language's structs and modules** — the checker's
  view of a Cicili `struct` and `module`, expressed as these objects.

Or it is set aside as a first mis-scope. It cost little and it taught the
cocolog findings in this repo's `CLAUDE.md`; it does not block anything.
