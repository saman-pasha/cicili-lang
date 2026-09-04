# cicili-cpp — a Safe Modern C compiler to LLVM, written on cocolog

**Status: design, for review. Nothing here is built yet except the M0 proof
below, which runs.**

cicili-cpp is a compiler for Cicili's language — Safe Modern C in
S-expressions — that lowers straight to **LLVM IR** and produces a native
object. It is **not a transpiler**: it does not emit C. Cicili (the existing
one) emits C text and hands it to a C compiler; cicili-cpp does the
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
| **cicili** | the LANGUAGE and its meaning: `func`, `struct`, `let`, `letin`, ownership, `maybe`/`either`, generics. Its `doc/DOC-C.md` and `doc/DOC-CPP.md` are the spec cicili-cpp compiles to the same meaning. And it is the language any NATIVE piece of cicili-cpp is written in — the LLVM binding and the driver are Cicili modules. | we read its docs and reuse its surface; we never edit its Common Lisp transpiler. cicili-cpp is a second, independent back end for the same language: LLVM where the original is C. |
| **cocolog** | the compiler's HOST. Every pass is cocolog clauses: the reader → an AST of terms, the type checker (unification), the ownership and lifetime checker (the "safe"), and the lowering to LLVM IR. Its DCG reads the surface; its store holds the symbol tables; the objects-and-modules module already here may structure the passes. | the compiler is a set of `.pl` files and, where a pass needs C speed, cocolog modules — all loaded through `COCOLOG_LIBRARY`, none of cocolog's own source changed. |
| **ZiguratIP** | through cocolog's store: a PERSISTENT compilation cache. A module's checked AST and its emitted IR, keyed by the hash of its source, live in the store, so a rebuild recompiles only what changed — cocolog's suspend-to-store nature applied to compilation. | reached only as cocolog's backing store, never directly. A design proposal, not required for M0–M2. |
| **LLVM** | the TARGET and the optimizer and the code generator. cicili-cpp emits LLVM IR; LLVM lowers it to native code. | reached first as textual IR + `clang` as assembler/linker (PROVEN, see M0), later — if wanted — as an in-memory `llvm-c` binding written as a Cicili cocolog module, for optimization passes and object emission without shelling out. |

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
                    clang module.ll  (LLVM backend: IR → native .o → link)
                                │
                             a binary
```

Each stage is cocolog clauses over terms. Lowering is a relation
`ir(+TypedForm, -Instrs)` with one clause per construct, the way Cicili has
one emit rule per clause — but the target is SSA IR, not C text, so the
checker's guarantees are carried into typed IR rather than re-proved by a C
compiler.

## The source surface: C, read by a DCG (decided)

The input is a **C/C++ source file**, read whole. `cicili(+File, -AST)`
acts like `phrase/2`: it reads the file entirely and, through a DCG, answers
its AST; `cicili/3` is the `phrase/3` form, answering what remained. The
grammars are `library/ccl_syntax.pl`: a lexer over character codes into
tokens that carry their line, and a parser over tokens into terms. The
preprocessor is not expanded; a `#` line is a node, and typedef names from
unseen headers are recognised from the tokens around them. This is M1, and
it is done (see below); the checker and the lowering take the AST from here.

## Milestones

* **M0 — the LLVM path runs. DONE.** `proof/forty2.ll`, a hand-written LLVM
  IR module, compiled by Apple's `clang` to a native Mach-O binary that
  prints a line and exits 42. No LLVM install: Apple clang consumes textual
  IR and drives the backend. This proves the target end of the pipeline on
  this machine before any of the compiler exists.
* **M1 — the reader. DONE.** `cicili/2,3` over two DCGs: C11 plus the GNU
  forms Cicili's emitted C carries (`__attribute__`, `typeof`, `({…})`,
  compound literals). `test/reader.sh`: 32 checks GREEN, one per construct,
  the error positions, and five real C files from the neighbours
  (`cicili/test/c/main.c`, `shared.c`, `macro.c`, `example/cimath.c`,
  `numpy_example.c`) read entirely.
* **M2 — a function to a binary.** cocolog clauses that lower a parsed
  `int main(void) { return 42; }` to `.ll`, driven through clang, exit 42 —
  end to end, the compiler's own IR. A gate that compiles and runs it.
* **M2b — the C core.** Integer and float types, arithmetic, locals, `if`,
  `while`, `for`, calls, `printf`. Each with a gate program that runs and
  checks its result.
* **M3 — structs and the safe part.** `struct`, members, `letin` scopes and
  deterministic cleanup lowered as IR, and the first ownership check: use
  after `move` is a compile error naming the form. This is where "Safe
  Modern C" stops being a tagline.
* **M4 — the cache.** The store keyed by source hash; a rebuild that touches
  one module recompiles one module.
* **Later — the llvm-c module**, optimization passes, and the objects layer's
  fate (below).

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
