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
module/cicili.cicili     the module: the C side (registration, ccl_version/1,
                         ccl_cocolog_version/1 over the engine's coco_version_text, THE LEXER,
                         ccl_lex_native/6 in Cicili, and ccl_host_arch/1, the arch it was compiled
                         on) and the Prolog half -- cicili_ast/2,3 (the reader's door) and the
                         objects layer
library/ccl_syntax.pl    the lexer (the DCG: the specification and the fallback) and the parser;
                         COMMITTED (library/*.so is not)
library/ccl_include.pl   #include: the inclusion path (the SDK's and LLVM's conventional
                         places, no tool run), resolution, the nested read (raw, else
                         through ccl_pp), .pl macro files, the cycle guard, the KB cache
library/ccl_pp.pl        the preprocessor, in cocolog (owner's rule: no clang, no LLVM
                         binary): ccl_pp_file/3 -- directives, conditionals, macros, the
                         built-ins, the target's predefined macros as pp_predef/3 facts;
                         ccl_pp_top/3, the user's file through it, its directives kept
library/include/         the compiler's own freestanding headers: stddef.h, stdarg.h,
                         stdbool.h, float.h, iso646.h, stdalign.h, stdnoreturn.h, limits.h,
                         and C23's stdckdint.h and stdbit.h
library/ccl_infer.pl     the macro facilities: ccl_type_of/2 and lookups over the symbol table
library/ccl_format.pl    format, print, println: the global macros, Rust's holes
library/ccl_ir.pl        cicili_ir/2: the lowering to LLVM IR text, one clause per construct
library/ccl_build.pl     cicili_compile/3 (the embedded LLVM, nothing else), cicili_link/3 (cc)
library/ccl_check.pl     the safe part: owners (own), move, the flow walk; run first by cicili_ir
library/ccl_cpp.pl       M6: the C++ forms desugared to that C before the check (ccl_cpp_units/2):
                         classes as structs, methods over this, constructors, destructors as defers
test/c/safe/             programs the check must REFUSE, each with the error its .expect names
bin/cicili               the command: clang's arguments, one cocolog run over ~/.cicili/KB (ccl_drive/2);
                         six forks, since each is a floor (the findings)
bin/cicili++             cicili for C++ (M5): the same, every input read as C++, in memory, linked by c++
test/cpp.pl, cpp.sh      the C++ reader's gate: 34 checks over test/cpp/*.cpp (the mangler's is c34), the six C++ files of Cicili's
                         test suite read whole, hello.cpp built through cicili++, and again from the summaries
test/libcxx.pl, libcxx.sh  the road to libc++: <vector>, <string>, <iostream>, <map>, <set>, <unordered_map>, <unordered_set>, <optional>, <memory>, <functional> and <tuple> flattened and read WHOLE, under a fresh HOME,
                         and at the levels: <set>, <map>, <unordered_map>, <unordered_set> at C++20, <optional>, <string> at C++23, <optional> at C++26;
                         test/cpp/run/std*.cpp are the standard streams built against libc++ and run: cout, endl, cin, getline, get, ws,
                         the extractors and inserters (stdistream, stdistream2, stdostream), the manipulators (stdmanip), and the
                         containers: stdvector, stdvectorown, stdvectorstring, stdstring, stdmap, stdmapstring, stdmapstring2, stdmultimap,
                         stdset, stdsetstring, stdset2, stdset3, stdunorderedmap, stdunorderedmapstring, stdunorderedmap2,
                         stdunorderedset, stdunorderedset2, stdoptional, stdoptionalstring, stdoptional2, stdnodehandle, stdmapinit, stdmapemplace, stdmapown,
                         stdsetlambda, stdunorderedhash, stdaggregate, stdstringops, stdctad, stdtuple, stdarray, refrank, the smart pointers (stduniqueptr, stdsharedptr, stdmemory),
                         the callables (stdfunction, stdbind, stdfunctional) with multibase and detectbase beside them,
                         and at the levels stdcontains (C++20), stdoptional3 (C++23),
                         stdoptionalref (C++26);
                         a fixture's input is NAME.stdin
test/census.pl, census.sh  a census of a header's constructs (test/census.sh '<vector>'), or of a flattened
                         file (cicili++ -E ... -o flat.cpp; sh test/census.sh flat.cpp): where the reader stops, with tokens
library/ccl_driver.pl    ccl_drive(+Inputs, +Options): the steps, diagnostics in clang's shape,
                         and the IR cache (dr_ir/3: a file's IR beside its unit in the store)
test/driver.sh           the command's gate; test/c/link and test/c/inc its fixtures
test/compile.pl          the compiler's gate: ONE process builds every test/c/run/*.c to a binary
                         and checks every test/c/safe/*.c is refused, over the user's store
test/compile.sh          runs it, then runs each binary and compares with NAME.expect
module/build.sh          CICILI=… COCOLOG=… sh module/build.sh  ->  library/cicili.so
module/ccl_llvm.cicili   the embedded LLVM: a cocolog module in Cicili over llvm-c; parse,
                         verify, target, passes, object (ccl_llvm_compile/3, ccl_llvm_check/2)
module/build-llvm.sh     LLVM=… sh module/build-llvm.sh  ->  library/ccl_llvm.so (Homebrew's LLVM)
proof/forty2.ll, run.sh  M0: LLVM IR through clang to a native binary, exit 42
test/config.sh           the neighbours and the library path, sourced by every gate
test/reader.pl           the reader's gate: a cocolog program, one clause per check (74),
                         one process over one fresh store, every header parsed once
test/reader.sh           runs it, and adds the check only a second process can make
test/c/                  the gate's fixtures: hello.c, rich.c, the macro, :=, pattern,
                         format and shorthand samples, the bad ones
test/objects.sh          the objects layer's gate
bench/btree/run.sh       the B-tree benchmark: cicili -O3, clang -O3 on the same algorithm, Rust's BTreeSet
bench/compile/run.sh     the compile-time benchmark: cicili++, clang++, rustc on a hello and the B-tree, at -O0
                         and -O3; cicili++'s first run (the init phase, summaries into a fresh HOME) apart
tutorials/NN-*.pl        the objects layer's lessons; goal `main', last line `done'
DESIGN.md                the architecture, the neighbours' roles, M0..M4
```

Build and prove, always in this order:

```sh
CICILI=~/Projects/GitHub/cicili COCOLOG=~/Projects/GitHub/cocolog sh module/build.sh
sh test/reader.sh
sh test/compile.sh
sh test/driver.sh
sh proof/run.sh
```

**`bin/cicili` takes clang's arguments** (owner's rule: no new flags to
learn): `-c -S -emit-llvm -fsyntax-only -o -O0..-Oz -I -l -L -shared -v
--version -ast-dump`; `-g -D -W -f` are accepted and ignored for now, and `-std` names the level of both languages (below).
It builds one Prolog options list and runs `ccl_drive/2` in one cocolog
process over `~/.cicili/KB` (`$CICILI_KB`, or `--no-kb` for `--local`); the run ends
`cicili: ok` or `cicili: N error(s)`, which the shell turns into the exit
status. A diagnostic is `file:line: error: what` (`dr_diag/3`, one clause per
error term; `once/1` around the report, since the callers' recovery fails
after it). The command puts every diagnostic on stderr, as clang;
`cicili: ...` and `unit(...)` lines on stdout.

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
**A pattern is written once** (owner's rule, 2026-09-06, on the DCG
predicates): where several predicates share a shape -- a level per
operator class, an answer cache per table, a token match per alternative
-- the shape is one predicate over a table or an argument, not a copy per
case (`ccl_binary/2` + `ccl_binop/2`, `ccl_cached/4`, `ccl_unary_/3`).

## How the reader is implemented, and why that way

`cicili_ast(+File, -AST)` mirrors `phrase/2`: the whole file or an error;
`cicili_ast/3` mirrors `phrase/3`, answering the tokens left. Two DCGs in
`library(ccl_syntax)`: `ccl_lex//2` over character codes -> tokens
`tok(Kind, Value, Line)`; `ccl_externals//2` over tokens -> the AST (its
vocabulary is the file's header). **The lexer that RUNS is native:**
`ccl_lex_native(+Text, +Line0, +Mode, +Lang, -Tokens, -Rest)` in
`module/cicili.cicili`, C written in Cicili, the DCG token for token (the
DCG ran at 0.15 ms a token, the floor of every read; the native one 600
times faster, 4 ms for 10,000 tokens). `ccl_tokens/3` and `ccl_lex_atom/4`
(an atom, from a line: the preprocessor's door) choose by `'$ccl_lexer'`,
decided once in `ccl_ensure_globals` by probing the predicate, so
`library(ccl_syntax)` alone still lexes through the DCG. The native one
builds `tok/3` with the engine's `coco_make` (behind `coco_m_machine`:
the SDK has no compound builder), keeps the keyword tables and the
punctuators in C, and `test/reader.pl`'s `k84` compares the two on
`test/c/lexer.c` (every token kind, number shape, escape, `#` line,
`#cocolog` block, in both modes and languages), the real fixtures and the
SDK's headers, `k85` that the native one is in use. A change to the
lexer's rules is made in BOTH, and k84 says when they part. (Its
vocabulary is the file's header; every statement carries its line as its
first argument, `expr(L, E)`, `if(L, C, T, E)`, `return(L, E)` ...).
**The expression grammar is one rule
for the ten binary levels** -- `ccl_binary(Min, E)`, precedence climbing
over the table `ccl_binop(Op, Level)`, `ccl_lor` at level 1 and
`ccl_shift` (a template argument's) at 8 -- and a unary, a primary or a
postfix operator is chosen by ONE look at the next token (`ccl_unary_(V,
K, E)`, `ccl_primary_(K, V, E)`, `ccl_postfix_p(V, A, E)`, the value or
the kind first so indexing finds the clause), the assignment's left side
read once as a conditional expression, the cast's type name tried once:
the level-per-class cascade and the try-every-alternative clauses cost
thirty token matches a token, this costs eight, and 2000 tokens parse in
0.1 s where they took 0.3 (owner's rule, 2026-09-06: in DCG predicates,
do not repeat a pattern across many predicates -- the ten levels were one
pattern ten times). Declarators are parsed inside out and folded onto the
base type by `ccl_mk_type/4`. The user's file goes through the preprocessor first
(`ccl_pp_top/3`, below): its conditional groups decided and its macros
expanded, while a `#define`, `#undef` or `#include` line comes out as a
token the parser reads as the `directive/2` or `include/3` node it always
made, so the items are what they were. A typedef name from a header the
reader has not seen is recognised from context (`name x`, `name *p` where an expression
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
(the preprocessor leaves a `#define` where it stood only when it is the
reader's, in a raw read). C++ is read in cicili++'s mode (below).

**An `#include` is read as it is met** (`library(ccl_include)`): the
parser calls `ccl_include/2` at the directive, which resolves the name on
the inclusion path (the including file's directory for a quoted name; then
`ccl_include_dir/1`, `$CICILI_INCLUDE`, and the toolchain's directories
from where the conventions put them, `ccl_toolchain_dirs/1`, no tool run,
cached in `'$ccl_incpath'`), reads the file raw with the same reader, and
only if raw does not read whole runs THAT file through the preprocessor
(`ccl_pp_parse/4`, below) and reads the result; `file(Path, raw|preprocessed, Unit)`,
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
An error in a macro carries both places: `here(File, Line, in_macro(Pred,
MacroFile))` on `macro_failed/2` and `macro_error/3` (`ccl_macro_file/2`
finds the file from `'$ccl_macro_files'`); every successful expansion is
`expansion(Line, Name, Args)` in `'$ccl_expansions'`, and the unit ends with
`'$expansions'(List)` when there were any, which the driver reads
(`dr_remember_expansions/1`) to add `note: expanded from macro` under a
diagnostic on that line. The command's output filter passes `: note: `
lines; `ccl_drive/2` is `once/1`, since cocolog's query loop asks for a
second answer and a stray choicepoint reprints everything.
The file is loaded with `ensure_loaded/1` (a reload replaces; under the
store its clauses stay in the process) and its heads are found by splitting
its text into clauses and `term_to_atom/2` on each (`ccl_pl_clauses/2`),
because `current_predicate/1` does not list consulted clauses. The registry
is the global `'$ccl_macros'`, saved and restored with the others.

**The symbol table is kept while parsing**, for the macros: `'$ccl_scope'`
(frames of Name-Type, innermost first; pushed by `ccl_compound` and at a
function's parameters, only when `{` is next), `'$ccl_typedefs'`
(Name-Type), `'$ccl_tags'` (Tag-Members; enumerators declared as int).
`ccl_note_item/1` feeds them one item at a time as the grammar produces
them; a whole unit tree (an included unit, the checker's and the lowering's
rebuild) goes through the BULK noter `ccl_items_note/1`, which collects
into difference lists and sets each table once -- per-item `nb_setval/2`
copies the whole list and was quadratic over the headers' 40k items.
**The file scope is a global of its own**, `'$ccl_gscope'` (the headers'
hundreds of names), and `'$ccl_scope'` holds only the OPEN frames,
`[]` at file scope: `nb_getval/2` copies what it answers, so a local
declared (`ccl_declare/2`) or a name looked up (`ccl_declared/2`, the open
frames first, then `ccl_gdeclared/2`) never copies the file scope;
`ccl_scope/1` still answers every frame, the file scope's last, for the
check's frame arithmetic, `ccl_locals/1` the open ones; `ccl_scope_add/1`
puts a list of declarations where `ccl_declare` would. **Answers are
cached** through ONE predicate, `ccl_cached(Cache, Key, Value, Goal)` in
`ccl_infer` -- a small global of Key-Value pairs, a copy of a dozen pairs
being microseconds -- for `ccl_typedef_of/2`, `ccl_tag/2`, a typedef's
full resolution (`ccl_resolve_type`, the chain walked once), a struct's
layout (`ccl_members_layout/4`), the file scope's names and `ir_type/2`;
`ccl_tables_changed/0` empties every cache and is called wherever a table
is written (the noters, the summaries, `ccl_with_file`'s restore). **A cached predicate is not
re-entrant**: `ccl_cached/4` reads the cache ONCE before it calls the goal and writes the list
back afterwards, so a NESTED ask on the same cache from inside that goal has its entry restored
away by the outer write -- harmless, since it costs only a recomputation, but a predicate that
asks its own cache while computing an entry takes the `_nocache' form, or does not ask at all:
`ccl_empty_layout' was written inside `ccl_members_layout_' that way and now answers from the
members alone (`ccl_no_data_members'), which is both re-entrant-safe and the right question. **A
cache keyed by a NAME whose values may be large -- a tag's members, a
typedef's resolution, a function's type -- is a global per name**
(`ccl_cached_named/4`: `'$ccl_tag:node'`, `'$ccl_r:size_t'`, `'$ccl_g:f'`,
`'$ck_oa:node'`, each prefix with a `names` index of atoms), because
`nb_getval/2` copies what it answers and a list of every pair found so far
would be copied at every lookup -- the lowering's scan of the headers'
92 tags would have put their member lists into the tag cache and every
later `ccl_tag/2` would have copied them all. `ck_has_own_array/1` is
answered per tag the same way (the lowering asks it of every struct in
the symbol table for the drains). Where a resolution can be answered by
the term's shape it is: `ccl_resolve_type/2`'s first clause takes a plain
specifier list, `ck_own_array_type/1` an array, a pointer or a plain type
in one head each.
Measured on the B-tree: the check 0.28 -> 0.07 s, the lowering 0.7 ->
0.4 s -> 0.21 s. The second half of the lowering's gain was three
things found by ranking every predicate's calls (an instrumented copy of
the library, below): `ir_join/3`, the module's text from its lines,
walked the codes of 1700 lines with `append/3` -- 0.1 s, a quarter of the
lowering; it is `atomic_list_concat/3` now (the walk was for cocolog
before 1.1.0, whose builtin died past 8 KB). `ccl_resolve_type/2`, asked
12,000 times, is chosen by its functor -- `base` to `ccl_resolve_base/3`,
whose first clause takes a plain specifier list in one try, anything else
itself -- where it tried the typedef, struct and union heads first every
time. `ir_abi/2` walked a struct's leaves and eightbytes at every call
site; cached. What is left is 50,000 predicate calls at cocolog's 5 µs a
call: `ir_expr/4` carries the LLVM type beside the C type now (above),
which took a tenth of the calls out; the rest is the inference.
Never `memberchk` on the open accumulator: it binds the tail (the
enumerators keep a closed list of their own). `library(ccl_infer)` reads them: `ccl_type_of/2` with the
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

**`#cocolog` ... `#end` is a macro file in place** (owner's rule): the
lexer, on a `#` line whose text is `cocolog`, takes every line up to the
`#end` line (or the file's end) raw into one `tok(cocolog, Text, L)`
(`ccl_cocolog_body//3`); the parser's `ccl_external` makes it the item
`cocolog(L, Text)` and calls `ccl_cocolog_block/2` (in `ccl_include`),
which writes the text to `tmp_file(cocolog)-L.pl` and runs
`ccl_load_macros/2` on it, the same door as `#include "m.pl"`: the heads
found by `ccl_pl_clauses/2`, `ensure_loaded/1`, the registry
`'$ccl_macros'`. A macro's error names that temporary file. The item
carries the text into the store (over the clause budget the file stays
uncached); on a cache hit nothing is re-loaded, the expansion having
happened when the unit was read. Two `k72` clauses had hidden the tie
check in `test/reader.pl` -- one clause per check, one NUMBER per check.

**`x <*> y` is the tie operator** (owner's rule, and the spelling): x lives
within y. The lexer has `<*>` as a punctuator (no C has it: `<*>` needs the
`>` right after the `*`); `ccl_tie//2` reads it after a declarator in
`ccl_init_declarator`, `ccl_member_declarator`, `ccl_param` and the
function definition (before `{`), `ccl_tie_name//1` after the `:=` forms
(`ccl_infer_decl/5`); `ccl_add_tie/3` (in `ccl_infer`) puts `tie(Y)` in
the OUTERMOST qualifier list of the type, through an array to its element
and through a function to its result, and `ccl_tie_of/2` reads it back.
Nothing in the lowering or the layout reads a qualifier, so a tie costs
them nothing.

**The C++ mode (M5, `bin/cicili++`):** `'$ccl_lang'` is c or cpp, set
from the file's extension by `ccl_read_file` (`.cpp .cc .cxx .C .hpp .hh
.hxx`) or forced by the driver's `lang(cpp)` (`'$ccl_lang_forced'`, which
`cicili++` sets through `CICILI_LANG=cpp`). Every C++ rule in
`ccl_syntax.pl` is guarded by `ccl_cpp` (`{ ccl_lang(cpp) }`) and placed
BEFORE the C clause it extends, so a .c reads as it did; the keywords are
mode-dependent (`ccl_keyword/1`: C's, plus `ccl_cpp_keyword/1` in cpp;
`override` and `final` stay identifiers), and `::` lexes only in cpp. The
vocabulary is README's table. Names: `ccl_qname//3` reads `::a::b<args>::c`
into an atom, `tmpl(N, Args)` or `scoped(Path, Last)` (`global` first for
a leading `::`), taking `N <` as a template-id when N is a known template
(`'$ccl_templates'`, seeded with the STL's, grown by every `template`
item) or, in a type context, when the arguments read as such and end
before a declarator (`ccl_targs_ahead/2`, a scan to the matching `>`,
`>>` closing two: `ccl_tclose/2` leaves one). In `ccl_specs` a compound
qualified name is a type (`ccl_cpp_type//3`), a plain one is left to the
C heuristics; in a block it must be followed by what a declarator starts
with (`std::cout << x` is an expression). A class's name joins the global
env at its declaration (`ccl_add_env/1`), its body parses under
`'$ccl_class'` so a constructor is known by the class's own name. A LESSON
that cost an evening: `( A, ! ; B )` inside a DCG body cuts the WHOLE
CLAUSE, so it is only for a choice that decides the clause -- `( inline,
! ; [] )` before `namespace` killed every inline function, and a
qualifier hook ending in `!` in the function-definition rule killed every
prototype at file scope. An optional word is `( ccl_kw(inline) ; [] )`,
no cut. The C++ items reach the bulk noter (`ccl_collect_item`: extern_c,
namespace by its bare name, template; `class` as a tag; `param/3`; refs)
and `ccl_note_item`. A C++ library header (`system(_)` or `next(_)` spec,
kind kept in `'$ccl_inc_kind'`) is flattened by the preprocessor
(`ccl_pp_parse/4`) and read once (`ccl_read_unit`), never raw -- raw, `<sstream>`'s
hundreds of headers each failed and got preprocessed in turn: ten
minutes -- and `#include_next` looks past the including file's directory
(`ccl_resolve_include(next(_), …)`). **The summary cache:** a flattened
library header is summarized to `~/.cicili/cpp/<name>-<fold>.sum`
(`ccl_sum_file/2`, two folds of the path), one term per line: `sum(Path,
key(ReaderVersion, cpp))` and a `dep(File, Time)` per file the
preprocessor pulled, then `decl(N, T)`, `typedef(N, T)`, `tag(Tag,
Ms)` (bodies dropped by `ccl_sum_slim/2`), `enum(N, V)`, `tname(N)` (the
names the parser's Env needs: typedefs and tags), `template(N)` -- what
`ccl_collect_items` and `ccl_items_typedefs` give (`ccl_sum_write/4`). A
valid summary (`ccl_sum_valid/1`: the version, every dep's time) makes the
include node `include(L, Spec, summary(F))`, and each consumer reads it
where it would walk a unit: `ccl_include_typedefs` (the Env),
`ccl_include_scope` → `ccl_sum_note/1` (the four tables, the templates,
the global env), `ccl_collect_item` (the bulk rebuild before the check
and the lowering), `dr_items_deps` (the IR signature). The driver reads
`.cpp .cc .cxx .C` through `dr_c`, skips the check and the lowering under
`-fsyntax-only` in cpp mode (M6's), and `ccl_link` uses `c++`. `cicili++`
runs `--no-kb`: see the findings.

**C23 (`-std=c23`), the C side's own level (0.57).** C's level is not C++'s
-- 17 and 23 are both languages' -- so it is a global of its own,
`'$ccl_c_std'` (`cstd(N)` in the driver's options, `-std=c23|gnu23|c2x|gnu2x`;
c17, c11 and c99 accepted, c89 and c90 refused), read by `ccl_c_std/1` and
asked in the grammar as `ccl_c23//0` (and `ccl_c_or_cpp//0` for a form C23
took from C++, read in C++ at every level). THE PREPROCESSOR answers the
level's macros first (`pp_c_std_table(S, c23)` before C17's table, as the
C++ levels already had it): `__STDC_VERSION__` is 202311L there and
201710L without, beside the `__STDC_*_H__` and `__STDC_EMBED_*` facts.
**THE FORMS ARE READ AT THE LEVEL, not lexed at it:** the keyword tables
are the LANGUAGE's, not the level's, and they are the native lexer's too
(k84 compares the two token for token), so C23's new keywords arrive as
the identifiers C17 has and the grammar takes them at `-std=c23` --
`bool` a type specifier, `true`, `false` and `nullptr` primaries,
`constexpr` an object's `const`, `thread_local` a storage word,
`alignas(...)` an attribute, `typeof_unqual` beside `typeof`. A C23
`constexpr` object is a CONSTANT: its name joins the enumerators' table
(`ccl_note_constants/2`, the same `'$ccl_enums'`), so an array's bound and
a static assertion fold it. `static_assert(e)` and `static_assert(e,
"msg")` are read in C as C++ already read them (`_Static_assert` too, C11's
spelling), at file scope and in a block, and A STATIC ASSERTION IS NOW
CHECKED where it folds -- IN C ONLY, since a C++ template may write
`static_assert(false, ...)` in a branch no instantiation takes, which
C++23 allows and a reader-time check would refuse. `[[attributes]]`, an
enum's underlying type (`enum E : unsigned char`) and `auto` deducing are
C++'s rules read in C from C23 (`ccl_c_or_cpp`). AND `typeof` IS RESOLVED:
nothing resolved it before (`ccl_resolve_base([typeof(X)], ...)`, a type
taken as it is and an expression through `ccl_type_of`), so a `typeof`
reached the lowering as a specifier it could not take; `typeof(K)` of an
OBJECT is its expression, where C's heuristics took a lone identifier for
a typedef name. **BOTH LEXERS** read C23's binary literal `0b1011` (which
is C++14's too) and the DIGIT SEPARATOR `1'000'000` in every scan --
decimal, hex, binary, a fraction and an exponent -- the native one
dropping it from the value it accumulates and from the text it spells for
`strtod` (`ccl_lx_puts_num`); the PP-NUMBER takes it as well
(`ccl_pp_number//1`, `ccl_lx_pp_number`), without which the preprocessor
read `1'000'` as a character literal and the line did not lex. Reader
version 40. Gated by `test/c/run/c23.c` (built at the level: a fixture's
`NAME.std` names it, as `NAME.flags` does in the C++ gate) and the
reader's `k87` and `k88`, with the new numbers in `test/c/lexer.c` under
`k84`. The rest -- `#embed`, `_BitInt(N)` lowered, `__VA_OPT__`, `#warning`, `__has_c_attribute`, `unreachable()`, `nullptr_t`, `typeof_unqual`, the `wb` suffix, the decimal types refused by name -- is 0.93's, below; `%b` is the C library's business.

**M6, the check and the lowering of the C++ forms, in steps; the first
(0.32): C++ that is C with names.** A namespace FLATTENS to bare names
(the noters already did so: `namespace`, `extern_c` items are their
items; `ir_item` walks them; `using` is nothing; `scoped(_, N)` in an
expression is `id(N)` in the check, the inference and the lowering;
two namespaces declaring one name collide, unhandled). `bool` is a byte
(`ir_base`, `ccl_basic_size`, rank 0), a conversion TO bool an `icmp ne`
+ `zext` (`ir_to_bool`, first in `ir_convert/6`), `bool(true)` /
`nullptr` constants and global initializers; `ccast(_, T, E)` is
`cast(T, E)`; `enum_class(Tag, Es)` an enum (`ir_base`, the bulk noter's
`ccl_collect_spec` collects it -- it did not, and `Color c` failed as
`typedef('Color')`), and a C++ TAG's name resolves as a type
(`ccl_resolve_base([typedef(N)])` in cpp mode through `ccl_tag_type/4`,
told by the members' shape: enumerators, plain members, a class's).
`for_each(L, Decl, Range, S)` over an ARRAY is rewritten ONCE for both
passes, `ccl_for_each_as_for/2` in `ccl_infer`: `for (int i = 0; i < N;
i++) { T x = xs[i]; S }`, an `auto &` a `ref` to the element; a range
that is not an array is `range_for_over_non_array`. **A reference is a
pointer bound once:** the reader gives `ref(Q, T)` / `rref(Q, T)`;
`ccl_type_of` DECAYS it (`ccl_unref/2` in the id, call, member, arrow,
index, deref clauses), `ir_type_` makes it `ptr`, a local's slot holds
the address (`ir_locals`: `ir_ref_of/2` of the initializer -- an lvalue
form's address, or a call's reference result as it is), a use of the name
loads that address first (`ir_ref_slot/4` in `ir_expr(id)` and
`ir_lval(id)`), a reference parameter takes the argument's address
(`ir_args_`), a reference result returns one (`ir_stmt(return)`,
`ir_lval(call)` for `alias(y) = ...`) and is loaded through where a value
is asked (`ir_expr(call)`). The CHECK sees the pointer: `ck_ref_params/2`
and `ck_ref_decl/5` map `ref` to `ptr` -- a parameter a borrow, a local
bound to an lvalue a borrow of its address (`addr(Init)`: an anchor, an
array's element), one bound to a call not followed -- and keep the
function's reference names in `'$ck_refs'`, since a use of such a name
is a use of the referent: `x = v` is `*x = v` (the assign clause first),
`&x` the pointer held, the value borrows only when the referent's type
carries a pointer, and `return x` from a reference-returning function
(`'$ck_ret'`) is checked as a borrow out (`borrow_escapes` for a
reference to a local, `ck_no_escape`). `new T` is
`(T *) malloc(sizeof(T))`, `new T(v)` stores v through a statement
expression, `new T[n]` `malloc(n * sizeof(T))`, `delete p` / `delete[]
p` `free(p)` (`ir_new/3`; `malloc` and `free` declared by
`ir_cpp_prelude` when the file did not, before the check, which consumes
at a delete as at a free and takes `new` as a fresh value). A form of a
later step is REFUSED BY NAME, never dropped: `class(N)` at its
declaration and where a variable has the type, `member_of_class(N)`,
`operator(Op)`, `constructor`, `destructor`, `method(N)`, `template`,
`lambda`, `throw`, `try` (the check's last `ck_stmt` clause throws the
lowering's `not_lowered(F)` with its place); the noters skip a member
defined out of its class (`Counter::made`, `Shape::scale`: a compound
name), which crashed `atom_concat` before. Gated by `test/cpp.sh`:
`test/cpp/run/names.cpp` and `loops.cpp` built through `cicili++`, run
against their `.expect`, and `control.cpp`, `classes.cpp`,
`templates.cpp` refused with `try`, `virtual`, `template`. Not done: two
namespaces with one name, a reference member, a reference to a class,
`auto` the reader could not infer (`ir_fail(auto)`).

**M6's second step (0.33): classes, DESUGARED to that C** by
`library/ccl_cpp.pl`, one typed rewrite of the units that `ccl_ir_units`
runs in cpp mode between the first symbol-table build and the check
(`ccl_cpp_units/2`; the table is built again from what comes out, since
the classes became structs). The design rule: every C++ form of the
steps to come is a rewrite to the C the check and the lowering have,
never new lowering, so the safe part reads C++ programs as it reads C.
`cpp_register_units/1` collects `'$cpp_classes'` (`C-cls(Base, Data,
Members, Statics, Defaults)`) from the `declare(_, base(_, [class(...)]))`
items, refusing `virtual(C)` and `multiple_inheritance(C)`, and DECLARES
every method, constructor, destructor, static member and free operator
in the table under its mangled name at once, so a rewritten call has a
type while the walk goes on. Names: `C.m.k` (k the arity), a
constructor `C.C.k`, the destructor `C.dtor.0`, an operator by its word
(`cpp_op_word/2`: `C.op.plus_assign.1`, a free one `op.plus.2`), a
static member `C.N` -- dots only, so LLVM takes them unquoted and no C
name collides. A class item becomes `declare(L, base(Q, [struct(C,
Data)]))` with the base's sub-object the first member, `'$base'`, then
`extern` declarations of the statics, then a function per method (`this`
the first parameter, `const C *` for a const method), per constructor
(void; its body the base's constructor over `&this->$base`, then every
data member from its initializer, else its `default_init`, in the
members' order, then the body), and the destructor; a class with no
constructor but defaults or a constructed base gets `C.C.0`
(`cpp_implicit_ctor`). Out of class: `int Counter::made = 0` is the
global `Counter.made`, `Shape::scale` and `Counter::~Counter`
(`dtor_def/4`) the functions. Bodies are walked with the symbol table's
scopes kept as the check keeps them (`cpp_method_body`, `cpp_stmt`,
`cpp_expr`, bottom up), so `ccl_type_of/2` tells a class-typed operand:
inside a method an unqualified data member is `this->n`, an inherited
one `(*this).$base.n` (`cpp_data_member/3` gives the hops), a static
`id('C.N')`; `o.m(a)` is `C.m.k(&o, a)` and `p->m(a)` `C.m.k(p, a)` with
the default arguments filled (`'$cpp_defaults'`, by mangled name), an
inherited method over the base sub-object's address, an unqualified
`m(a)` inside a method over `this`; `Counter(v)` and the functional cast
build a temporary in a statement expression; `o += v`, `o[i]`, `a + b`
go to the class's member operator, else a free one registered
(`'$cpp_free_ops'`), else stay the form. A local of a class with a
constructor becomes a `'$splice'` of the declaration, the constructor
call over its address (from `ctor(As)`, `init(Items)`, no initializer,
or a single value not of the class -- a value of the class is COPIED,
`Counter e = c + d`), and, when the class has a destructor, a
`defer(L, [], block([expr(L, call(id('C.dtor.0'), [addr(id(N))]))]))`:
the existing defer machinery runs it at every exit of the scope, last
declared first, as C++ does. `new C(As)` is a statement expression
constructing into `new(T, [])`'s block (the check: a loose pointer out,
as before), `delete p` of a class with a destructor
`comma(call(dtor, [p]), delete(p))` (a temporary for a non-name, since
the check would see a borrow freed). `ccl_members_of/2` answers a
class's data members (the raw `class(...)` spec, before the rewrite;
statics excluded) so member types resolve during the walk. Gated by
`test/cpp/run/counter.cpp`: two classes with a base, initializers,
defaults, a static, `operator+=`, `operator[]`, a free `operator+`, a
temporary returned by value, `new`/`delete`, destructors counted -- the
numbers agree with clang++'s.

**M6's third step (0.34): `virtual`, the same way.** The registry's
`cls/6` carries the class's SLOTS (`cpp_slots/4`: the base's, then each
own virtual method -- or one overriding a base slot, `override` being
implicit -- appended by name and arity, `'$dtor'` for a virtual
destructor). The class that introduces slots over a non-polymorphic base
(or none) gets `'$vptr'` as its first data member (after `'$base'`), a
pointer to `struct 'C.vt'`, which `cpp_vt_struct` declares before the
class's struct: a function-pointer member per slot over the OWNER's
`this` type (`cpp_vt_owner/2`: the first polymorphic class up the
chain). After the functions comes the table, `static struct 'C.vt'
'C.vtable' = { the most derived implementation per slot }`
(`cpp_vtable`, `cpp_slot_impl/4`: the class's own method, else the
base's; the destructor slot `cpp_dtor/2`, which answers the base's when
the class has none, since the base sits at offset 0). Every constructor,
an implicit one included (`cpp_implicit_ctor_needed` counts a polymorphic
class), stores `this->$vptr = (struct Owner.vt *) &C.vtable` right after
the base's constructor (`cpp_vptr_store/3`; the walk finds the hops to
the member). A destructor's body ends with the base's destructor over
`&this->$base` (`cpp_dtor_body`). A call `p->m(a)` whose method has a
slot is `p->$vptr->m(p, a)` (`cpp_dispatch/5`); `o.m(a)` dispatches only
when `o` is a reference or `*p` (`cpp_static_object/1`: a named value
or a member of one has its static type); an unqualified `m(a)` inside a
method dispatches through `this`; `delete p` with a virtual destructor
destroys through the slot (`cpp_destroy`). Single inheritance keeps the
base at offset 0, so `this` is never adjusted. The lowering's constants
take a function's address and a global's (`ir_gconst(id(F))`,
`ir_gconst(addr(id(G)))`), and the check counts `&global` as static, so
the store in the constructor is no fresh value. Gated by
`test/cpp/run/shapes.cpp` (two overrides, one inherited slot, a virtual
destructor chained, a static counted) and the reader's `classes.cpp`
built and run (exit 34). Not done: a pure virtual method (refused,
`pure_virtual`), a member of class type with a constructor, an array or
a global of a class with a constructor, a temporary's destructor,
`operator=` and copy constructors (a struct copies), nested classes,
`static` methods, `friend`, access control (ignored), a method called
before the class is complete, `dynamic_cast`, RTTI.

**M6's fourth step (0.35): templates, instantiated on use.** The
registry keeps `'$cpp_templates'` (`Name-tmpl(TParams, Item)`, from the
`template(L, TParams, Item)` items, a function or a class), the
instances made `'$cpp_instances'` (`Name-Template`) and their items
`'$cpp_instance_items'`, which `cpp_flush_instances/2` appends to the
unit's items at its end (walking an instance may make more). EVERY TYPE
the walk meets goes through `cpp_type/2` -- a declaration's, a
parameter's, a member's, a cast's, `sizeof`'s, `new`'s, a typedef's --
and a template-id there, `typedef(tmpl(N, Args))` or the scoped form,
becomes its instance's name: `cpp_instantiate_class/3` binds the
parameters (`cpp_bind_targs`, defaults filled), names the instance
`N.key.key` (`cpp_instance_name`, `cpp_type_key/2`: `Buf.int.4`,
`max2.double`, a pointer `int_p`), and, once, substitutes the bindings
through the item (`cpp_subst/3`: a type parameter's `typedef` becomes
the argument with the qualifiers kept, a non-type parameter's `id` the
value), registers the class (`cpp_register_class`, so its members'
types go through the hook too: nested instantiation) and desugars it
like a class written out -- under `cpp_isolated/1`, the symbol table's
open scopes set aside so the instance's walk sees no local of the
function that met it and its declarations go to the file scope. A call
`max2<int>(1, 2)` (the reader's `call(tmpl(F, TArgs), As)`) or `max2(3,
4)` of a function template goes to `cpp_instantiate_function/4`: the
type arguments explicit, then DEDUCED from the arguments' types
(`cpp_match/5`: a type parameter's `typedef` takes the argument's type
decayed, through `ptr`, `ref`, `rref`), then defaulted, else
`cannot_deduce(P)`; the instance is declared in the table and walked
like a function. The table built before the walk holds a template-id
RAW (`Ints` = `typedef(tmpl(Buf, ...))`): `ccl_resolve_base` leaves a
compound typedef name as it is (an `atom(N)` guard before the cached
lookup, which would have `atom_concat`ed it), `cpp_class_of_type_`
instantiates such a one on sight, and a rewritten `typedef` item is
noted at once (`ccl_note_typedefs`). The template item itself is
nothing in the output; a template from a header's summary has no body
and is refused, `template_without_body(N)`. Gated by
`test/cpp/run/templ.cpp` (a class template with an array member, a
constructor and methods, instantiated twice and through an alias, a
function template deduced and explicit) and the reader's
`templates.cpp` built and run (exit 10; its `std::vector` is its own
namespace's). Not done: partial and explicit specializations, a
non-type argument deduced, `template` inside a class, a template
template parameter, `typename T::x`, SFINAE.

**M6's fifth step (0.36): lambdas, a class of the captures.** The
reader gives `lambda(Caps, Params, Ret | none, Body)` with `cap(val, N)`,
`cap(ref, N)`, `cap(default, '=' | '&')`, `cap(this)`. `cpp_lambda/6`
makes the class `lambda.K` (`'$cpp_lambdas'` counts): a member per
capture -- by value the local's type (decayed), by reference
`ref([], T)` -- and the method `operator()` over the parameters with
the body as written, registered and desugared like a class written out
under `cpp_isolated` (so inside the body the captured names are
members, `this->k`, and an enclosing local NOT captured is undeclared,
as C++ has it); the expression becomes `compound_lit(base([],
[typedef('lambda.K')]), init([...]))` of the captures' values, `&t` for
a reference. A default capture takes every enclosing local the body
names (`cpp_lambda_free/3`: the body's `id`s minus its parameters and
its own declarations, kept when `cpp_local`); the result type is the
first `return`'s, typed under the parameters (`cpp_lambda_ret/3`), or
void. `auto f = <lambda>` -- `auto` the reader could not infer -- takes
the initializer's type in `cpp_decl_pieces` (the initializer rewritten
once; any `auto` does: a method's or a template's result). A call `f(a)`
of a local whose class has `operator()` is `lambda.K.op.call.n(&f, a)`
(the first `cpp_call` clause), which also serves a function template's
parameter of the closure's type: `apply(addk, 1)` copies the closure
(its reference member still the caller's `t`). THE LOWERING reads a
REFERENCE MEMBER through (`ir_ref_member/4` in `ir_lval(member)` and
`ir_lval(arrow)`: the slot's address loaded, then the referent), while
an initializer stores the address as any pointer; the check's
`ccl_type_of` already unrefs a member's type. Gated by
`test/cpp/run/lambdas.cpp`. Not done: `[this]` (refused,
`capture_this`), a lambda inside a template's body before its
instantiation, `mutable` (every capture is mutable), a lambda's
destructor, `std::function`.

**M6's sixth step (0.37): a real program under the safe part** --
`test/cpp/run/btree.cpp`, the B-tree of `bench/btree` as a class over
`own` pointers (`own node *root`, the nodes' `own node *C[nc]`), a
constructor, a destructor, const methods, `own BTree *t = new BTree()`
and `delete t`; it prints the C version's numbers. What it taught the
check, THE OBJECT'S LIFECYCLE: the desugaring marks a constructor's
`this` `ptr([], base([fresh], [typedef(C)]))` and a destructor's
`[dying]` (`cpp_this_type/4`, in the function, its declaration and the
table's `$dtor` slot alike), and the check reads the marks
(`ck_this_marker/2`): under `fresh` the pointee's own fields start
UNSET (`ck_param_owners`: garbage, not complete), so `root = new_leaf()`
is no overwrite, and `ck_complete_owners` still demands them live or
null at every return -- a constructor that forgets an own field is
refused; under `dying` the fields are exempt from that demand
(`'$ck_dying_fields'`), so `~BTree() { free(root); }` passes, and the
CALLER of a destructor -- `delete p` as `comma(dtor(p), free(p))`, a
local's defer over `&c` -- takes the object's own fields as moved
(`ck_args_`: `ck_dying_param/2`, `ck_arg_base/2`, `ck_own_under`), so the
free that follows finds nothing leaked. `new T` of a struct without a
constructor is malloc's bytes to the check (`ck_alloc_mode`: `new(_,
[])`, `new_array`, and through a `cast`), `new C(args)` a complete
object (its constructor was made to be). `bench/btree/btree_cicili.c`
built with `-O1` at 20000 keys gives the expectation. Not done: a
constructor that delegates, `this` handed out of a constructor, a
destructor's effect on a struct member of class type, arrays of
objects, `static` methods (a `this` is passed and unused).

**M6's seventh to ninth steps (0.38-0.40, redone in 0.41 over the
program's own classes -- THE OWNER'S RULE: nothing of the standard
library is the compiler's own; the C freestanding headers were the one
exception, on the C side; the C++ side compiles against libc++ as it
is, C++17 the baseline then the next majors, and libc++'s containers
await the forms their bodies use).** What the three steps built stays,
exercised by `test/cpp/run/bag.h` (a `Name` over an `own char *` and a
`Bag<T>` over an `own T *`, a LOCAL header read whole) and `bag.cpp`:
(1) a header the program wrote gives its classes and templates to
every unit that includes it (`cpp_register_header/1` from the include
node's raw unit, `file(_, _, unit(Is))`; its class, struct and enum
class NAMES join the includer's Env, `ccl_items_typedefs` in cpp mode,
so `Name &s` parses): a class registered and EMITTED as an instance
is, its functions `linkonce` (`cpp_linkonce/2` in
`cpp_add_instance_items`; the lowering spells `define linkonce_odr`),
so two units link; a library header's summary keeps names only, and a
template of libc++'s is refused, `template_without_body(N)`. A
range-for over an object whose class has `size()` and `operator[]` is
rewritten by the desugaring (`cpp_stmt(for_each)`) into the `for` over
an index, the element type the operator's result unreferenced; the
range must be an lvalue form. `cpp_subst` turns `sizeof(id(T))` (read
as an expression while T was only a name) into `sizeof_type` of the
argument and `T(x)` into a functional cast; a scoped type name
flattens in the type hook (`typedef(scoped([std], string))` is
`typedef(string)`); a class's STRUCT form is in the tags table from
its registration (`cpp_register_class` notes it), so `this->d[i]`'s
element has a type while the instance's own methods are walked. (2)
OVERLOADS BY TYPE: a name carries its parameters' type keys
(`cpp_params_key/2`: `Name.op.plus_assign.char`,
`Name.op.plus_assign.char_p`, `Counter.add.int`, a nullary `C.m.0`),
and `cpp_method/5` and `cpp_ctor/3` take the ARGUMENTS, keep the
overloads whose arity fits and pick the one whose parameter types fit
the arguments' best (`cpp_pick/3`, `cpp_arg_fit/3`: the same class 3,
both pointers 2, both arithmetic 2, an unknown type 1). THE RULE A
DESTRUCTOR BRINGS: a class with one is never copied, since two owners
of one buffer free it twice and the check cannot see the destructor's
free -- refused as `copy_of_a_class_with_destructor(C)` (a local
initialized from an lvalue of the class),
`assignment_to_a_class_with_destructor(C)` (`s = t`, unless the right
side is a `move(...)` into the holder's fresh slot),
`class_with_destructor_by_value(C)` (an lvalue handed to a by-value
parameter, `cpp_no_copies/1` after every call),
`return_of_a_class_with_destructor(C)` (an lvalue returned by value;
`'$cpp_ret'` holds the function's result type through
`cpp_method_body/5`; a temporary, a call's result, is fine and moves).
`ccl_members_of` of a raw `class(...)` spec keeps pointer-typed
members; a tag noted TWICE -- the raw class from an include, the
desugared struct from the emitted items -- resolves to the struct
(`ccl_tag_type` through `ccl_tag_struct/2`, cached under `'$ccl_ts:'`);
a parameter's own field RETURNED AS A PLAIN POINTER (`c_str`) is a
borrow out, the caller's still, not a move (`ck_consume_or_use`, first
clause). (3) MOVE SEMANTICS: `std::move(x)` is Cicili's `move(x)`
(`cpp_call`: `scoped([std], move)`, a semantic mapping, no header
needed); the LOWERING's `move(E)` of a struct lvalue whose type holds
owners loads the value and stores null into every own pointer field of
the source, nested structs recursively (`ir_null_own_fields/2`,
`ir_has_own_fields/1`), so the source's destructor, run at its scope's
end, frees nothing; the CHECK's `move(E)` of a struct by value with
owners moves its fields out (`ck_expr(move)`, first clause), and
`ck_kind(move(E))` gives such a value its own kind; a struct with
owners handed BY VALUE hands them to the callee's copy (the check's
rule in the safe part above); `move(x)` of a value without owners is
`x` (`cpp_holds_owners/1`: a template's `T` an int); after a call with
a `fresh` parameter the argument's own fields are LIVE
(`ck_fresh_param/2` in `ck_args_`, the constructor's contract read back
by the caller), so `std::move(a)` after `Name a = "alpha"` finds fields
to move; a constructor's or destructor's argument may be a member's
address (`ck_arg_base(addr(E), K)` takes any path). AN EXPLICIT
DESTRUCTOR CALL, `x.~T()` and `p->~T()`, is read as `call(member(x,
dtor(T)), [])` (`ccl_postfix_p`, cpp only) and desugared (the first
`cpp_call` clauses) to the class's destructor over its address,
nothing for a class without one -- what a container of the program's
own writes where its elements leave (`Bag::pop`, `~Bag`); `d[n] =
move(x)` is how it stores. A moved-from object keeps its plain fields
(only owners are nulled): its state is unspecified, as C++ has it.
Reader version 31 (for `.~T()`). Gated by `test/cpp/run/bag.cpp`, run
under `leaks` and MallocScribble. Not done: the forms libc++'s
`<vector>` and `<string>` use (allocators, `enable_if`, partial
specializations, `constexpr`, `noexcept`, rvalue reference overloads
chosen by value category, exceptions), which are the road to compiling
them as they are.

**M6's tenth step (0.41): members of class type.** A data member whose
class has constructors is CONSTRUCTED in every constructor of its
holder (`cpp_member_inits`, the class clause: from its `init(N, Args)`
entry, else its default initializer, else the member's default
constructor, else `member_not_constructed`), and a holder without a
constructor gets the implicit one for it (`cpp_implicit_ctor_needed`
counts such a member); a member whose class has a destructor is
DESTROYED by every destructor of its holder, the members in reverse
order, then the base (`cpp_dtor_body`), and a holder with none gets an
implicit destructor (`cpp_implicit_dtor_needed/1`, `cpp_implicit_dtor/3`,
emitted with the class; `cpp_own_dtor` counts it, so `delete`, the
scope's defer and the table's slot find it). An AGGREGATE initializer
of a class whose only constructor is the implicit one constructs each
member from its item (`cpp_decl_pieces`' first clause,
`cpp_aggregate_inits/5`: `Person p = { "ann", 30 }` is
`string.string.char_p(&p.name, "ann"); p.age = 30;`), then the
destructor's defer. The check's constructor and destructor effects
reach a member's address: `ck_arg_base(addr(E), K)` takes any path
(`&this->name`, `&p.name`), so the member's own fields go live after
its constructor and moved after its destructor, and the holder's
`fresh`/`dying` rules hold through the nesting (`ck_pointee_fields`
recurses into members held by value). Gated by
`test/cpp/run/member.cpp` (a struct with a `Name`, a class with a
`Name` and a `Bag` of the structs, a member initializer, an aggregate,
a move into the bag; zero leaks). Not done: a member's default
initializer of class type (`std::string s = "x";` in a class body),
an array member of objects, a union of objects.

**M6's eleventh step (0.42): C++20.** THE LEVEL: `-std=c++17|20|23|26`
(`bin/cicili`: `std(N)` in the options; older levels refused as
unsupported, C's `-std` ignored) sets `'$ccl_std'` (default 17;
`ccl_std/1` reads it), and the preprocessor answers the level's macros
first (`pp_predef_macro`: the tables `cpp26`, `cpp23`, `cpp20` by
`pp_std_table/2`, then `any`, the arch, `cpp`; the tables at the end
of `ccl_pp.pl`, from the reference compiler's `-dM -E` at each level,
taken once: `__cplusplus` 202002L/202302L/202400L, the `__cpp_*`
feature tests -- concepts, consteval, constinit, char8_t, the three-way
comparison, coroutines, modules, `using enum` ...). A summary is one
level's (`ccl_sum_file` folds `Path@Std`, the `sum` line's key is
`cpp(Std)`), the store's key `cpp(Version, Std)`. THE READER (version
32): the keywords `concept requires co_await co_yield co_return
consteval constinit char8_t` in both lexers (`ccl_lx_cppkw` in the
module), `<=>` a punctuator in both (`ccl_lx_p3`) and a binary
operator at level 7.5 -- below the relational, above the shifts;
`concept N = E;` an item (`ccl_note_template(N)`, so `C<T>` reads as a
template-id), a `requires` clause on a template's head kept as
`requires(E)` among the parameters (the binders skip it), a
`requires` expression a primary with its requirements (`type(T)`,
`compound(E, C)`, `nested(E)`, `expr(E)`), `co_return` a statement and
`co_await`/`co_yield` unaries, `using enum E`, a range-for with an
initializer as a block, `if constexpr` its own node, an attribute
before a statement dropped, `auto` a TYPE in C++ declarations (C's
storage class it is not) so `auto f(auto x)` reads, a template lambda
with `tparams(Ps)` among its captures, `explicit(cond)`. THE
DESUGARING: a concept is registered (`'$cpp_concepts'`,
`N-concept(TPs, E)`) and CHECKED where a template is instantiated
(`cpp_constraints_hold/3` after the bindings; `cpp_satisfied/1`: `&&`,
`||`, `!`, a concept-id through `cpp_concept_holds/2`, a
`requires_expr` whose requirements type-check under its parameters --
an expression rewritten by the desugaring has a type, a type resolves,
a compound's type satisfies its concept, a nested one holds -- else a
constant expression; a trait with no body here is
`constraint_unknown`), refusing `constraint_not_satisfied(N)`; an
abbreviated function template becomes a template of invented
parameters `$A1, $A2 ...` at registration (`cpp_auto_params/4`, through
pointers and references) and its item is nothing; a function's `auto`
result is deduced from its first return (`cpp_lambda_ret`, at the item
and at an instance); `if_constexpr` is decided by `cpp_const_bool/2` (a
constant, a `bool`, a concept-id) and one branch kept, else a plain
`if`; `bin('<=>', A, B)` on scalars is `(A > B) - (A < B)`, an int
where C++ has `std::strong_ordering` (a class's `operator<=>` when it
has one, else `three_way_comparison_of_a_class`); `using enum` is
nothing (the enumerators are global names already); `co_return`,
`co_await`, `co_yield` are `coroutine`, a template or generic lambda
`generic_lambda`; `char8_t` is a byte. Gated by `test/cpp/cxx20.cpp`
read (c22-c28), `test/cpp/run/cxx20.cpp` built with `-std=c++20`
(`test/cpp/run/NAME.flags` gives a fixture its flags) printing
`__cplusplus` 202002, and `coro.cpp` and `concept_fail.cpp` refused by
name. Not done: modules (`import`/`export`), `consteval` evaluated at
compile time (it runs at run time like `constexpr`), coroutines,
`std::strong_ordering` and defaulted `operator<=>`, generic lambdas,
constrained `auto` (`Number auto x`), `requires` clauses on a
non-template function, C++23's and C++26's forms beyond their macros.
**An integer literal's suffix is read** (found by this step: `1L` was
`int(1)`, so a template deduced `int` from it and `%ld` of it read
garbage): both lexers give `tok(uint|long|ulong, N, L)` for `u`, `l`,
`ul` in either case and order (`ccl_int_suffix//1` in the DCG,
`ccl_lx_int_suffix` and `x->sfx` in the native one), the parser the
nodes `uint(N)`, `long(N)`, `ulong(N)`, typed, folded, lowered and
keyed (`cpp_type_key`: `Nu`, `Nl`, `Nul`) beside `int(N)`; reader
version 33; `k59` and `k65` read `0xFFul` and `1u << 4`.

**M6's twelfth step (0.43): C++23.** The level's macros were there
(`-std=c++23`, `pp_std_table`); this step is the forms. THE READER
(version 34): `if consteval { } else { }` and `if ! consteval` are
`if_consteval(L, no | yes, T, E)`; an explicit object parameter, `this
Self &self` (`ccl_param`, cpp only), is `param(this(T), N)` first among
the parameters (`ccl_declare_params` strips the mark); `a[i, j]` at
`-std=c++23` (`ccl_std_at_least/1`) is `index(A, args(Is))`, a single
index the `index/2` it was -- one clause reads `ccl_args` and chooses,
no re-parse; `auto(x)` and `auto{x}` are `decay_copy(E)`; a lambda
takes an attribute after its captures and its specifiers with or
without the parentheses (`ccl_lambda_specs`: `mutable`, `constexpr`,
`consteval`, `static`, `noexcept(...)`); `using T = type;` in an
init-statement (`ccl_for_init`'s alias clause, `ccl_init_stmt` makes
the `typedef` item) and -- C++11's, missing -- in a block; `if (init;
c)` and `switch (init; e)` (C++17's, missing) are a `block` of the
initializer and the statement, as the range-for with an initializer
is; a label may end a block (`ccl_label_body`: `label(L, N, empty)`).
BOTH LEXERS: the suffix `z`/`Z` (`4uz`) is a long, `size_t` under
LP64; the escapes `\x{...}`, `\o{...}`, `\u{...}` and the universal
character names `\uXXXX`, `\UXXXXXXXX` (not read before), the last
two put into a string as UTF-8 (`ccl_utf8/3`, `ccl_lx_put_utf8`), a
code point in a char literal; octal `\NNN` up to three digits (before,
`\101` read as `\1` then `01`); `\N{NAME}` is not read. THE
PREPROCESSOR: `#elifdef X` and `#elifndef X` (`pp_cond_word`,
`pp_defined_body/3` spells them as `defined(X)` for the group skipper);
`#warning` stays nothing. THE DESUGARING: `cpp_norm_members/2` at
`cpp_register_class` turns the marked parameter into the qualifier
`explicit_this(N, T)`, so arity, overload choice, mangling and slots see
the parameters a caller passes; `cpp_declare_members` and
`cpp_member_fns` declare and emit such a method with `param(T, N)`
first instead of `param(ThisT, this)` and walk its body under `Ctx =
none` (no implicit `this`: C++23 has it so, `self.n`), `this auto` on a
class's method refused as `deduced_this(C)` (a member template);
EVERY CALL SITE passes the object through `cpp_object_arg/3`: the
declared function's first parameter named `this` takes the address as
before, any other name takes the object itself (`B` for `addr(B)`,
`deref(P)` for a pointer) -- a reference parameter takes its address in
the lowering, a by-value one a copy, refused for a class with a
destructor by `cpp_no_copies`. A lambda's `this auto self` is the
closure by value (`cpp_self_type/3`: `auto` becomes the closure's type,
an rvalue reference a reference), its method marked `closure`, and its
body walked under `Ctx = self(C, SN)` so a capture named bare is
`member(id(self), N)` (`cpp_expr(id)`'s second branch) -- the recursive
lambda, `n * self(n - 1)`, states its result type, since the first
return's type is asked before the closure's class exists. `if
consteval` keeps the run-time branch (nothing here is evaluated at
compile time); `decay_copy(X)` is `cast(T, X)` of the decayed type, the
value itself for a class (a copy of one with a destructor refused as
before); `index(A, args(Is))` goes to the class's `operator[]` over the
arguments, else `subscript_arity(N)`. FOUND BY THIS STEP: a typedef
inside a block was noted by the reader and forgotten by the passes
(the symbol table is rebuilt from the top-level items) -- `T x` was
`not_lowered(typedef(T))` in C too; `ccl_collect_item(function)` now
walks the body's statements for `typedef` items (`ccl_stmt_typedefs`,
by statement shape, not into expressions), one table for the function
(a name typedef'd in two blocks must agree); `test/c/run/typedef_block.c`.
Gated by `test/cpp/cxx23.cpp` read at the level (c29-c33: `unit_at/3`
sets `'$ccl_std'` for the read), `test/cpp/run/cxx23.cpp` built with
`-std=c++23` (`.flags`) printing `__cplusplus` 202302, and
`deduced_this.cpp` refused. Not done: deducing `this` with a deduced
type on a class's method (CRTP: `template` inside a class), `static
operator[]`, `\N{...}`, the extended floating-point suffixes (`1.0f16`),
`#warning` printed, `[[assume]]` told to LLVM, trailing whitespace
before a line splice, `consteval` at compile time, modules; C++26's forms.

**M6's thirteenth step (0.44): the road to libc++, its first stretch.**
FOUND FIRST: the reader had never read a libc++ header -- it stopped at
`<vector>`'s first item (a conversion operator) and `ccl_read_unit`
takes a PARTIAL read silently (`partial(U, line(L), near(F))`), so every
library summary held nothing but macros. THE LOOP: `cicili++ -E f.cpp -o
flat.cpp` (clang's flag; `dr_preprocess`: `ccl_pp_file/3` standalone,
spelled back by `ccl_pp_spell/2` in ccl_pp -- a token a word, a string
with `\NNN` escapes, a line per source line, an infinite float as
`1e999`), then `sh test/census.sh flat.cpp` (test/census.pl: the read
through `cicili_ast/3`, the stop line, the farthest line and the tokens
around both, then a histogram of the AST's functors with the template
shapes apart) -- a few seconds a turn where a flatten is twenty. THE
READER (version 34 still; every rule guarded by `ccl_cpp`): a
conversion operator `operator T()` (`ccl_conv_type`: specifiers and
pointers only, `int ()` would read as a function type) as
`method(L, Qs, T, operator(conv(T)), [], false, Body)`; class-scope
`typedef` and `using x = T` as `typedef` members whose names join the
global env; `ccl_sto_pick/2` chooses the deciding storage word (`static
inline constexpr` lost `static`); attributes anywhere (`[[...]]` before
an item, a member, among the prefix words, after a lambda's parameters,
`alignas(...)`); packs: `tparam(pack, N, D)`, `tparam(vpack(T), N,
none)`, `param(pack(T), N)`, `pack(X)` for an expansion in a template
argument, a call argument, a base, an initializer item, a constructor
initializer, `sizeof_pack(N)`, `fold(Op, dots, E)` / `fold(Op, E,
dots)` / `fold(Op, A, dots, B)`; a template argument is a full
expression (`ccl_targ_expr`: `'$ccl_targ'` counts the depth and
`ccl_op_open/1` makes `>` and `>>` closers, parentheses reset it); a
template's parameters are types for the item's whole text
(`ccl_tparam` adds each to the global env as read, `ccl_tparams_enter/3`
and `ccl_tparams_leave/1` around the item, `'$ccl_tmpl_depth'` making
the item's own name a template inside its body, `ccl_note_if_template`);
`struct X<Args>` is `class(K, tmpl(X, Args), Bs, Ms)` (`ccl_class_targs`;
the noters skip a compound tag), a declarator `X<T>::f`, `v<T>`,
`operator+<...>` is `name(Q)` where a declarator may end
(`ccl_declarator_id_end`: `(is_x<T>::value && y)` is no cast); `typename
T::x`, `X<T>::template f<U>`, `decltype(e)` as a name's segment and
`decltype(auto)`; the compiler's traits: `builtin_type(N, Args)` for the
type-yielding ones (`ccl_builtin_type_name`: a fixed list, since the
SDK's `(__istype(c, m))` is a call) and `call(id('__is_same'), [type(T),
type(U)])` for the tests (`ccl_builtin_trait`); `noexcept(e)`,
`alignof(T)`, `void()`, `int{}`, `typename X::y()` as `construct(T, As)`,
`::new`, `::operator new`, `p.operator->()`, `operator""sv`, `f(...)
= delete` at file scope, a member template's name noted, `template <int
&...>`, `template <class...> class F = X`, `if (T x = e)` and `while` as
a block of the declaration and the test, `return { a, b }`, `struct I
{...};` inside a class as `nested(Base)`, `friend(L, Ms)` with the
member read (a friend's body has semicolons), `extern template ...;`
and `template class X<char>;` as `extern_template(L, I)` and
`explicit_instantiation(L, I)`, a deduction guide as
`deduction_guide(L, N, Ps, T)`, an out-of-class `X<T>::X(...)` with
`inline` and attributes before it (`ccl_class_base/2`), an unnamed
template parameter, `typename T::x = 0` told from a type parameter
(`ccl_tparam_end`), the threaded env MERGED into the global one at every
item (`ccl_env_sync/2`: before, a typedef's item replaced the global env
and dropped every class name added on the side). THE VEXING PARSE: `S
b(std::move(a));` had read as a function declaration; a qualified name
is a type where its last name is known as one (`ccl_qname_typish`) or a
declarator follows (`ccl_declarator_follows`: `ns::what &w`), an
expression where `(` does. BOTH `<vector>` AND `<string>` READ WHOLE
(441 and 434 items; `test/libcxx.sh`, a fresh HOME so nothing is served
from a summary, about a minute).

THE DESUGARING (`library/ccl_cpp.pl`), on the program's own classes:
`test/cpp/run/generic.cpp`, `copies.cpp`, `bindings.cpp`. Packs:
`cpp_bind_targs_` gives a pack parameter `P-pack(Rest)`; `cpp_subst`
expands `pack(X)` wherever a list holds it (`cpp_subst_elems`: an
argument, a template argument, `base(A, pack(Q))`, `item(D, pack(V))`,
`param(pack(T), N)` into `N$1..N$k` with `N-vpack([id(N$1) ...])` bound
by `cpp_param_packs` for the body) -- ONLY for packs that are bound
(`cpp_pack_names`), so a member template's own expansion inside an
instantiated class waits for its own instantiation; folds
(`cpp_fold_right/left`, empty ones as the standard has them);
`sizeof_pack`; a trailing parameter pack deduced element by element
(`cpp_deduce_pack`); `cpp_type_key(pack(L))` joins the keys. SPECIALIZATIONS:
`'$cpp_spec'(N, TPs, Pattern, Item)` from `cpp_spec_name`;
`cpp_instantiate_class_` binds the primary's parameters (defaults
merged from the other declarations of the name, `cpp_merge_defaults`,
their parameters renamed), names the instance, records
`'$cpp_inst'(Name, inst(N, FullArgs))`, then `cpp_pick_spec`: every
specialization whose pattern matches (`cpp_match_pattern`: a type
parameter binds, a value parameter compares by `ccl_const_eval`, a
template-id pattern matches an instance of that template through its
recorded arguments, `cpp_instance_of`), the most specialized of them
(`cpp_more_special`: X's pattern as arguments matches Y's); the
injected class name is bound to the instance (`Self`). FUNCTION
TEMPLATES are candidate sets: `cpp_instantiate_function` tries each in
declaration order, `cpp_signature_holds` inside a `catch` as a
condition -- a `cpp_refuse` in binding, deduction or the resolution of a
value parameter's type (`enable_if<c, int>::type`, no `type` member:
`no_member_type`) is no candidate (SFINAE); the first candidate's
refusal is the diagnostic when none fits (`'$cpp_first_refusal'`);
overloads get `F.cK` in their instance names. MEMBER TEMPLATES:
`'$cpp_mt'(C, Key, TPs, M)` from `cpp_register_class_extras`;
`cpp_method` falls back to `cpp_member_template_call` (deduced from the
arguments, or `o.f<T>(...)` given), `cpp_ctor` to
`cpp_member_template_ctor`; the instance is declared and emitted at the
call. DEPENDENT NAMES: `'$cpp_class_types'` (a class's typedefs, from
its `typedef` members) answers `cpp_type(typedef(scoped(Path, N)))`
through `cpp_scope_class` (a class, an instance, a namespace prefix
skipped) and REFUSES `no_member_type` when the class has no such type;
`cpp_subst` substitutes inside a scoped name's path (`C::value_type`
with C bound); a class's own typedef names resolve inside its members
through `'$cpp_class_ctx'` (`cpp_in_class`, set while a class is
declared, walked or emitted); `cpp_targ_value` tells `X<T>::value` (a
static member) from `X<T>::type` by what the class has; `X<T>::f(args)`
calls a static method with a null this; `X<T>::value` folds to the
static's constant (`'$cpp_static_inits'`); `decltype(e)` types the
expression desugared; `__is_same` and a dozen traits are decided
(`cpp_trait`, `cpp_builtin_type`). AUTO RESULTS of methods are deduced
through the desugaring (`cpp_method_ret`: the first return desugared,
then typed -- the inference knows no instance's call). COPIES: a
constructor from the class itself (`cpp_copy_ctor(C, ref | rref)`)
makes an lvalue initializer construct through it and `move(x)` through
the move one, the argument x itself (a reference parameter takes the
address, `cpp_ref_args_of` strips `move` there); `cpp_arg_fit` scores
the value category (`cpp_category_mismatch`: an rvalue reference binds
no lvalue, a plain one no rvalue; an rvalue prefers `C &&`); `a = b` goes
to `operator=`; a by-value parameter of a class with a destructor takes
`cpp_copy_temp` at the call (the copy constructor into a temporary) and
the callee destroys it (`cpp_param_defers`, a defer first in the body);
`return x` of such a local moves out into a temporary; a prvalue moves
bitwise (C++17 elides that copy). THE CHECK: `r.f` with r a reference
is keyed `r->f` (`ck_path`), a conditional returns either arm
(`ck_no_escape`), `&c.f` borrows what `&c` does. BINDINGS: `auto [a, b]
= e` is Cicili's pattern by another spelling (`ccl_destructure`, an
array's elements by index, `ccl_bind_refs` for `auto &`). A braced
temporary of a plain struct is a compound literal; deleted and defaulted
members are dropped at `cpp_norm_members`, a pure one marked; an
abstract class registers and is refused only where constructed
(`cpp_not_abstract`). THE LIBRARY: a flattened header's items are
indexed by name into FACTS, `'$cpp_hdr'(Name, Item)` (`cpp_index_header`;
`cpp_hdr_load/1` registers every item of a name on the first miss of
`cpp_class`, `cpp_template`, `cpp_class_template`); a header's class is
LAZY (`'$cpp_lazy'`: the struct emitted, `cpp_use_member` emitting a
member when `cpp_method`, `cpp_ctor` or `cpp_own_dtor` first names it);
a header's inline function is emitted linkonce when loaded; an alias
template instantiates as its type (`cpp_instantiate_type`; the class
definition wins a name over `std::pmr::vector`, an alias sharing the
flattened name, and alias and variable templates stay out of the C
typedef table, `ccl_collect_item`); the registries that hold BODIES
are facts too (`'$cpp_cls'`, `'$cpp_tmpl'`, `'$cpp_spec'`, `'$cpp_mt'`,
`'$cpp_inst'`, `'$cpp_out'`, reset by `cpp_reset/1`): as lists in
globals they were copied at every lookup, megabytes each once libc++
was in them. THE BUDGET: `cpp_spend/1` counts loads and instances,
`cpp_deeper/1` the nesting; past 3000 or 120 the compile stops with
`instantiation_budget` / `instantiation_depth`, since one unbounded run
of `std::vector<int>` took the machine's memory (the owner saw it);
`'$cpp_trace'` prints each spend for the loop. `std::vector<int> v;`
loads vector, allocator, allocator_traits, numeric_limits,
initializer_list, `__wrap_iter`, `__vector_layout` and `__split_buffer`
(26 loads and instances, two minutes: the declaration of a library
class's hundred methods resolves every dependent type in them, a road
of its own to profile) and stops at `template_without_body('_Layout')`:
a template template parameter (`template <class, class, class> class
_Layout`) bound to a template's name and used as one, the next form. NOT DONE: the AST cache beside a summary (a program that
instantiates a library template needs the header read again, twenty
seconds: `template_without_body` on a summary-served run), the forms
libc++'s bodies use past that point, `std::pmr` and other namespace
collisions (the flattening), a lambda pack capture, `\N{...}`, nested
classes as types, `using` declarations, a friend's scope.

**M6's fourteenth step (0.45): libc++'s first function compiled from its
own body, `std::swap`.** THE TEMPLATE TEMPLATE PARAMETER, `template <class,
class, class> class _Layout = __split_buffer_pointer_layout`: bound to a
template's NAME, `tname(X)` (`cpp_tname_arg/3`: an atom, a namespace
flattened away, another such parameter's binding passed on --
`__split_buffer<_Tp, _Allocator, _Layout>`); `cpp_subst` turns
`base(Q, [typedef(P)])` into the name and `tmpl(P, Args)` into `tmpl(X,
Args)` (in a scoped path too), the key is the name, a specialization's
pattern matches one (`cpp_match_one`), `f(H<T>)` deduces H from an
instance (`cpp_match`'s template-id clause), and `ccl_skip_to_close`
counts nested `<>` in the parameter's own list. `__split_buffer`'s base,
`_Layout<__split_buffer<_Tp, _Allocator, _Layout>, _Tp, _Allocator>`
(the CRTP through the parameter), instantiates; `test/cpp/run/ttp.cpp`.
FUNCTION TEMPLATES AS C++ CHOOSES (`cpp_instantiate_function`): the
candidates are every DEFINITION of the name in declaration order (a
prototype is a `declaration` item; the registry is assertz -- the
`reverse` from the global-list days put the last declared first); a
signature holds when the arity fits (`cpp_arity_holds`: defaults, a
pack), the explicit arguments bind, the parameters deduce, the defaults
fill, the constraints hold, AND every class-typed parameter accepts its
argument (`cpp_params_accept`: the class itself, an instance of the
template, a class derived from it, else a class with a one-argument
constructor; a scalar parameter takes no class without a conversion
operator; an argument the inference cannot type passes) -- before, the
first candidate whose parameters deduced was taken, `__swap_allocator(a1,
a2, true_type)` for a `false_type`; a template-id parameter whose
argument is no instance of the template, nor a base of the argument's
class (`cpp_instance_or_base`), is `deduction_failed(N)`, no candidate --
before, it bound nothing and the defaults filled: `swap(tuple<_Tp...> &,
...)` held for two pointers with `_Tp` an empty pack; an ALIAS template's
template-id (`__type_identity_t<_Tp> *`) is a non-deduced context, the
alias substituted once `_Tp` is bound explicitly and the parameter
checked then; of the candidates that hold, the FEWEST CONVERSIONS win
(`'$cpp_conversions'`: a derived object to a base's reference, a value
through a constructor), then the MOST SPECIALIZED (`cpp_fn_more_special`:
Y's parameter types deduce from X's taken as arguments with X's own
parameters opaque, `$opaque.P`), the first declared among equals; the
trace prints `candidate(F, K, holds(Conv) | refused(Why))`;
`test/cpp/run/overloads.cpp` (thirteen choices, clang++'s). THE TRAITS
over two or more types are decided (`cpp_trait_n`: constructible,
assignable, convertible, base_of, over the registry -- a scalar converts
as C++ converts, a class through its constructors, conversion operators
and bases; the nothrow forms are the plain ones, the trivial ones ask no
user-written special member) and the rest of the one-type ones
(`cpp_trait_of`: scalar, fundamental, object, empty, polymorphic,
aggregate, trivially copyable, trivially destructible ...);
`ccl_builtin_trait` is a FIXED list of the compiler's -- libc++ has
functions in the same spelling (`__is_overaligned_for_new(__align)`),
read as the calls they are. A DATA MEMBER's type is resolved under the
class's own typedefs at registration (`cpp_member_types`: `pointer
__begin_` is `int *`; the trace `member_type_unresolved`), so
`this->__front_cap_` has the type a call deduces from. A static
inherited from a base folds (`cpp_static_const` walks the bases:
`is_move_constructible<T>::value` is `integral_constant`'s), and a static
WITH its initializer in the class is its own definition, `linkonce`
(`cpp_static_decls`; `ir_globals` spells `linkonce_odr global`) --
`integral_constant::value` was the undefined symbol at the link. A
conversion operator mangles `op.conv_<key>`. A type without a
constructor direct-initialized, `_Tp __t(std::move(__x))`, `int n{}`,
takes the value or the type's zero (`cpp_plain_init`). `std::move` of a
value without owners is the value, through `cpp_expr(move(X))`, the one
door. A namespace-qualified call, `std::swap(a, b)`, `std::swap<int>(a,
b)`, resolves as the bare name would and never as a member. THE READER
(version 35): a FUNCTION template's name is a template (`move<int>(x)`
reads as a template-id) but no type (`'$ccl_fn_templates'`,
`ccl_note_if_fn_template` at the definition, a summary's `ftemplate(N)`
line, `ccl_qname_typish` excluding them): `_Tp __t(std::move(__x))` had
read as a function declaration taking a `std::move`, the vexing parse
C++ resolves by knowing what `std::move` is. THE AST BESIDE THE
SUMMARY (the thirteenth step's open item): `<name>-<fold>.ast.pl` holds
one clause per named item of the flattened header, `'$cpp_hdr_ast'(Name,
Item)`, written by `ccl_ast_write` with the summary and consulted
(`ensure_loaded/1` takes a two-megabyte clause in 0.2 s under `--local`,
where `term_to_atom/2` fails past tens of KB a line) by `cpp_load_ast`
when the include node is `file(_, summary, summary(F))`; `cpp_hdr_item/2`
answers from the index and the file alike, so the second run of a
program that instantiates a library template needs no flatten (0.8 s
where the first took 8). THE LIBRARY'S FUNCTIONS ARE NOT CHECKED -- the
decision this step took, for the owner to confirm or reverse: libc++'s
bodies keep raw pointers by their own discipline (a vector's begin, end
and capacity; a swap of two pointers through references), which the safe
part refuses at every line (`a borrow stored where it cannot be
followed`, swap's first statement); a function that comes from a library
header -- an inline one, a lazy class's member, an instance of the
header's template, whatever such a walk emits -- is `'$cpp_libfn'(Name)`
(`cpp_as_lib/2` around the emissions, a template's origin `'$cpp_lib'(N)`
from `cpp_hdr_load`) and the check skips it (`cpp_library_function/1` in
`ck_items`); the program's own functions, its own templates' instances
wherever they are instantiated from, are checked as always, and the
lowering lowers both. THE PROBE (`scratchpad/probe.sh SRC HOME LOG
SECS`): the HOME is REMOVED first -- twice a run showed no spend and
`template_without_body(vector)` because a leftover summary was served
and nothing reached the index -- and `test/config.sh` is sourced by a
shell whose `$0` sits in `test/`, since it finds the checkout from `$0`.
THE LAYOUT FORMS libc++ builds its containers from: an ANONYMOUS
STRUCT member's members are the class's own and an anonymous UNION's are
reached through the one member it becomes (`cpp_norm_members_`, a hop in
`cpp_data_member`; libc++'s compressed pair is such a struct) --
`test/cpp/run/anon.cpp`; `__builtin_offsetof` is decided from the layout
the compiler already computes (`cpp_offsetof/4` over
`ccl_members_layout`, a dotted path walked), which is how libc++ finds a
type's data size, the offset of a `char` placed after it --
`test/cpp/run/offsetof.cpp`; an ARRAY'S BOUND is an expression the
desugaring must rewrite like any other (`cpp_array_bound/2` in
`cpp_type`), since `char __padding_[sizeof(_ToPad) -
__datasizeof_v<_ToPad>]` needs its variable template instantiated and
folded -- it was passed through untouched and the array came out empty;
and a CLASS'S OWN TYPEDEF now wins over a namespace's of the same name
inside the class, as C++ looks names up (the `\+ ccl_typedef_of(N, _)`
guard in `cpp_type` inverted that order) -- `test/cpp/run/padding.cpp`.
FOUND ON THE WAY, older than this step: `malloc(sizeof(T))` did not
compile in C++ mode at all. libc++ spells `size_t` as
`decltype(sizeof(int))`, the lowering has no `decltype`, and resolving it
through `ccl_type_of` turns in a circle, since the type of a sizeof IS
`size_t`: `ccl_resolve_base` answers a `decltype` of a sizeof with the
concrete `unsigned long` and any other with the expression's type
(`ccl_sizeof_expr/1`, cpp only). Gated by `test/cpp/run/stdswap.cpp`: `<utility>`'s `std::swap` over
pointers and over ints, its result type through `__enable_if_t`,
`is_move_constructible` and `is_move_assignable`, C++'s numbers on the
first run and on the summary-served one. `std::vector<int>` now reaches
43 loads and instances (26 at 0.44) and stops inside libc++'s compressed
pair, `_FirstPaddingByte<pointer>`: the layout class's own `pointer`,
`typename __alloc_traits::pointer`, does not resolve through
`allocator_traits`'s own meta, so the instance is keyed by the unresolved
name and has no members -- the allocator machinery is the next stretch.

**M6's fifteenth step (0.46): the allocator machinery, and the memory
that had to come first.** THE MEMORY: cocolog has no collector (the
finding below): a `cicili++` run of `std::vector<int>` peaked at 4.5 GB
and, with a runaway of mine on top, restarted the owner's machine. The
preprocessor runs each file inside `\+ \+` (3.1 GB -> 564 MB for the
flatten), the parser reads EACH ITEM inside `\+ \+` (`ccl_externals/4`:
the item and the count of tokens left kept through a global, the
position recovered by that count -- the parse of the flattened
`<vector>` 1033 -> 440 MB, of which the top pass is 355), the name sets
the parser asks at every identifier are buckets (`ccl_set_has/2`), a
class's tag is noted without its bodies, and a gate's harness runs each
check inside `\+ \+`; every run of mine is under `scratchpad/guard.sh`
or `watch.sh`, and the module is rebuilt after a cocolog update (the
engine went 1.2.5 -> 1.2.12 under this step). THE DETECTION IDIOM, which
libc++'s allocator traits are built on (`__pointer` is
`__detected_or_t<_Tp *, __pointer_member, _Alloc>`): a partial
specialization's pattern is matched in TWO PASSES (`cpp_match_pattern`:
`cpp_match_deducible`, then `cpp_match_later`) -- the deducible elements
bind the parameters, then every NON-DEDUCED element (an alias template's
template-id such as `__void_t<_Op<_Args...>>`, a name qualified by a
parameter, a decltype; `cpp_non_deduced/2`) is substituted, resolved and
compared with its argument, a refusal in that resolution being no match:
the SFINAE that picks `__detector<_Default, __void_t<_Op<_Args...>>, _Op,
_Args...>` only where `_Op<_Args...>` has a type; a pattern element that
still names a free parameter is no match; a template-id pattern over a
template template parameter deduces the template too (`cpp_match_tmpl`,
`_Sp<_Tp, _Args...>`); an alias template's template-id in a FUNCTION
parameter is a non-deduced context as well (`cpp_match`); a PLAIN STRUCT
is a scope (`cpp_path_class`: `NoPtr::pointer` is refused as
`no_member_type`, never flattened to a namespace's bare name), an enum's
name is not (`Color::Green` is its enumerator); `test/cpp/run/detect.cpp`
(found and not found, clang++'s). A TYPEDEF IS RESOLVED IN THE CLASS THAT
DEFINES IT (`cpp_class_typedef/4` gives the defining class, `cpp_in_class`
around the resolution in `cpp_type`, `cpp_path_class`): `allocator_traits`
writes `pointer` as `typename __base::pointer` with `__base` its own
alias, which the asking class did not know -- and a scope the resolver
does not find flattens SILENTLY as a namespace (`cpp_type`'s last scoped
clause), which the trace now prints as `flatten(Path, N)`; the probe
showed `flatten([__base], pointer)` nineteen times. AND THE CLASSES THE ALLOCATOR
DRAGS IN, each a defect of its own: a class DECLARED and not defined
(`class bad_alloc;`) was indexed under its name and registered as the
class, with no members, so the real definition never registered
(`cpp_index_name` requires a body of a class as it always did of a
struct; `cpp_lazy_class` skips a bodyless one); a CONSTRUCTOR that is
declared and not defined -- libc++'s `bad_alloc()` lives in the shipped
binary -- had no clause in `cpp_member_fns`, where a method and a
destructor had one, and became a declaration now; a member of a class
whose only constructors are a defaulted one and a converting TEMPLATE
(`std::allocator`) is default-initialized with nothing to call
(`cpp_trivial_default/1`) and copied from its own class by the implicit
copy, the template never preferred over it (`cpp_ctor`'s guard), and a
CONSTRUCTOR'S PARAMETERS are in scope while its member initializers are
built (`a_(a)` has to type `a` to choose) -- `test/cpp/run/alloc.cpp`;
`__is_constructible` and `__is_assignable` unref the ARGUMENT and count a
constructor template and a defaulted constructor, so `std::allocator` is
move-constructible as C++ says (it read false, and the `enable_if` behind
`std::swap`'s result type then had no `type`); `auto` deduces ANY type
and not only a plain one (`ccl_add_quals`), where `auto __new_begin =
__begin_ - __size` -- a POINTER -- silently failed
(`test/cpp/run/autoptr.cpp`); a specialization is picked only where it
HAS a body. AND THE SILENT FAILURES BEHIND ALL OF THEM: a registration
or an emission that merely FAILED left the class half-registered -- its
`'$cpp_cls'` fact asserted, its members never emitted, and
`cpp_class/2`'s own load then failing -- so every later lookup lied;
each is a refusal now (`class_not_registered`, `class_not_emitted`,
`instance_not_emitted`, `base_not_registered`, `members_not_split`,
`member_types`), and the steps of a class's registration and emission
trace under `'$cpp_trace'` (`item_member_fns`, `method_body_failed`,
`instantiate_failed`, `want(Name)` ...), which is how each of these was
found. FOUND ON THE WAY: a missing input file compiled to `cicili: ok`
(`dr_input` refuses it now, `no such file or directory`).
`std::vector<int>` now reaches 67 loads and instances (43 at 0.45, 26 at
0.44) -- through the exception classes, the compressed pair, the
allocator's traits and `std::swap`'s result type -- and stops in
`__to_address`, `cannot_deduce('_Tp')`, the next stretch.

**M6's sixteenth step (0.47): `__to_address` and the uninitialized-memory
algorithms.** THE ONE THAT PAID FOR THE REST: `cpp_isolated/1` set the
symbol table's open scopes aside and restored them on success and on
failure but NOT ON A THROW -- and SFINAE throws and catches by design
(`cpp_holding_candidates` catches `not_lowered` to reject a candidate),
so after a candidate was rejected the CALLER's own locals had no types.
`__to_address(__first)` deduced and `__to_address(__last)`, the next
argument of the same call, did not (`cannot_deduce('_Tp')`, the argument
traced as `unknown`); a `catch` that restores and rethrows, as
`cpp_in_class` and `cpp_as_lib` already had. It took the probe from 67
loads to 97. THE FORMS: a UNARY operator on a class goes to the class's
operator, as a binary one already did (`cpp_expr` on `deref`, `preinc`,
`predec`, `postinc`, `postdec` -- postfix passing the `int` C++ marks it
with -- `not`, `neg`, `bitnot`, all through `cpp_operator/5`), without
which libc++'s `addressof(*__first)` could not be typed
(`test/cpp/run/unaryops.cpp`); a temporary of a class TEMPLATE's
instance written with explicit arguments, `Guard<A, I>(a, i, j)`, which
only a plain class had (`cpp_call`'s `tmpl` clause, guarded by
`cpp_targs_settled/1` so an argument that did not fold never names an
instance by its spelling); a QUALIFIED PATH of two or more class
segments walked segment by segment, each named inside the one before
(`cpp_scope_walk/3` behind `cpp_scope_class/2`, the old last-segment
rule tried first), which is how `allocator_traits<A>::propagate_on_container_swap::value`
folds; a MEMBER ALIAS TEMPLATE registered (`cpp_member_key` had only
methods and constructors) and resolved through its class,
`_IfImpl<C>::template _Select<A, B>` -- and its clause sits BEFORE
`cpp_type`'s template-id clause, since `cpp_template_id/3` strips a
scope to a bare name for `std::vector<int>`'s sake and swallowed this;
a member initialized from `std::move(x)` chooses its constructor on the
RAW initializer, so the choice looks through the move
(`cpp_init_arg_class/2`). AND THE DETECTION
`iterator_traits` IS BUILT ON, `__has_iterator_typedefs<It>::value`
deciding between two static member function TEMPLATES -- one taking
`...`, one taking five defaulted `__void_t<typename _Up::X> *`
parameters -- read through `decltype` of the call: an ELLIPSIS takes any
number of arguments and is C++'s WORST match, so a variadic candidate is
tried last and only where nothing else fits (`cpp_variadic_member/1`,
the flag threaded into `cpp_signature_holds/7` and `cpp_arity_holds/3`);
a member TEMPLATE named unqualified with explicit arguments,
`__test<_Tp>(nullptr, ...)`, resolves inside its own class with a null
`this`, as `X<T>::f(args)` already did; a `decltype(...)` is a SCOPE
(`cpp_path_class`), so `decltype(__test<_Tp>(...))::value` names the
class the expression has; a static const's initializer is DESUGARED in
its class's own words before it is folded (`cpp_fold_static/4`, a guard
per name since folding may ask for itself), where only a literal
constant folded before; and `typename _Up::X` on a class that has
neither such a type NOR such a member REFUSES (`cpp_targ_value`), which
is the SFINAE that rejects the candidate -- it had quietly become a
value named after the class, so the wrong overload won.
`test/cpp/run/detect2.cpp` (found and not found, clang++'s).
`std::vector<int>` now reaches 156 loads and instances (67 at the start
of this step, 43 at 0.45) -- through `__to_address`,
`__uninitialized_allocator_relocate`, the exception guard,
`__allocator_destroy`, `reverse_iterator`, `__wrap_iter` and
`iterator_traits` -- and stops on a NESTED CLASS, `vector`'s own
`__destroy_vector`, which is not registered as a type: the next stretch.

**M6's seventeenth step (0.48): nested classes, and what vector asked for
next.** A NESTED CLASS is a type of the class that holds it and a class of
its own under the mangled name `Enclosing.Nested`: its NAME is registered
first (`cpp_nested_names/2`, so a member of that type resolves before the
nested class exists), the class itself after the enclosing one is
registered (`cpp_nested_classes/3`, so its own members may name the class
that holds it -- libc++'s `vector` destroys itself through
`__destroy_vector`, which holds a `vector &`), and the enclosing class's
typedefs are copied into it (`cpp_enclosing_types/2`), as C++'s scoping
has them. It is reachable three ways: as a type (`Plain::Nested` outside,
`Nested` within, both through `cpp_class_typedef`), as a temporary
through the enclosing name, and named BARE inside its own class
(`__destroy_vector(*this)`); a class with no constructors takes braced
AGGREGATE initialization rather than a constructor
(`cpp_temporary`'s first clause, beside the empty `__less<>()` case) --
`test/cpp/run/nested.cpp`. AND THREE DEFECTS IT UNCOVERED, each older
than this step: a specialization's pattern QUALIFIERS were ignored, so
`numeric_limits<const _Tp>` matched every argument and the class derived
from ITSELF (`cpp_pattern_quals/3`: the argument must carry every
qualifier the pattern names, and binds without them); a VARIABLE
template used as a template argument was read as a type and instantiated
as a class (`cpp_variable_template/1` in `cpp_targ_value`,
`integral_constant<bool, __is_floating_point_impl<T>>`); and an OPERATOR
member template could not be named at all -- `cpp_instance_name`
concatenated `operator('()')` as if it were an atom and threw a type
error (`cpp_instance_base/2` spells it `op.call`), which `__less<>`'s
templated `operator()` needs. `std::vector<int>` now reaches 177 loads
and instances (156 at 0.47, 43 at 0.45) and stops on an instance keyed
by names that did not resolve, `__allocation_result.pointer.size_type`
beside the good `__allocation_result.int_p.size_t`: a template
instantiated where its arguments' class scope was not in hand, which is
a name-resolution defect rather than a missing form, and the next thing
to chase.

**M6's eighteenth step (0.49): the name resolution behind a badly keyed
instance.** `std::vector<int>` had made TWO instances of one template,
`__allocation_result.pointer.size_type` beside the good
`__allocation_result.int_p.size_t`: the first keyed by names that never
resolved. THE CAUSE was in the READER, not the desugaring. `auto r =
std::__allocate_at_least(a, n)` was deduced AT READ TIME by
`ccl_auto_decl/5`, from the symbol table's declaration of
`__allocate_at_least` -- and a function template is declared there under
its RAW, unsubstituted signature (`ccl_collect_item` walks into a
template's item), so the deduced type was `__allocation_result<typename
_Traits::pointer, typename _Traits::size_type>` with `_Traits` free.
The desugaring then resolved it, could not find `_Traits` as a scope, and
FLATTENED it as if it were a namespace (`cpp_type`'s last scoped clause),
giving `pointer` and `size_type` as the arguments. A type that still
carries a DEPENDENT name is not deduced yet (`ccl_dependent_type/1`: a
`scoped/2` anywhere in it): `auto` stays, and `cpp_decl_pieces` deduces
it once the call is instantiated, which is the only place that knows.
Reader version 36. `test/cpp/run/autodep.cpp`. THE TOOL that found it,
worth keeping: `cpp_where/2`, a SCOPED breadcrumb of what the desugaring
is working on -- `class(N)`, `fn(F)`, `load(N)`, `member(C, M)`,
`sig(F)`, `subst(F)`, `body(C)`, `auto(N)`, `call(F)`, `args(F)`,
`stmt(Functor, Line)` -- printed by every trace that would otherwise be
silent (`flatten(Path, N, in(Where))`). An unscoped first attempt named
the last thing ENTERED and sent me to the wrong class twice; scoped, it
named the statement. And the reproduction is the other half: the shape
cut down to thirteen lines runs in ONE SECOND where the probe takes
fifty, which is what made the last four defects quick. `std::vector<int>`
now reaches 182 loads and instances (177 at 0.48) and stops in the
EXCEPTION classes -- `__throw_length_error` pulls `length_error`,
`logic_error`, `basic_string` and `char_traits`, whose primary is
declared and whose `char` specialization the index does not hold -- which
is the road to `<string>` and, behind it, the question of exceptions
themselves.

**M6's nineteenth step (0.50): EXCEPTIONS, by not having them.** libc++
asks the COMPILER whether the language has them -- `#if
defined(__cpp_exceptions) && __cpp_exceptions >= 199711L` decides its
`_LIBCPP_HAS_EXCEPTIONS` -- so the two predefined macros
(`__cpp_exceptions`, `__EXCEPTIONS`) are simply not predefined any more
(`ccl_pp.pl`, commented with the reason). The library then compiles its
OWN no-exceptions configuration, as it ships and as `-fno-exceptions`
gives it: `<vector>`'s flattened text went from nine `throw`s and three
`try` blocks to NONE, and a thrower aborts with a message instead. This
is the honest configuration for a compiler whose safe part has no
unwinding to offer, and a program that writes `throw` or `try` of its own
is still refused by name. Reader version 37, since every summary was
flattened with exceptions ON and must be read again. WHAT IT UNCOVERED,
each a defect of its own: a PRVALUE bound to a `const` reference had no
address, and C++ materializes a temporary -- `ir_ref_of` allocates one
and stores the value (`v.push_back(1)`, the user's own line, was the
first thing to reach it); the COMPILER'S OWN BUILTINS that libc++ calls
are answered as this compiler can (`cpp_builtin_call/3`:
`__builtin_is_constant_evaluated` is FALSE, since nothing here is
evaluated at compile time; `__builtin_operator_new` and `delete` are the
malloc and free the lowering already has, at any arity, an alignment
request dropped; `__builtin_launder`, `__builtin_addressof`,
`__builtin_expect`, `__builtin_assume_aligned`); a VARIABLE template read
as a TYPE in an expression is evaluated (`!__has_max_size_v<const _Ap>`
-- the reader cannot tell a type from a value there, and unevaluated the
negation came out false); and a bool template argument KEYS AS ITS NUMBER
(`cpp_type_key`), so `true` and `1` name one instance where they had
named two -- the same duplicate-instance defect as 0.49's, from the other
side. Lowering version 9. `std::vector<int> v; v.push_back(1);` now
reaches `allocator_traits<allocator<int>>::max_size`, whose two overloads
are chosen by `__has_max_size_v<const _Ap>` and its negation: a variable
template of TWO parameters whose specialization is a `decltype` of a
member call, where both conditions come out false and neither overload is
picked. The isolated shapes all work (a negated variable template, a
`const` argument, static member templates with `enable_if` defaults,
`test/cpp/run/` fixtures), so what is left is that two-parameter
detection, and it is the next thing.

**M6's twentieth step (0.51): the detection trait, and the allocator
through.** `__has_max_size_v<_Alloc, class = void>`, whose specialization
is matched by `decltype((void) declval<_Alloc &>().max_size())`, decides
which `allocator_traits::max_size` libc++ uses. It asked four things,
each a defect: a function template DECLARED and never defined
(`template <class T> T &&declval();`) must still instantiate, for its
TYPE is all a decltype wants (`cpp_fn_item/2` normalizes a declaration
item into a function with no body, the call clauses take it, and the
instance is emitted as a DECLARATION) -- without it the call fell to the
class-template clause and refused `instance_without_body(declval)`; a
member call on a type that HAS members but not that one REFUSES
(`cpp_call`'s member clause), which is the rejection a detection needs,
where it had been left alone and `(void) <unknown>` was void either way,
so the trait was true for everything; a member of a REFERENCE is a member
of what it refers to (`cpp_class_of_type` unrefs), since `declval<C &>()`
names one; and a member template's signature is checked IN ITS OWN CLASS
(`cpp_in_class` around `cpp_signature_holds` in `cpp_try_member`), since
`const allocator_type &` is written in the traits class's words and read
in the caller's -- it refused `argument_mismatch`.
`test/cpp/run/detect3.cpp` (found, not found, and through a `const`).
AND WHAT THE ALLOCATOR NEEDED BEHIND IT: `::operator new` and `delete`
written out are the malloc and free the lowering already has
(`cpp_operator_new/3`, any arity); a tag with NO members takes no
initializer, so `__element_count(n)` -- an empty scoped `enum class` --
is a CAST (the enum-ness of an empty enum is not in the tag table, and
the members decide); and a class-scope typedef naming a scalar is a
functional cast, `size_type(~0)`, beside the nested-class case that
clause already had. TWO OF THOSE CUT TOO WIDE, and the gate
said so: unreffing inside `cpp_class_of_type` made a REFERENCE-typed
type count as its class, and the rules that turn on the value category
(`return_of_a_class_with_destructor` and kin) then fired on returns of
references -- six fixtures failed, and the unref belongs in
`cpp_class_of_type_of`, the class an EXPRESSION has, never in the
type-level test; and making a declaration a candidate let the
DECLARATION of `std::swap` win over its definition, which linked to
nothing, so a declaration is a candidate only when nothing is defined
(`cpp_defined_first/2`, before the specialization ordering). `std::vector<int> v; v.push_back(1);` now compiles
`allocator<int>`'s `allocate` and `max_size` whole and stops in
`__swap_allocator`, on an `integral_constant<bool, false>` that reaches
the lowering without being instantiated.

**M6's twenty-first step (0.52): A LIBRARY TEMPLATE'S INSTANCE IS LAZY.**
A class instance emitted EVERY member function it had, so
`std::vector<int> v; v.push_back(1);` compiled vector's hundred members
and stopped at the first one this compiler could not take --
`__swap_allocator`, reached through a `swap` the program never calls. A
library header's plain class already emitted members only as they were
named (`'$cpp_lazy'`, `cpp_use_member/2`); an instance of a LIBRARY
template does so too now (`cpp_lazy_instance/2` before `cpp_item`), which
is what the standard says a template instantiates. The program's OWN
templates stay eager: their instances are the program's code and the safe
part must see all of it. It took the probe from 177 instantiations to 83,
and every form still to be found is now one the program actually uses.
WITH IT: a NESTED class sees the enclosing class's types INCLUDING the
inherited ones -- `'$cpp_enclosing'` records which class holds a nested
one and `cpp_class_typedef/4` falls back to it, where copying the
enclosing class's direct entries missed `pointer` on
`__split_buffer::_ConstructTransaction`, whose enclosing class gets it
from its layout base. `std::vector<int> v; v.push_back(1);` now stops on
`__vector_layout`'s `__alloc()`, an accessor emitted lazily whose
`__alloc_` is a member of the class's ANONYMOUS STRUCT and is not found
there: the flattening that `test/cpp/run/anon.cpp` proves works on a
struct written plainly does not reach this one, whose members carry
`[[no_unique_address]]` and default initializers and sit last in the
class. The gates' peaks fell with the laziness (the C++ gate 855 -> 615
MB).

**M6's twenty-second step (0.53): an anonymous struct in C++'s own
shape, and a phase that says its name.** An anonymous struct whose
members carry DEFAULT INITIALIZERS reaches the desugaring as
`class(struct, anon, [], Ms)` and not the plain `struct(anon, Ms)` that
`test/cpp/run/anon.cpp` covers, so its members were not flattened into
the holder and `__vector_layout`'s `__alloc()` could not find `__alloc_`
(`cpp_norm_members_` takes both shapes now) --
`test/cpp/run/anoninit.cpp`. AND THE DIAGNOSTIC that found the next one:
`ccl_ir_units` ran the desugaring, the check and the lowering as one
conjunction, so any of them merely FAILING left the driver with nothing
to say but `the check or the lowering failed without saying why`; each
phase names itself now (`ir_fail(phase(desugaring | check | lowering))`).
`std::vector<int> v; v.push_back(1);` stops in the LOWERING, around the
declared-only `declval` instance that 0.51 taught the desugaring to make.

**M6's twenty-third step (0.54): the lowering of what libc++ declares
but never defines, and the EMPTY CLASS.** A function item with NO BODY is
a PROTOTYPE: nothing to define, its `declare` line coming from the
externals a call names (`ir_item`'s first function clause) -- the
lowering had only the defining clause and merely failed. And
`std::declval` is not bodyless after all: libc++ gives it a body of one
`static_assert` and no return, so the function falls off its end, which
the lowering already closes with a zero of the return type -- but the
return type is `allocator<int>`, an EMPTY class, and an empty aggregate
has no leaves, so it classified as `direct([])`, pieces with no LLVM type
at all. C++ gives an empty class size ONE and one byte crosses a call
(`ir_abi_`'s first clause, `ir_pieces_type([], i8)`); empty classes are
everywhere in C++ -- an allocator, a comparator, a tag. AND TWO
DIAGNOSTICS, both of which earned themselves at once: `ir_items` names
the ITEM it cannot take (`ir_item_name/2`: the function or declaration
and its name, a body as its functor) and ATTACHES THE ITEM to any error
raised inside it (`ir_item_error/2`, a `not_lowered` passing through
unchanged), which turned a bare `type_error(atomic, scoped([global],
deallocate))` into the item that raised it. `std::vector<int> v; v.push_back(1);` now stops in
`vector`'s NESTED `__destroy_vector`, on `__alloc_traits::deallocate(...)`
whose scope arrives as `[global]` rather than the enclosing class's
typedef: the nested class reaches the enclosing class's TYPES now, and
this says its qualified NAMES do not follow the same road.

**M6's twenty-fourth step (0.55): a qualified name inside a nested class,
a temporary called, an enum that is a strong typedef, and the members
libc++ defines OUT of their class.** (1) THE VEXING PARSE, ONE SCOPE
DEEPER: `traits::take(x);` as a statement inside a nested class's method
read as a DECLARATION of a globally qualified name -- `ccl_direct`'s
`name(Q)` clause takes a compound qualified name as a declarator-id, which
is right at file scope (`Shape::area`, `vector<T>::vector`, a
specialization `f<int>`) and never inside a function body, where such a
declarator declares nothing: `\+ ccl_in_block` (`ccl_locals/1` non-empty)
now says so. Reader version 38; `test/cpp/run/qualstmt.cpp`. (2) A
TEMPORARY'S `operator()`: `__destroy_vector(*this)()` is how libc++'s
vector destroys itself -- the callee is no function but an object built
in the same expression, so the call goes INSIDE the block that builds it
(`cpp_temp_call/3`, tried by the last `cpp_call` clause once the callee
is desugared), where that object has an address; `(*p)(a)` and `fs[i](a)`
take their own (`cpp_addressable/1`), no temporary. `test/cpp/run/tempcall.cpp`.
(3) A SCOPED ENUM'S UNDERLYING TYPE: libc++ writes `enum class
__element_count : size_t { }` as a strong typedef for a count, and the
reader kept nothing of `: size_t` while an enum with NO enumerators has
the members' shape of an empty struct -- so the tag resolved to
`%struct.__element_count = type {}` and the cast back to a count came out
as `sext` from a struct, which LLVM refused. An enum's members now carry
`enum_base(T)` first (`ccl_enum_members//3`, a scoped enum without a
written base marked `int` all the same), `ccl_is_enum_tag/1` is the ONE
test for them (the type resolution `ccl_tag_type/4`, the functional cast
`__element_count(n)`, the scope walk that must not take `Color::Green`
for a class's member), and the size (`ccl_size_align`) and the LLVM type
(`ir_base`) are the underlying type's. Reader version 39;
`test/cpp/run/strongenum.cpp`. (4) A FLOAT LITERAL PAST A DOUBLE --
`__LDBL_MAX__`, which every long double header writes and this compiler
lowers as a double -- is the largest finite double (`ccl_finite_float/2`
at the parser's one float-literal door, so both lexers agree): cocolog
WRITES an infinity as `inf.0` and its own reader refuses that, so the AST
beside a summary would not consult (`its clauses would not consult`, no
line) and the header was flattened and read again at every run, fifty
seconds against three. (5) A CLASS TEMPLATE'S MEMBER DEFINED OUT OF ITS
CLASS, `template <class _Tp, class _Allocator> void __vector_layout<_Tp,
_Allocator>::__set_bound_using_pointer(pointer __p) noexcept { ... }`,
which is how libc++ writes half of a container's members: the item was
DROPPED at registration (neither a specialization's name nor a
template's), so the instance's member kept the class's declaration, the
lowering made it a prototype and the linker said the symbol was undefined
(`nm -u` named `__size`, `__capacity`, `__end_ptr`,
`__set_bound_using_pointer`). Every such definition is kept by its
CLASS's name (`'$cpp_mdef'(Class, Key, TParams, Pattern, Member)`,
`cpp_mdef_item/4`: a method, a MEMBER TEMPLATE whose own parameters wait
for the call, a constructor, a destructor -- the reader gives the last
two the class's bare name, so their parameters bind in order), indexed
under it (`cpp_index_name`, which is also what `ccl_ast_write` writes
by), and an instance takes the definition whose pattern matches its
arguments (`cpp_match_pattern`) and whose parameters key alike
(`cpp_member_defs/5`, before the instance's class is registered).
`test/cpp/run/outofclass.cpp`. (6) THE RESULT TYPE IS PART OF THE
SIGNATURE, C++'s immediate context: `typename
__sfinae_underlying_type<_Tp>::__promoted_type __convert_to_integral(_Tp)`
is no candidate for a `_Tp` that is no enum, and the refusal its
resolution raises must make it none -- before, the candidate was chosen
on its parameters alone and the refusal came out as an error
(`cpp_result_holds/2` inside the candidate's own catch; only a DEPENDENT
QUALIFIED name is resolved there, the one shape written to fail, since an
`auto` or a `decltype` result is deduced later from the body and a plain
type or a template-id would cost a refused candidate an instantiation).
WHERE `std::vector<int> v; v.push_back(1); return (int) v.size();`
STANDS: with (1) to (4) it passed the desugaring, the safe part and the
LOWERING whole and made an object file of 9816 bytes -- the first time
the program reached one -- whose link named seven undefined symbols, the
four layout accessors and two vector members defined out of their class
among them; with (5) those bodies are found, and the walk that now enters
them stops in the DESUGARING at `__convert_to_integral(__n)`, where every
template overload of the name is refused, rightly, and the plain
overloads beside them are not candidates at all: a free function's
OVERLOADS are neither chosen by their arguments nor mangled apart (the
first definition of a name is emitted and every call goes to it), which
is the next stretch. Seven gates GREEN (the C++ one at 773 MB, libc++'s
at 1596).

**M6's twenty-fifth step (0.56): FREE FUNCTION OVERLOADS, chosen by their
arguments and mangled apart.** C++ tells `int f(int)` from `double
f(double)` by the arguments and gives each its own symbol; C has one name
one function, which is what this compiler emitted -- so of libc++'s ten
`__convert_to_integral` overloads, one per integer type, only the FIRST
got a body and every call went to it, whatever it passed (a `size_t`
through the `int` one). Every free function is noted by name, by the key
of its parameters AS WRITTEN and by whether it has a body
(`'$cpp_fn'(Name, Key, Params, Defined)`), in a PRE-PASS over every unit's
items before anything is registered -- and, for a library header, over
every item of a name before any of them is (`cpp_note_fns/1` in
`cpp_hdr_load`) -- so a name is known to be overloaded or not before any
call to it is read. A name with TWO definitions of different parameters
mangles each `F.<keys>` (`cpp_fn_name/4`), as a method already did; a name
with ONE definition keeps it, so every C function, every `main` and
everything a linker must find by name is untouched, and so is a
DECLARATION of an overload (we may name only what we define) and anything
inside `extern "C"` (`'$cpp_cnames'`). The same name is used where the
function is DECLARED in the table, where it is EMITTED (`cpp_item`) and at
the CALL (`cpp_free_call/5`), from the one predicate. THE CHOICE: an
overload whose parameters take the arguments EXACTLY -- both resolved,
their top-level qualifiers dropped, and equal (`cpp_arg_exact/2`) -- wins
over any template, which is C++'s rule for a non-template that needs no
conversion (`__convert_to_integral(__n)` with `__n` a `size_t` takes the
`unsigned long` overload, where the two templates rightly refuse); else
the templates as before; and where NO template holds, the plain overloads
of the name, which are one overload set with them (`cpp_fn_best/4` over
`cpp_pick`, the methods' own scoring). A library header's inline function
is emitted once per OVERLOAD rather than once per name. Gated by
`test/cpp/run/freeoverloads.cpp` (six `kind` overloads chosen by type and
by arity, an exact `unsigned long` beating a template that would have
taken it, a static declared before it is defined) and
`test/cpp/run/aliastype.cpp` (the overloads a libc++ container is written
on: an alias of a class template's instance as the parameter type, free
and as a member). `std::vector<int> v; v.push_back(1); return (int)
v.size();` passes `__convert_to_integral` and stops where
`vector::__copy_assign_alloc(const vector &, false_type)` takes an ALIAS
of a class template's instance as a parameter: a library header's typedef
reaches the tables raw, and the passes rebuild them from the summary, so
the name must carry its instance to the lowering. Seven gates GREEN.

**M6's twenty-sixth step (0.58): six defects between the overload set and
the lambda, and the cleanup that hid them.** Following the vector probe
past `__convert_to_integral` turned up six, each its own rule: (1) an
ALIAS of a class template's instance carries the INSTANCE, not the name
(`typedef integral_constant<bool, false> false_type` taken as a parameter
type, which is how libc++ writes `vector::__copy_assign_alloc(const vector
&, false_type)`) -- the passes rebuild the tables from the summary, where
a library header's alias is raw, so a note behind the name does not
survive to the lowering, and only an alias whose WHOLE definition is a
template-id is resolved, since a name like `type' is some class's and the
global table's entry for it is another's; (2) A LIBRARY HEADER'S FREE
FUNCTION IS EMITTED WHERE IT IS CALLED (`'$cpp_fn'`'s origin
`lazy(Item)`, `cpp_use_fn/3`), as its classes and templates already were,
since libc++'s ten `__convert_to_integral` overloads include two over
`__int128_t` that nothing here lowers and a program calls one; (3) A TAG'S
OR A CLASS'S NAME CALLED WITH MORE ARGUMENTS THAN IT CAN TAKE is no
temporary (`cpp_tag_takes/2`, `cpp_class_takes/2`): namespaces flatten to
bare names here and libc++ has both `_Algorithm::__fill_n`, an empty tag
struct used as a template argument, and `std::__fill_n(first, n, value)`,
so the call built an aggregate of three items for a type with no members;
(4) A CLASS TEMPLATE DECLARED AND NEVER DEFINED is an INCOMPLETE TYPE a
template argument may name (`cpp_incomplete_instance/2`: the instance is
its name and its arguments, which is what a specialization's pattern
matches on) -- `__single_iterator<_It>` is declared only, a tag for the
algorithm dispatch; (5) THE ENCLOSING CLASS'S OWN REGISTRATION CAN ASK FOR
A NESTED CLASS, since declaring vector's members resolves types that
instantiate templates whose bodies call vector's members whose bodies name
`_ConstructTransaction` -- all before `cpp_nested_classes`, which comes
last so a nested class sees the enclosing one registered: the name is
recorded when the TYPE is and the class is registered on the first ask
(`'$cpp_nested'`, `cpp_nested_ready/1` in `cpp_class/2`); (6) a STATIC
member's type is resolved IN ITS CLASS (`cpp_in_class` around
`cpp_static_decls`, `cpp_resolved_type/2`), where `static constexpr const
type __max` reached the lowering as the global table's `type`, which is
some other class's. AND IN THE LOWERING: a call's VALUE bound to a const
reference gets the temporary C++ materializes for it (`ir_ref_of`, where
only a reference RESULT was taken and anything else refused), which
`std::min<size_type>(a.max_size(), n)` needs; and `initializer(I)` names
the TYPE that has no such member. Lowering version 12.
THE CLEANUP THAT HID THEM: this work was written, then reverted when two
fixtures failed in ways none of it explained -- a local with a plain
initializer had no type at its call. The cause was a single edit of mine
that removed a debugging trace: the replacement line put its `%` comment
BEFORE the rest of the clause, so `cpp_expr(...), ccl_declare(N, T)` was
commented out and no such local was ever declared. A comment inside a
clause ends the LINE, so a line is never rewritten with one in the middle;
and a regression that no change explains is a mis-edit until proved
otherwise. Seven gates GREEN. `std::vector<int> v; v.push_back(1); return
(int) v.size();` now stops in a LAMBDA inside one of vector's members,
on `__emplace_back_assume_capacity` named there: a lambda in a member
function must reach the enclosing class through the captured `this`, which
this compiler refuses (`capture_this`) -- the next stretch.

**M6's twenty-seventh step (0.59): A LAMBDA CAPTURING `this`.** It was
refused by name (`capture_this`) since the fifth step, and libc++'s
`vector::emplace_back` writes one: `std::__if_likely_else(size() !=
capacity(), [&] { __emplace_back_assume_capacity(...); ++__end; }, ...)`.
The closure keeps the enclosing object as a REFERENCE member, `'$this'`,
which is what a `[&x]` capture already is -- the lowering reads a
reference member through and the check counts it as one -- and its
initializer is `this` itself; `'$cpp_closure_this'` records which closure
holds whose class. Inside the closure's `operator()` the enclosing class
is reached through it: a data member named bare is `this->$this.member`
(`cpp_closure_member/3`), a method called bare takes
`&this->$this` as its object (`cpp_closure_object/2`, the base's hops
with it, a virtual one dispatched as ever), a static is its global, and
`this` written out is `&this->$this`. A lambda captures it where `[this]`
says so and, under a DEFAULT capture, where the body names anything of the
enclosing class -- a data member, a static, a method, a MEMBER TEMPLATE
(which is how vector's lambda names `__emplace_back_assume_capacity`) or
`this` itself (`cpp_captures_this/4`, `cpp_has_member/2`). The closure's
RESULT TYPE is deduced from the first return DESUGARED IN THE ENCLOSING
CONTEXT (`cpp_lambda_ret/4`, as a method's `auto` result already was),
since a member named in the body has a type only once it is the call or
the access the desugaring makes of it -- and where the lambda stands, the
enclosing locals and `this` are still in scope. THE CHECK takes the
captured object as it takes a reference capture: the item of a `'$this'`
slot is walked, not refused as a borrow stored where it cannot be followed
(`ck_init_slots_`), the closure being scope-bound here. WITH IT, two more
of libc++'s forms: a FILE-SCOPE TYPEDEF called by its own name is a
temporary of the class it names or the cast it looks like
(`false_type()`, `size_t(n)`), which only a class-scope typedef had; and
`cpp_has_member/2` looks through a member template. Lowering version 13.
Gated by `test/cpp/run/capturethis.cpp` (a member named bare, a method
called, `this->` written out, a default capture taking it, a static),
clang++'s numbers. Not done: a closure that ESCAPES its scope with a
captured reference or `this` is not followed by the safe part (the hole a
`[&x]` capture already had), `[*this]` (the object by value), a lambda
capturing `this` inside a nested class's method reaching the enclosing
enclosing one. `std::vector<int> v; v.push_back(1); return (int)
v.size();` now stops in `std::forward`'s instance, on an argument that
still names a template parameter -- an instance keyed by an unresolved
name, the defect 0.49 met from the other side.

**M6's twenty-eighth step (0.60): eleven forms between the free name and
the object file, and `std::vector<int>` COMPILED.** Following the probe
from the instance keyed by an unresolved name to the link:
(1) A TYPE THE READER CANNOT SETTLE stays `auto` -- 0.49 kept a qualified
name; a name the tables do not know, INSIDE A TEMPLATE, is another
template's own parameter come from the declaration the type was read off
(`auto __guard = std::__make_exception_guard(...)` takes that function's
result `__exception_guard<_Rollback>`), and deducing it keyed an instance
by that free name (`ccl_free_name/1`, reader version 41).
(2) A TYPEDEF IN A BLOCK IS SUBSTITUTED INTO THE STATEMENTS THAT FOLLOW,
as a template's parameter is: the typedef TABLE is one per unit, and half
a dozen libc++ functions each declare their own `_ValueType` -- one entry
survived, another function's, whose parameter was free.
(3) AN INITIALIZER IS WALKED ONCE: the `auto` clause desugared it to learn
the type and handed the RESULT to the pieces, which desugared it again --
a statement expression's temporary was declared twice (`no_constructor(C,
0)` where the second walk found it bare) and a lambda made a second
closure for nothing (`'$cpp_walked'/1`, the marker the pieces pass
through).
(4) THE MEMORY BUILTINS are the C library's functions (`__builtin_memcpy`
and kin, declared by `ir_cpp_prelude` when the file did not), and
`__builtin_constant_p` is FALSE, an assumption and a prefetch nothing.
(5) THE BIT COUNT folds where its argument does (`__builtin_popcountg`),
which is how libc++ writes a type's `digits`; cocolog's integers are
61-bit, so `~0` is -1 and the count is taken from the type's WIDTH.
(6) `__make_unsigned` and `__make_signed` answer (`cpp_signedness/3`).
(7) A C++ CAST FOLDS (`ccl_const_eval(ccast(...))`), without which
`type(~0)` stopped every constant behind it.
(8) A STATIC CONST NAMED BARE inside its class folds to its value, as
`C::value` already did -- `numeric_limits<ptrdiff_t>::__max` is built from
three such constants, and a static that does not fold is emitted `extern`
and the linker finds nothing.
(9) A TYPE'S NAME CALLED is one predicate for the three names a type has
(`cpp_type_call/3`): a class-scope typedef, a file-scope one, and an ALIAS
TEMPLATE's template-id (`__make_unsigned_t<type>(0)`).
(10) A PRVALUE USED AS A PLACE gets the temporary C++ materializes for it
(`ir_lval(call(...))`, where only a reference result was taken): `end()[-1]`
is vector's `back()`, and `f().x` is everyday C++.
(11) A LIBRARY HEADER'S FUNCTIONS ARE LOADED ON THE FIRST ASK from the
overload path too (`cpp_fn_ready/1`, whose load now throws through rather
than swallowing a refusal), and a lazy emission that FAILS is a refusal
(`function_not_emitted`), never a call with no definition behind it.
WHERE IT STANDS: `std::vector<int> v; v.push_back(1); return (int)
v.size();` compiles to an OBJECT FILE of 34 KB whose only unresolved
symbols are `malloc`, `free`, `memcpy` and libc++'s own
`std::__libcpp_verbose_abort` -- and that last one is C++-MANGLED in the
shipped library (`__ZNSt3__122__libcpp_verbose_abortEPKcz`), where this
compiler emits every name unmangled. ITANIUM NAME MANGLING FOR WHAT A
LIBRARY HEADER ONLY DECLARES is the next stretch, and the last thing
between the program and a binary that runs. Gated by
`test/cpp/run/libcxxforms.cpp` (a block typedef per function, a prvalue as
a place, an alias template called, a static const folding, the bit count),
clang++'s numbers; seven gates GREEN.

**M6's twenty-ninth step (0.61): ITANIUM NAME MANGLING, and `std::vector<int>`
RUNS.** Four things between 0.60's object file and a binary that gives C++'s
answers, the first of them the name itself. (1) THE MANGLING, for what a
library header only DECLARES: this compiler emits every name it DEFINES
unmangled -- its own C-shaped symbols, `C.m.k`, `F.<keys>`, which nothing
else knows -- but a name it only CALLS must be the one the shipped library
EXPORTS, and libc++ declares `std::__libcpp_verbose_abort(const char *, ...)`
and ships it as `_ZNSt3__122__libcpp_verbose_abortEPKcz`. So a function that
a library header declares and never defines, that is not `extern "C"' and
whose namespace path is known, is called by its Itanium name
(`cpp_mangled_name/3`, chosen in `cpp_fn_name/4` where the overload mangling
sits): `_ZN`, the namespace path (`cpp_mangle_ns/2`, `St` for std), the name
length-prefixed, `E`, then the parameters (`cpp_mangle_params/4`,
`cpp_mangle_type/3` over `P` `R` `O` `K` and `cpp_mangle_basic/2`'s builtin
codes, `v` for `f()`, `z` for the ellipsis). WHAT IS NOT MANGLED keeps its
plain name, so the linker names the symbol rather than a wrong one being
found: a class-typed parameter (this compiler's class names are its own
mangling, not C++'s), a type no code encodes, and ANY signature whose
substitutable components repeat (`cpp_no_repeats/1`) -- Itanium writes the
second occurrence of a component as `S_`, `S0_` ..., and a straight
re-encoding would be a different symbol. A HEADER'S NAMESPACE PATH is
recorded as the items are indexed (`cpp_index_items/2` threads it,
`'$cpp_hdr_ns'(N, Path)`; `extern_c` is the path `c`) and written beside the
AST for a summary-served run (`'$cpp_hdr_ast_ns'`), since the namespaces
flatten to bare names everywhere else here; the declaration itself is
emitted once, `cpp_use_mangled/3`, with the ellipsis kept
(`cpp_fn_variadic/1`, `cpp_fn_arity_fits/3`). (2) A REFERENCE MEMBER IS
BOUND, never constructed and never assigned: its slot takes the object's
ADDRESS and every later use reads through it (`ir_ref_member/4`, which a
lambda's `[&x]` capture already relied on). libc++'s `vector` destroys
itself through a nested `__destroy_vector` that holds a `vector &`, and
taken as a member of a class with constructors that member initializer
became `operator=` into an uninitialized reference -- `vector::assign`,
`fill_n`, SIGSEGV. `cpp_member_inits`' first clause makes it
`bind_ref(arrow(this, N), E)`, which is `ir_bind_ref/2` in the lowering (the
address into the SLOT, where an assignment would write through it) and a
plain walk in the check, the object outliving its holder the way a reference
capture's does -- neither followed by the safe part. (3) PLACEMENT NEW,
which is what `std::__construct_at` is and every container's way of making
an element: the reader read the placement arguments and THREW THEM AWAY, so
`::new ((void *) __p) _Up(args)` was the allocating new it looks like, called
malloc and dropped the block -- a vector's size grew and its elements were
never stored. They are kept now, `new_at(Ps, new(T, As))` (reader version 42;
`ccl_new_node/3`), and the desugaring builds what the form means
(`cpp_new_at/4`): the class's constructor over the given address, or the
value stored through it, or a refusal by name (`placement_new`). (4) A CAST
TO A REFERENCE TYPE IS A BIND, not a conversion -- `static_cast<_Tp &&>(__t)`
is `std::forward`'s whole body, and as a value conversion it loaded the int
and made a pointer of it (`inttoptr`), so every element a container
constructed held the low half of an address. The value of a reference is its
address (`ir_expr(cast(T, E))` and `ir_ref_of/2` for `cast` and `ccast`
alike, `ir_lval` for the bind as a place), and a reference where a VALUE is
wanted is read through (`ir_convert/6`'s first clause), which is what the
rest of the lowering had done only at a call's result. Lowering version 15.
Gated by `test/cpp/run/stdvector.cpp`: ten `push_back`s through the slow
path, the split buffer and the relocation, `size`, `capacity`, `operator[]`,
`front`, `back`, and `std::vector<double>` for the whole machinery again --
clang++'s numbers, and `leaks` finds none. Seven gates GREEN (the C++ one
1037 MB warm, 2803 cold after the reader bump, which tripped a 2800 MB
watchdog on the first run and read as a RED: the finding below, again). NOT
DONE: the substitutions `S_`, `S0_` (a repeated component refuses instead), a
class-typed parameter in a mangled name, a mangled name for a TEMPLATE
libc++ ships instantiated, `new (p) T` told from `new (p) T()` (the reader
gives both no arguments, and the value-initialized form is what is meant), a
placement new of an aggregate with no arguments, `std::string` and the rest
of the containers.

**M6's thirtieth step (0.62): A VECTOR OF THE PROGRAM'S OWN CLASS.** 0.61's
vector held ints: the elements were scalars, nothing was constructed in place
and nothing destroyed. `std::vector<Name>`, over a class with an `own` pointer,
a destructor and a move constructor, is where libc++'s container holds objects
the safe part owns -- and it asked three things, the first of them older than
libc++. (1) A TEMPORARY DIES AT THE END OF ITS FULL EXPRESSION. It was on
0.34's not-done list ever since ("a temporary's destructor"): a local of a
class with a destructor got the scope's defer and a temporary got nothing, so
`v.push_back(Name("a"))` left the object alive for good and a class over an
own pointer leaked one buffer per call. The full expression here is the
STATEMENT, so `cpp_stmt/3` is a wrapper around the walk (`cpp_stmt_/3`, every
old clause): it opens `'$cpp_temps'`, and `cpp_temporary` registers a
temporary of a class with a destructor there instead of declaring it in its
own block -- only the construction stays where the evaluation order puts it.
An EXPRESSION or a DECLARATION statement then takes the declarations before it
and plain destructor CALLS after it (`cpp_temp_scope`, spliced: C++'s point of
destruction exactly, in construction order and destroyed in the reverse); ANY
OTHER statement holds statements of its own, past which an early exit would
walk, so its temporaries get a DEFER at the end of a block wrapped around it --
which a `return` needs in any case, the defers running after its value is
computed. A LOOP's condition and step are evaluated at every turn and one slot
cannot hold a temporary per turn, so a temporary there is refused by name
(`cpp_expr_once/4`, `temporary_in_a_loop_condition`). (2) AND A TEMPORARY WHOSE
VALUE INITIALIZES ANOTHER OBJECT of its class is ELIDED, as C++17 guarantees:
the object it builds IS the by-value parameter or the result, and whoever holds
it destroys it (`cpp_temp_elide/2` at the two places that know -- a class-typed
by-value parameter in `cpp_copies_`, and `return`). The gate found this one:
destroyed at both ends, `v.push(Name("gamma"))` freed one buffer twice
(bag.cpp aborted) and `return Counter(n)` counted a destruction that never
happened (counter.cpp's numbers moved by one). (3) A PARAMETER'S TYPE IS READ
THROUGH AN ALIAS to see its VALUE CATEGORY (`cpp_param_ref/2` at the head of
`cpp_arg_fit`): libc++ writes `push_back(const_reference)` beside
`push_back(value_type &&)`, and no category can be read off the alias's own
name -- the const lvalue overload won every temporary, which then had to be
copied into it, and a class with an owner had two holders. (4) A STATEMENT
EXPRESSION IS A PLACE when it ends with one (`ir_lval(stmt_expr(...))`,
`ir_lvalue_form`), which is what every temporary this compiler builds is
(`({ C $tmp; ctor(&$tmp); $tmp; })`), so a reference binds to the OBJECT;
materialized as a prvalue instead, the temporary was copied and the copy's
owner was freed under the vector that had taken it. Lowering version 16. WHAT
RUNS: `std::vector<Name>` pushes temporaries by move, grows its buffer three
times relocating the objects, subscripts, calls their methods, is walked by a
RANGE-FOR (`for (const Name &x : v)`, which the desugaring's rewrite over
`size()` and `operator[]` already served) and destroys them all -- clang++'s
numbers, `leaks` finds none, and a `std::vector<Tag>` counts its constructions
and destructions to the same totals C++ gives. Gated by
`test/cpp/run/stdvectorown.cpp`; seven gates GREEN. NOT DONE: a class with a
COPY constructor rather than a move one in a vector (libc++ copies where it
cannot move), `v.insert`, `v.erase`, `v.resize` (a placement new of a class
with no arguments is refused by name), a temporary whose lifetime is extended
by binding it to a named reference, a temporary in a loop's condition,
`vector<vector<T>>`.

**M6's thirty-first step (0.63): `std::string` from libc++, COMPILED FROM ITS
OWN BODY.** The SHORT-STRING OPTIMIZATION is what the type is built on, and
what it asked for first: `union __rep { __short __s; __long __l; }` with four
constructors. (1) **A UNION WITH CONSTRUCTORS IS A CLASS whose members share
storage**, so it goes a class's whole road -- registered, its methods emitted,
its constructors chosen -- while its LAYOUT stays a union's. `'$cpp_union'(C)`
says which, the class's tag carries the marker `union_tag` first and
`ccl_is_union_tag/1` is the ONE test for it (as `enum_base` and
`ccl_is_enum_tag` already told a scoped enum from an empty struct, 0.55); the
emitted declaration is `union(C, [union_tag|Data])` so the tag noted FROM it
agrees, `ccl_tag_type/4` answers a union spec, and `cpp_class_of_type_` takes
that spec as its class all the same. A UNION'S CONSTRUCTOR initializes AT MOST
ONE member and leaves the others alone (`cpp_union_inits`) -- they share the
bytes, and default-constructing the rest would overwrite them and demand
constructors none of them have. (2) A **NESTED UNION** is a nested TYPE of its
holder (`cpp_nested_name`, `cpp_nested_spec`): with constructors it is the
class above, with only data members a plain union emitted once under the
mangled name. (3) A **LAYOUT IS OVER DATA MEMBERS**: a C++ class's tag carries
its constructors, methods and typedefs beside them, and a nested one reaches
`ccl_members_layout_`/`ccl_union_layout` as the reader gave it -- both skip
what is not a `member/3` now. (4) A **NESTED TYPE NAMED AS A TYPE is registered
on the first ask**, whatever its kind (`cpp_type`, `'$cpp_nested'`): a LAZY
library instance never runs the enclosing class's nested registrations, and
`basic_string` names its own `__rep` as a template argument -- that union's
members name `__short` and `__long`, two more of its nested types. (5) A
**CLASS-SCOPE ENUMERATOR is a constant of the class**, as a static const is
(`cpp_class_enums`, kept RAW and folded in the class's words like a static's):
`enum { __min_cap = (sizeof(__long) - 1) / sizeof(value_type) > 2 ? ... : 2 }`
is named bare in members and in an array's bound. (6) A **NESTED CLASS SEES THE
ENCLOSING CLASS'S STATICS**, as it already saw its types (`cpp_static_const`
through `'$cpp_enclosing'`): `__long`'s constructor divides by its holder's
`__endian_factor`. (7) A **SCOPED NAME, FLATTENED, GOES THROUGH THE TYPE HOOK
AGAIN**: `std::string` is an ALIAS of a template-id, and flattened to the bare
name and left there it reached the lowering as `basic_string<char>` itself.
(8) **`C() = default;` IS the implicit default constructor** and keeps the
class default-constructible where its other constructors would have suppressed
it (`'$cpp_default_ctor'`, `cpp_trivial_default`) -- `__rep` writes it beside
three others. (9) A **CANDIDATE WHOSE ARGUMENT DOES NOT FIT IS TRIED LAST**,
after every template (`cpp_args_fit` in `cpp_method` and `cpp_ctor`; the
arity-only set stays the last resort, so nothing that resolved before resolves
differently): libc++ writes `explicit basic_string(const allocator_type &)`
beside the constructor TEMPLATE that takes a `const char *`, and the plain one,
alone in fitting the ARITY, won every `std::string s = "abc"' -- which came out
empty. (10) A **DEFAULT ARGUMENT IS DESUGARED WHERE IT IS FILLED IN**, which is
where C++ evaluates it (`cpp_fill_defaults`): it is kept raw from the
declaration, and `const _Allocator & __a = _Allocator()` on that same template
reached the lowering as a call to a type; `cpp_subst` turns a bound `T()` into
the type's name called, the temporary road a class's name already takes.
(11) A **`const` LOCAL OF INTEGRAL TYPE WITH A CONSTANT INITIALIZER IS A
CONSTANT EXPRESSION**, as C++ has had it since C++98 (`cpp_note_const`, noted
after the initializer is DESUGARED, since the class constants in it fold only
then; C gained this at C23, `ccl_note_constants`). (12) An **EXPLICIT TEMPLATE
ARGUMENT IS EVALUATED WHERE IT BINDS** (`cpp_bind_explicit`, `cpp_bind_targs_`
through `cpp_targ_value`), whatever road brought it: the class path evaluated
first and the FUNCTION and MEMBER template paths handed the argument over raw,
so `__align_it<__boundary>(n)` -- libc++'s alignment step over that `const`
local -- keyed its instance by the NAME and left it in the body. (13) A
**SPECIALIZATION'S DEFINITION BEATS ITS OWN FORWARD DECLARATION**
(`cpp_pick_spec`, through `cpp_template_class_def`): libc++ declares
`struct char_traits<char>;` early and defines it later, both matching `[char]`
and equally specialized, so the empty one won and every `traits_type::copy`
was a call to nothing; a declared-only specialization still stands where none
is defined (0.58's incomplete type). The alias resolution TRACES what it
catches (`alias_refused(N, W)`), which is how (8) was found -- it had been
swallowed into a silent fallback. Lowering version 17. Gated by
`test/cpp/run/stdstring.cpp`: a SHORT string in the object's own bytes and a
LONG one in a buffer the destructor frees, `size`, `c_str`, `operator[]`,
`empty` -- clang++'s numbers, `leaks` finds none, 557 MB to build. Seven gates
GREEN (the C++ one 1581 MB).
NOT DONE, AND MEASURED: **the MUTATING operations do not fit in memory here.**
`s += "def"` alone peaks past 2800 MB in 17 s and was killed -- and it is no
runaway: 120 instantiations, 46 of them distinct, with
`__allocator_traits_base.allocator.char` asked 283 times and
`allocator_traits.allocator.char` 267. It is the no-GC accumulation of the
finding below over a hundred library instantiations, not a loop, so the way
through is the compile's memory and not a budget. Also not done: `push_back`,
`operator==`, a string COPIED, `operator+`, `substr`, `find`, iterators,
`std::string` as a member or in a container.

**M6's thirty-second step (0.64): THE COMPILE'S MEMORY -- a loop, not a
weight.** 0.63 left `s += "def"` peaking past 2800 MB in 17 s on a 16 GB
machine, and read it as the no-GC accumulation of a hundred library
instantiations. MEASURED, it was nothing of the kind. THE PHASES, taken apart
(`cicili++ -fsyntax-only` against the whole build, then `ccl_cpp_units` alone
under the guard): the READ is 48 MB and 0.9 s, and the DESUGARING is all 2900
of the rest -- so the question was never the reader's. Two guesses failed
before the measurement paid: scoping every class instantiation inside `\+ \+`
moved the peak by nothing (its results are facts and globals, which survive a
scope, and its intermediates were not the weight), and the desugaring's lookup
tables are SMALL (`'$cpp_class_types'` 127 entries after a `std::string` build,
`'$cpp_lazy'` 51). What found it was the trace at a LOW cap, which names what
is in flight when the memory goes: the last event was always
`instance(initializer_list.value_type)` -- an instance keyed by a FREE NAME,
0.49's defect once more -- and then silence while the machine filled. THE
CAUSE: substituting `_Ep := value_type` into `initializer_list<_Ep>` turns its
own `typedef _Ep value_type` into **`typedef value_type value_type`**, a
typedef that IS its own definition, and `cpp_type`'s class-scope clause
resolved that name in that class by asking for itself, without end and without
a trace. A TYPEDEF THAT IS ITS OWN DEFINITION IS NOW LEFT ALONE
(`cpp_self_typedef/2`, the guard on that clause): the name stays as written and
whatever needs it refuses by name, as everything else here does. 2936 MB and
16 s become 495 MB and 4 s. AND AN INSTANCE ASKED FOR AGAIN ANSWERS ITS NAME
AND NOTHING ELSE (`'$cpp_iname'(N, Args, Name)`, the arguments compared with
`==` so an unbound one matches nothing): a clause retrieval COPIES the term it
answers, and `cpp_instantiate_class_` fetched a template's whole item -- one of
libc++'s containers is hundreds of members -- to recompute a name it had
computed before, 267 times for `allocator_traits<allocator<char>>` alone. The
asks fall from 550 to 51 and the peak by a further tenth. WHAT IT BOUGHT, all
measured on this machine: the desugaring of `s += "def"` 2936 -> 495 MB;
`test/cpp/run/stdstring.cpp` built through `cicili++` 557 -> 422 MB; THE C++
GATE 1581 -> 752 MB. The libc++ gate stays at 1882 MB, the biggest number left
and the READER's -- a flatten and a parse of `<vector>` and `<string>` under a
fresh HOME, one-time per header and cached after. Lowering version 18. Seven
gates GREEN; no new fixture, since the shape that looped needs an argument no
valid C++ can write, and the gates' peaks are the measurement. NOT DONE: why
`initializer_list<value_type>` is asked with a free name at all (the class-scope
typedef did not resolve where `basic_string` declares that constructor) -- the
loop is gone but the badly keyed instance remains; the reader's 1882 MB; and
`s += "def"` still refuses, now by name (`undeclared('__func_')` in a scope
guard), which is a form and no longer a wall.

**M6's thirty-third step (0.65): A CANDIDATE'S PARAMETER TYPE IS READ IN ITS
OWN CLASS'S WORDS.** 0.64 stopped the loop and left the question it hung on:
why is `initializer_list<value_type>` asked for at all? THE INSTRUMENT first,
since the obvious one lies: `cpp_where` keeps only the innermost breadcrumb, so
a trace inside `cpp_instantiate_class` reports `in(class(initializer_list))` --
the ask naming itself. Read BEFORE the wrap, with the class context beside it,
it named the caller at once: `ask(initializer_list, [typedef(value_type)],
from(stmt(expr, 3)), ctx(none))` -- the statement `s += "def"` in `main`, no
class in context at all. THE CAUSE: libc++ gives `basic_string` five
`operator+=` overloads, one of them `operator+=(initializer_list<value_type>)`,
and `cpp_method` scored every candidate AT THE CALL SITE, where the context is
the caller's or none. A parameter type is written in ITS CLASS's words:
`value_type` there is `basic_string`'s, and read in `main` it resolved to
nothing and instantiated `initializer_list` under the free name. The scoring
and the pick now run inside `cpp_in_class(C, ...)` in `cpp_method` and
`cpp_ctor` -- the rule a member template's signature has had since 0.51 ("a
parameter written `const allocator_type &' is in the traits class's words, not
the caller's"), for the plain overloads too. With it, `std::string s; s +=
"def";` makes 45 instances and NOT ONE keyed by a free name (it asked for four
before); its build is 495 -> 455 MB. The C++ gate goes the other way, 752 ->
861 MB, and rightly: resolving a parameter in its class is real work that was
being skipped. 0.64's self-typedef guard stays as the net under it. Gated by
`test/cpp/run/classwords.cpp`, which EARNS its line -- without the fix the
`List<char>` overload wins a `List<int>` argument (both candidates score zero,
so the first declared takes it) and LLVM refuses the call; with it, clang++'s
numbers.

**M6's thirty-fourth step (0.66): A DATA MEMBER THAT IS CALLABLE, and the
string that GROWS.** A local of a class with `operator()` has been callable
since M6's fifth step; a MEMBER was not, and libc++'s `__scope_guard` holds
the closure it was made with and writes `__func_()` in its destructor -- which
is the whole of how `basic_string` unwinds an append. The member is reached the
way every bare member name is (`this->f_`, a base's hops with it) and its own
class's `operator()` takes its address, the local's road one scope further in.
FIVE MORE the growing string asked for, each its own rule. (1) A PRVALUE OF THE
CLASS IS THE OBJECT, elided, as C++17 guarantees -- no constructor runs and
none is looked for: `auto __guard = std::__make_scope_guard(f);` handed a
`__scope_guard` to the only constructor `__scope_guard(_Func)` has, which takes
the closure, and LLVM refused the store; the temporary that built it is the
object too, so the statement must not destroy it (`cpp_temp_elide`, as a
by-value parameter and a return already did). (2) A CONVERTING CONSTRUCTOR AT A
CALL (`cpp_converting_ctor`, in `cpp_copies_` beside the copy): libc++ hands a
`__long` where a `__rep` is wanted, and `__rep(__long)` is how a string becomes
long. It converts only where the argument's type is KNOWN and is not already
the parameter's class -- what cannot be typed is never converted, which is the
guard `bag.cpp` earned when a `Name` temporary, whose type nothing could tell,
was wrapped in a second `Name`. (3) A PARAMETER IS RESOLVED IN ITS CLASS BEFORE
IT IS SCORED (`cpp_param_ref` through `cpp_type`): 0.65 put the SCORING in the
class, but the fit test resolves with the INFERENCE, which knows typedefs and
tags and no class scope, so `__rep(__long __r)` -- two of `basic_string`'s
nested classes by their short names -- still fitted nothing. (4) THE SAME TYPE
FITS ITSELF, registered class or not: two plain structs alike scored zero,
since only a registered class was compared. (5) A MEMBER INITIALIZED FROM A
CALL takes its class from the DESUGARED form where the raw one cannot tell it:
libc++'s copy constructor writes
`__alloc_(__alloc_traits::select_on_container_copy_construction(__str.__alloc_))`,
and unasked it read as a member with no constructor to take it. AND (6) A
DEFAULT ARGUMENT BELONGS TO THE DECLARATION, which C++ forbids an out-of-class
definition to repeat -- so taking the definition whole (0.55) threw the
defaults away, and `__grow_by_without_replace(a, b, c, d, 0)`, five arguments
to six parameters, found no member of that arity at all (`cpp_keep_defaults`,
`cpp_member_params`). FOUND ON THE WAY, older than this step: a temporary
hoisted out of its own block (0.62) was DECLARED nowhere until the statement
that holds it was walked, so nothing could type the value the block yields;
`cpp_temporary` declares it where it registers it. AND A LESSON THE GATE
TAUGHT: two clauses of `cpp_keep_defaults` both matched the empty case, which
made `cpp_member_def` nondeterministic, so `findall` gave the member twice and
a constructor was emitted twice -- `invalid redefinition of function`. A
refusal now TRACES its breadcrumb (`refuse(What, in(W))` under `'$cpp_trace'`),
which is how two of these were found. Lowering version 20. WHAT RUNS:
`std::string` appends (`+=`, a `const char *` and in a loop), `push_back`s,
grows out of its own bytes into a heap buffer, and is COPIED into a string with
a buffer of its own -- clang++'s numbers, `leaks` finds none. Gated by
`test/cpp/run/callable.cpp` (a callable member with two overloads, a converting
constructor, a default argument on the declaration) and an extended
`test/cpp/run/stdstring.cpp`. Seven gates GREEN (the C++ one 846 MB). NOT DONE:
`operator+`, `substr`, `find`, iterators (`operator==` is 0.67's).

**M6's thirty-fifth step (0.67): A FREE OPERATOR TEMPLATE OF A LIBRARY
HEADER.** `s == "abc"` is how a string compares, and libc++ writes it as
`template <class _CharT, class _Traits, class _Allocator> bool operator==(const
basic_string<...> &, const _CharT *)` -- a free function TEMPLATE. It reached
nothing here: `'$cpp_free_ops'` holds the operators the PROGRAM writes out, and
a header's item is indexed by NAME, which for `operator('==')` is a compound
that `cpp_template_name` would not take -- so the template was neither indexed
nor registered, and the `==` stayed a raw one on a struct, which LLVM refused.
Two halves. (1) A FREE OPERATOR TEMPLATE IS NAMED as a written-out one already
is, by its word and arity (`cpp_free_operator`, `op.eq.2`): with a name, a
library header indexes it, `cpp_hdr_load` registers it and `'$cpp_tmpl'` holds
it. (2) AT THE CALL, `cpp_operator`'s free branch falls through to THE
FREE-FUNCTION ROAD (`cpp_call(none, id(Name), [A|Args], E)`) -- its lazy load
by name, its candidate set, its deduction, all of which the plain free calls
have had since 0.56 -- and the answer is taken ONLY where the callee comes back
DECLARED; otherwise the form stays as it was, so a scalar `==` is untouched and
a name that resolves to nothing is refused where it always was. THE NAMING IS
WHAT A SUMMARY'S AST HOLDS, so `ccl_reader_version` is bumped (43) and every
summary and AST is rewritten: without that, a cached header keeps the old index
and the operator is invisible. Reader version 43, lowering version 21. Gated by
`test/cpp/run/stdstring.cpp`, which now compares (`1 0`); with it the probe
this whole stretch began from -- a string constructed, appended to, pushed back
on, grown into a heap buffer, COPIED and COMPARED -- matches clang++ line for
line. Seven gates GREEN. A NOTE ON THE COLD RUN, beyond the finding below: the
C++ gate peaked at 2803 MB twice after the version bump and was KILLED at the
2800 cap both times -- and a killed run writes no summary, so it stays cold for
ever. The way through is to warm the cache OUTSIDE the gate, one fixture build
at a time (836 and 699 MB here), and then run it (1057 MB). The libc++ gate,
which runs under a fresh HOME and is therefore always cold, went 1883 -> 2445
MB, the operator templates being part of what it now writes.

**M6's thirty-sixth step (0.68): AN INSTANTIATION INSIDE `\+ \+`, and the type
an argument has.** `std::vector<std::string>` -- libc++ holding libc++ -- took
2824 MB and 108 s and was killed at the cap. THE MEASUREMENT FIRST: the READ is
102 MB and 1.3 s, so the desugaring is all of the rest; the trace at a low cap
shows 185 spends and 80 DISTINCT instances with nothing asked twice, so it is
genuine breadth and no loop. AND THE FIX IS THE ONE 0.64 TRIED AND MEASURED AS
NOTHING: an instantiation's whole body -- substituted, registered, its members
walked and emitted -- now runs inside `\+ \+`, whose results (facts and
globals) survive the scope while every intermediate is reclaimed, cocolog
reclaiming on backtracking and by nothing else. 0.64's conclusion ("its
intermediates were not the weight") was drawn while the LOOP dominated and is
CORRECTED here: with the loop gone they are most of it. `vector<string>`'s
desugaring 2824 -> 1091 MB and 108 -> 9 s; THE C++ GATE 1057 -> 847 MB and THE
LIBC++ GATE 2445 -> 1902, the biggest number this repository has.
THREE DEFECTS the probe turned up on the way. (1) THE TYPE AN ARGUMENT HAS is
one predicate now (`cpp_arg_type/2`: through a `move' in either spelling, else
through the DESUGARED form), and `cpp_arg_fit` asks IT rather than the
inference: a member initializer and a call's arguments are both RAW when they
are scored, and libc++ writes `__rep_(std::move(__str.__rep_))' -- which the
inference cannot type, so every candidate scored the 1 an unknown type earns
and the FIRST constructor won, `__rep(__short)' for a `__rep', storing a union
into a byte. `cpp_init_arg_class/2` is that predicate plus the class, one rule
where there were two. (2) THE ARITY ALONE IS THE LAST RESORT, but never a
CLASS-typed parameter for an argument of ANOTHER class (`cpp_args_no_clash/2`,
in `cpp_ctor`'s and `cpp_method`'s fallbacks): that is no conversion this
compiler makes. (3) AN UNNAMED TEMPLATE PARAMETER HAS NO NAME TO LOOK UP --
libc++ writes its SFINAE guard as one -- and `memberchk(P-A, B)` with P unbound
takes whatever is FIRST in the bindings, so an instance was named one way where
it was emitted and another where it was called; it contributes no key and binds
nothing, in both places alike. AND a member TEMPLATE's instance that fails to
emit is a REFUSAL (`member_instance_not_emitted`), the name being noted DONE
before the emission runs -- 0.46's rule, which had never reached this path.
Lowering version 22. NOT DONE: `std::vector<std::string>` does NOT run. It
compiles through the desugaring in 10 s at 1144 MB, where it could not be
compiled at all, and stops at
`undeclared('allocator.S.construct.S.S.S_p.S_rr')`: the member template
`allocator<string>::construct` is NOTED as an instance and never EMITTED, so
the call names a definition that is not there. The refusal above does not fire
for it, which says the emission is not failing but being SKIPPED -- the name is
already noted when the first ask arrives -- and that is where the next step
starts. AND A LESSON FROM THE SAME AFTERNOON: two further rules tried here --
"no argument whose type is KNOWN may score zero" in the last resort, and the
`move' forms before the general type lookup in `cpp_arg_type' -- BROKE
`stdstring.cpp` and were reverted. The overload rules interact, and a change to
one is worth no more than the gate it passes. Seven gates GREEN.

**M6's thirty-seventh step (0.69): A NAME IS NOTED WHEN IT IS EMITTED, NOT
BEFORE.** 0.68 left `std::vector<std::string>` stopping at
`undeclared('allocator<string>::construct...')` -- the member template NOTED as
an instance and never EMITTED -- and the refusal added there did not fire,
which said the emission was not failing but being SKIPPED. THE ANSWER: a
member template's instance is made wherever its call is MET, and that can be
INSIDE another candidate's signature check, whose catch swallows the refusal
and rejects the candidate -- SFINAE, by design, since 0.44. The note was taken
BEFORE the emission (to stop a recursive ask looping) and SURVIVED the
abandonment, so every later ask answered with a definition that had never been
emitted and the lowering met a call to nothing. The name is IN PROGRESS while
the emission runs -- which is all a recursive ask needs -- and NOTED only once
it is done; a throw clears it, as `cpp_isolated` and `cpp_in_class` already
restore what they set aside (`'$cpp_making'`, `cpp_make_member/9`). THE SAME
SHAPE SAT IN `cpp_use_member`, a LAZY class's member emitted where it is first
named (`cpp_make_lazy/5`): that is how `basic_string`'s own MOVE CONSTRUCTOR
was lost. TWO MORE from the same probe. A type that is KNOWN but names no class
-- a library template's raw, unsubstituted result -- no longer hides the
DESUGARED form from `cpp_init_arg_class`, which 0.66 taught to ask it and 0.68's
`cpp_arg_type` had short-circuited. And the MOVE FORMS come before the general
type lookup in `cpp_arg_type`: `<utility>` arrives with every container, so
`std::move` is a DECLARED template whose raw result type would otherwise win --
tried in 0.68, reverted with an innocent change beside it, and measured alone
here. AND BOTH CANDIDATE FILTERS ARE DETERMINISTIC NOW: `cpp_args_fit` and
`cpp_args_no_clash` each had two base clauses that matched the empty case, so
`findall` returned a candidate TWICE -- 0.66's lesson (`cpp_keep_defaults`) in
two more places. Lowering version 23. WHERE IT STANDS:
`std::vector<std::string>` compiles through the desugaring AND the safe part
whole, in 10 s at 713 MB, emitting `allocator<string>::construct` and
`basic_string`'s move constructor -- two defects further than 0.68 -- and stops
in the LLVM it emits, inside that move constructor: `__rep_(std::move(
__str.__rep_))` still picks `__rep(__short)` by arity where the implicit
bitwise copy is meant. The member-initializer overload choice is the next step.
Seven gates GREEN; no new fixture, the libc++ fixtures being what these rules
are measured by (each broke while they were wrong).

**M6's thirty-eighth step (0.70): A VECTOR OF STRINGS -- libc++ holding
libc++.** Two rules, both about reading a parameter for what it is. (1) A
MEMBER INITIALIZER'S OVERLOAD CHOICE READS ITS PARAMETER IN ITS OWN CLASS'S
WORDS. `cpp_args_no_clash`, the filter on the arity-only last resort, tested the
RAW parameter type, and libc++'s union-class writes `__rep(__short __r)' with
its holder's NESTED names -- which the inference cannot resolve, so
`cpp_class_of_type` failed, the clash went unseen and
`__rep_(std::move(__str.__rep_))' took `__rep(__short)' by arity: a union stored
into a byte. It goes through `cpp_param_ref` now, the door `cpp_arg_fit` has
used since 0.66 -- the same rule as 0.65's and 0.66's, in the one place that
still missed it. (2) A CONVERTING CONSTRUCTOR SERVES A PARAMETER THAT BINDS A
TEMPORARY, not only a by-value one: a const lvalue reference or an rvalue one,
for which C++ materializes one (`cpp_param_takes_class/2`). And TEMPLATE
constructors count (`cpp_converting_ctor`'s second clause, over `'$cpp_mt'`),
since libc++ writes `basic_string(const _CharT *, const _Allocator & =
_Allocator())' as one -- which is the whole of how `v.push_back("alpha")' makes
a string out of a `const char *'; without it the `const char *' went to
`push_back(const_reference)' as though it were a string, and the vector held a
pointer to a literal. A clash that a converting constructor BRIDGES is no
clash, which is what keeps `__reset_internal_buffer(__long)' -- `__rep(__long)'
-- alive beside (1). Lowering version 24. WHAT RUNS: `std::vector<std::string>`
pushes four strings, one of them past the short-string bytes, grows its buffer
twice relocating them, subscripts, is walked by a RANGE-FOR and destroys them
all -- clang++'s numbers, `leaks` finds none, 825 MB to build. Gated by
`test/cpp/run/stdvectorstring.cpp`. Seven gates GREEN (the C++ one 805 MB).
NOT DONE: `vector<string>`'s `insert`, `erase` and `resize`; a `string` as a
class's member; `std::map` and the associative containers; `<iostream>`.

**M6's thirty-ninth step (0.71): THE ROAD TO `<iostream>` -- read whole,
`std::cout` named by its symbol, and fourteen forms between the include and
the locale.** THE READER (version 47), by the census loop, eleven gaps:
C23's `_BitInt(N)`; the GNU spellings `__signed`, `__const`, `__volatile`,
`__restrict`, `__inline` and their `__x__` forms (`ccl_gnu_word/2`, one clause
per word, one rule for all); a NESTED CLASS DEFINED OUT OF ITS ENCLOSING CLASS,
`class locale::facet : public __shared_count { ... }`, read as `class(K,
scoped([locale], facet), ...)` (`ccl_class_qual`, and `ccl_current_class` sees
through the scoping); an enumerator with attributes; `virtual` on either side
of the access word in a base clause; a member template's name after
`template`; `new T[n](args)` and `new T[n]{...}` as `new_array_init` (refused
by name); `__int128_t` and `__uint128_t` in the typedef seed; `extern "C++"`
TRANSPARENT -- its items spliced where it stood (`'$splice'`, the door macros
use), where `extern "C"` keeps its block -- both spellings had been one item,
and libc++'s `<math.h>` wrapping `namespace std` in one put a namespace under
the C marker, on which `ccl_flat_items` FAILED and the header's AST beside the
summary was never written (the stale one of an older, 74-item read served,
and `cout` was not in it -- the silent failure that hid everything below); and
A TYPE TEMPLATE ARGUMENT NAMES NO DECLARATOR (`ccl_targ_type`): `__conditional_t<
is_copy_assignable<first_type>::value && is_copy_assignable<second_type>::value,
pair, __nat>` read `...::value &&` as an rvalue reference whose declarator-id was
the second half, and libc++'s `pair` lost half its condition. THE AST BESIDE
THE SUMMARY: a failed write is traced (`ast_not_written`), `ccl_flat_items`
keeps the C marker under a namespace, the text is built A HUNDRED ITEMS AT A
TIME inside `\+ \+` (`ccl_ast_chunks`; the cold read of `<iostream>` 2598 ->
1987 MB, the same bytes) and the summary's sections are lists of TERMS made
into text the same way (`ccl_sum_chunks`); and since its content follows
`cpp_index_name/2`, A CHANGE THERE BUMPS THE READER VERSION TOO -- the only
stamp the file has, and a stale one served the old index silently. THE EXTERN GLOBAL: `extern ostream cout;` is
indexed (`cpp_index_name` on an extern declaration), registered on the first
ask (`cpp_lazy_var`) under the symbol libc++ exports, `_ZNSt3__14coutE`
(`cpp_mangled_var`: the header's namespace path `[std, __1]` from
`'$cpp_hdr_ns'`, checked against `nm` of `libc++.tbd`), and `cpp_global_var/2`
gives `std::cout` and a bare `cout` that name. THE DESUGARING, seven forms,
each with a ten-line reproduction that ran in a second where the probe took
ten: (1) A NESTED ENUM is a type of the class that holds it, as a nested class
is (`cpp_nested_enum`: one tag `Enclosing.Name` at file scope, its enumerators
global names as every enum's are) -- `ios_base::seekdir`; and a scope path ENDS
at a nested enum (`cpp_scope_walk`), where `B::strong::two` had become the
static member `B.two`. (2) A NESTED CLASS DECLARED IN ITS HOLDER AND DEFINED
OUT OF IT: `scoped([locale], facet)` is `locale.facet` in the index, the
registrations and the emission (`cpp_class_item_name`), the forward
declaration `class facet;` names the type (`cpp_nested_name`'s `class(N,
none)` clause, no class registered for it), and the holder's types are in
scope inside (`cpp_encloses`). (3) MULTIPLE INHERITANCE WHERE EVERY BASE AFTER
THE FIRST IS EMPTY -- no data, no slots, nothing to construct: C++'s empty base
optimization gives it no bytes, so it is a SCOPE and no sub-object here
(`cpp_extra_bases`, `cpp_empty_class`, `'$cpp_extra'`), and `cpp_base_scope/2`
is the one door every base lookup goes through -- typedefs, static consts,
static members, `cpp_has_member`, a method (`cpp_extra_method`, the object's
own address being the base's); a second base WITH storage or slots is refused
as before. `ctype<char> : public locale::facet, public ctype_base`. (4) A PURE
VIRTUAL SLOT NOTHING OVERRIDES holds a NULL in the table (`cpp_slot_def`), where
the link named `SC.zero.0` and nothing defined it -- `__shared_count::
__on_zero_shared() = 0`; `cpp_not_abstract` still never fires, since
`cpp_slot_impl` answers the pure declaration, a gap older than this step. (5)
THE DEFAULT-ARGUMENT DROP RAN OFF THE END: a method's recorded defaults do not
count `this`, and a call the desugaring had already built carries it, so
`cpp_drop` had no clause and the whole constructor walk FAILED -- silently --
on `facet(size_t __refs = 0) : __shared_count(static_cast<long>(__refs) - 1)`
(`cpp_drop(_, [], [])`; `ctor_walk_failed` prints the body now). (6) THE
IMPLICIT DEFAULT CONSTRUCTOR C++ DELETES: a member whose class has no default
constructor leaves its holder without one, and the class stays the aggregate
it was written as (`cpp_members_default`, `cpp_default_ctor_exists`, a test
that emits nothing) -- `__in_out_result` holding an `ostreambuf_iterator`,
built `return { a, b }`; making the constructor refused the whole class. (7)
AN ALIAS NAMED AS A BASE names the INSTANCE (`cpp_base_name` asks `cpp_class`
of the atom first): `__libcpp_is_contiguous_iterator<char *> : true_type`.
Lowering version 25 (the null slot). WHERE `std::cout << "hello"` STANDS: the
desugaring goes through `basic_ostream<char>`, `basic_ios`, `ios_base`,
`basic_streambuf`, `locale::facet`, `__shared_count`, `ctype<char>`,
`__pad_and_output` and `std::copy`'s `__unwrap_range` -- 236 loads and
instances, 1166 trace lines, 9 s and 816 MB warm -- and stops at
`std::pair<char *, char *>`'s constructors: every one is a template whose
parameter `__enable_if_t<_CheckArgsDep::template __is_pair_constructible<_U1,
_U2>(), int> = 0` asks a CONSTEXPR STATIC MEMBER FUNCTION TEMPLATE to be
EVALUATED AT COMPILE TIME (its body one `return is_constructible<_T1,
_U1>::value && ...`); taken for a class template it refuses
`template_without_body(__is_pair_constructible)`, and every two-argument
constructor is rejected. A constexpr function of one `return` could fold as a
static const's initializer does (`cpp_fold_static`: instantiate, desugar in
the class's words, `ccl_const_eval`) -- the next stretch, and named. Gated by
`test/cpp/run/nestedenum.cpp` (plain and scoped, as a member's type in a
template) and `test/cpp/run/facet.cpp` (the facet shape whole: declared in,
defined out, an abstract first base, an empty second, a defaulted base
constructor, the slot filled by the derived class), clang++'s numbers; and
`<iostream>` read WHOLE in `test/libcxx.pl` (662 items). Seven gates GREEN
(the C++ one 2245 MB, the libc++ one 1743 MB with `<iostream>`; a cold read
of `<iostream>` alone 2009 MB, under the 2800 MB cap the owner set).

**M6's fortieth step (0.72): THE CONSTEXPR FUNCTION, and the road to a running
`std::cout` -- `cicili: ok` to the link, five symbols short.** THE STEP ASKED
FOR: a constexpr function of ONE `return' FOLDS where a constant is wanted
(`cpp_const_value/2`, the door `cpp_targ_value` and `cpp_fold_static` now take
constants through): the instance is emitted as any member template's is, its
body read back from the emitted item (`'$cpp_out'`), already desugared in its
class's words so the traits in it are constants, its parameters bound to the
call's arguments (`cpp_param_binds`, `cpp_replace_ids`; `this' to the null it
was passed), the return's expression folded -- bounded in depth, since such a
function may call itself. With it, TWO READINGS the class knows better than
the reader: `X::template f<U>()' in a template argument reads as a FUNCTION TYPE
returning `X::f<U>' (the reader cannot know f is a member function template;
the class can: `cpp_targ_value`'s `fn(scoped(_, tmpl(M, _)), [], false)`
clause makes it the call), and a qualified member template call with its
arguments given (`cpp_call`'s `scoped(Path, tmpl(M, TArgs))` clause). libc++'s
`pair` chooses every constructor by `__enable_if_t<_CheckArgsDep::template
__is_pair_constructible<_U1, _U2>(), int> = 0', and `std::pair<char *, char *>
q(p, p)` runs. Gated by `test/cpp/run/constexprfn.cpp` (the shape on the
program's own classes, a static const from a constexpr call with an argument,
the same function called at run time) and `stdtraits.cpp`.
THE ROAD, followed from there to the link, twenty-three forms, each with its
reproduction: (1) a pack in a BUILTIN TRAIT's arguments expands
(`type(pack(T))` in `cpp_subst_elems`: `__is_constructible(_Tp, _Args...)`);
(2) an AGGREGATE TEMPORARY's `operator()` (`cpp_temp_call` for a compound
literal: `_Algorithm()(a, b, c)`, its block made here) -- `aggcall.cpp`; (3)
`__remove_cv`, `__remove_const`, `__remove_cvref` of a POINTER
(`cpp_strip_quals`: they took only a specifier list, and `is_void<char *>` is
`_BoolConstant<__is_same(__remove_cv(_Tp), void)>`); (4) `X::f(args)' ON A
CLASS WITHOUT SUCH A MEMBER REFUSES (`no_member(C, M, K)`), the rejection the
detection `decltype((void) pointer_traits<P>::to_address(...))` needs --
flattened to a global name it was void either way and every pointer had a
`to_address`; (5) `typename _Tp::x' WITH `_Tp` A SCALAR, a pointer, a reference,
a function: the segment carries the type (`nonclass(A)`, `cpp_subst_path`) and
resolving the name refuses (`cpp_type`, `cpp_expr`), where the parameter's name
stayed in the path and flattened as a namespace into a FREE NAME (unique_ptr's
deleter, a function pointer, asked for `::pointer`); (6) a `static' POINTER or
ARRAY member is a static (`cpp_static_type`: the word sits in the innermost
base's qualifiers, and `static const char __src[33]' was DATA, so a class of
statics alone was no empty base) -- `staticbase.cpp`; (7) A LAZY POLYMORPHIC
CLASS EMITS ONLY WHAT ITS TABLE NAMES (`cpp_slot_fns`: its own slot
implementations, IN PROGRESS while their bodies are walked -- uflow calls
underflow -- and noted after), where it emitted every member: `std::cout <<
"hello"' walked 234 members, `operator<<(double)`, `swap`, the whole input
side, and the run fell 363 -> 113 instances, 17 -> 6 s (the trace
`make_lazy(Name)` says which member a program pulls in); (8) a slot's RESULT
type resolved in its class (`cpp_slot_ret`: `virtual int_type uflow()` reached
the lowering raw in the table's struct); (9) A DESTRUCTOR A LIBRARY HEADER
DECLARES AND THE SHIPPED LIBRARY DEFINES is called by its Itanium name
(`cpp_dtor_name`: `_ZNSt3__18ios_baseD1Ev`, `_ZNSt3__16localeD1Ev`, a nested
class by its segments; a template instance's nested class keeps its own name,
`cpp_plain_lib_class`); (10) THE VIRTUAL DESTRUCTOR TAKES TWO SLOTS
(`'$dtor_del'`), the Itanium layout -- and it must, since a virtual call INTO an
object the library made (cout's streambuf, its `overflow`) indexes that
object's own table, and with one entry every slot past the destructor was off
by one; (11) VIRTUAL INHERITANCE, as the ABI lays a COMPLETE OBJECT out
(`'$cpp_vbase'`, `cpp_base_layout`): the class's own table pointer first, its
own members, the shared base LAST -- `basic_ostream : virtual public basic_ios`,
where cout is the ostream's vptr and the basic_ios at offset 8 (measured with
clang++: 160 = 8 + 152) and every field we read sat eight bytes off; the
class's table holds its own virtuals (`cpp_vbase_dtor_slots`: the base's
virtual destructor makes its own slots, first), a destructor is virtual by
`override' too, and a class with a virtual base and no destructor gets the
implicit one (its base's runs on the sub-object where it lies); the reader
KEEPS `virtual' on a base (`base(virtual(A), Q)`, reader version 48) --
`virtualbase.cpp` (clang++'s offsets and size); (12) A DISPATCH READS THE
OBJECT'S OWN CLASS'S TABLE (`cpp_dispatch` casts the pointer to `C.vt`, the
tables laid out base first: `ctype<char>::widen` found no `do_widen` in
`__shared_count.vt`); (13) `return { a, b }' builds the RESULT TYPE's object,
through its constructor or as the aggregate; (14) A NESTED CLASS OF A LAZY
CLASS IS LAZY (registered eagerly, `sentry' walked its constructor, which
calls flush(), whose body declares a sentry -- mid-registration, so the ask
failed and the local was a plain value), and `cpp_nested_ready` clears its
in-progress mark on a throw (0.69's rule); (15) A NESTED CLASS DEFINED OUT OF
ITS CLASS TEMPLATE, `template <...> class basic_ostream<_CharT,
_Traits>::sentry { ... }' (`cpp_mdef_item`'s class clause, `cpp_member_shape`
for `nested(...)`: kept by the class's name like a member's body and merged
into the instance's forward declaration; reader version 49, since the index
changed); (16) A POINTER PARAMETER TAKES BY WHAT IT POINTS TO
(`cpp_pointer_fit`: `void *' any object pointer, a FUNCTION pointer only a
function, a class one a class -- scored as any two pointers, the manipulator
inserter `operator<<(basic_ostream &(*)(basic_ostream &))' took `cout <<
"hello"', and the literal was CALLED: SIGBUS at the literal's address); (17) A
FREE OPERATOR THAT FITS EXACTLY BEATS A MEMBER THAT NEEDS A CONVERSION
(`cpp_member_exact`, `cpp_free_operator_call`: C++ weighs them together, and
`cout << "hello"' is the free template over `const _CharT *', never the member
over `const void *'); (18) A SCALAR PARAMETER NEVER TAKES A CLASS ARGUMENT
without a conversion operator, in the arity-only last resort too
(`cpp_args_no_clash`: `__s = std::copy(...)' on an ostreambuf_iterator took its
`operator=(char)' and the struct was sign-extended to a byte); (19) A CLASS
VALUE WHERE A BOOL IS WANTED converts through its `operator bool'
(`cpp_to_bool`: if, while, do, for, `!', `&&', `||' -- the contextual
conversions, an explicit one included: a stream's sentry, `if (__s)'); (20) THE
SPECIALIZATION ORDERING takes a template-id over opaque names as an INCOMPLETE
INSTANCE (`cpp_opaque_types`, 0.58's shape): `ostreambuf_iterator<$opaque._CharT,
...>' instantiated refused, so that `__pad_and_output` was no more special than
the generic one and the tie went to the first declared; (21) `__to_address` and
`std::is_void` on pointers, `is_copy_assignable`, all C++'s answers now
(`stdtraits.cpp`); (22) ON THE C SIDE, a global char array initialized from a
SHORTER literal is zero-filled to its bound (`ir_str_tail`: `char s[33] =
"abc"' was refused by LLVM, `[17 x i8]` into `[33 x i8]`); (23) the AST beside
the summary bumped the reader version twice more, as the rule says; (24) IN THE
LOWERING, A POINTER OR A REFERENCE TO A DERIVED OBJECT CONVERTS TO ITS BASE BY
THE BASE'S OFFSET (`ir_convert`'s class-pointer clause, `ir_base_path`,
`ir_base_hops` over the `$base' members; `ir_ref_to` at the three binds -- a
local reference, a reference parameter, a cast to a reference): every base
sat at offset 0 until now, so `A *base = &x' copied the pointer unchanged and
`base->twice()' read `b''s bytes, the gate's first RED of this step; a null
pointer is not spared the offset (not done). Lowering version 27 (the
table's shape, the conversion). WHERE `std::cout << "hello"' STANDS: it
desugars, passes the safe part, lowers and reaches the LINK -- `cicili: ok' up
to it -- FIVE SYMBOLS SHORT, each named: the constructor and the destructor of
`basic_ostream<char>::sentry`, members of a nested class DEFINED OUT OF ITS
CLASS TEMPLATE (the member-definition index keys them under the nested name
alone, and the merge does not reach into a nested class's members);
`__num_put_base::__identify_padding(char *, char *, const ios_base &)`, a
declared-only STATIC MEMBER of a plain class, shipped as
`_ZNSt3__114__num_put_base18__identify_paddingEPcS1_RKNS_8ios_baseE` -- the
SUBSTITUTIONS `S1_` and `NS_...E` that 0.61 left undone; `ctype<char>::do_narrow(char,
char)`, a declared-only member of a template SPECIALIZATION,
`_ZNKSt3__15ctypeIcE9do_narrowEcc` -- a template's instance in a mangled name,
also undone since 0.61; and `__to_chars_integral`'s instance
`.c1.unsigned_long.0`, noted and never emitted. The next stretch is the
Itanium mangler's second half and the nested class's out-of-class members. The
build is 11 s and about 1000 MB warm; the cold read of `<iostream>` 1425 MB.
Gated by `test/cpp/run/constexprfn.cpp`, `aggcall.cpp`, `staticbase.cpp`,
`virtualbase.cpp` and `stdtraits.cpp`, clang++'s numbers. Seven gates GREEN
(the C++ one 1140 MB, the libc++ one 1811 MB).

**M6's forty-first step (0.73): THE ITANIUM MANGLER'S SECOND HALF, and
`std::cout << "hello, cicili++\n"` RUNS.** THE MANGLER (`cpp_ita_*`): what
0.61 spelled -- `_ZN', a namespace, a name, `E', builtin parameters, refusing
any repeat -- is spelled with the ABI's SUBSTITUTION TABLE threaded through
(`cpp_ita_sub`, `cpp_ita_note`: every prefix, nested name and non-builtin type
a candidate in order, its second occurrence `S_', `S0_', `S1_' ... in base 36),
a class a NESTED NAME (`N <prefix> <len>name E'; `St' for std, no candidate;
`St3__1' one), a template instance `<len>name I <args> E' (its template-name
prefix a candidate; as a TYPE the instance itself, as a member's PREFIX the
template-id too -- the two cases clang++ told apart: `ff(string, string)' ends
`S5_', `tw<char>::two(ct2<char>, ct2<char>)' `S3_'), `K' after `_ZN' for a const
method, a function directly in std UNSCOPED (`_ZSt19uncaught_exceptionsv'),
`C1' and `D1' for a constructor and a destructor (0.72's `cpp_dtor_name`
folded in). MEASURED against clang's own symbols for six shapes, all six equal.
AT ONE DOOR, `cpp_mangle/4`: a member a library header DECLARES and the shipped
library DEFINES (`cpp_shipped_member`: no body in the class's list AND no
out-of-class definition in the header, `cpp_defined_out_of_class`; the
parameters RESOLVED IN THE CLASS before spelling, `do_narrow(char_type, char)'
being written in ctype's words) is named by its symbol where it is declared,
called and slotted -- `__num_put_base::__identify_padding',
`ctype<char>::do_narrow', `locale::use_facet'; a shipped STATIC DATA MEMBER
alike (`cpp_static_name': every facet's `static locale::id id',
`_ZNSt3__15ctypeIcE2idE'). What the encoder cannot spell keeps its own name, and
the link names it. ON THE WAY TO THE LINK AND PAST IT, twelve more: (1) THE
MEMBERS OF A NESTED CLASS DEFINED OUT OF ITS CLASS TEMPLATE, `template <...>
basic_ostream<_CharT, _Traits>::sentry::sentry(basic_ostream &)': the reader
keeps the enclosing path on such a constructor or destructor (`ctor_def(L,
scoped([tmpl(basic_ostream, ...)], sentry), ...)`, reader version 50; the bare
name had lost which class's sentry it was), the index keys them under the
enclosing class (`in_nested(N, M)', the key `nested_member(N, K)'), and the
merge reaches into the nested class's members once the class is whole
(`cpp_nested_defs`, `cpp_member_def_key`); (2) A PLAIN CLASS'S OUT-OF-CLASS
BODIES, `inline ios_base::fmtflags ios_base::flags() const { ... }', indexed
by the class's name, noted BEFORE the batch registers (`cpp_note_hdr_mdefs`:
the class item comes first in the header) and merged in `cpp_lazy_class` --
unindexed, `flags()' took the mangled road and libc++ hides it from its ABI;
(3) a nested class KNOWN BY NAME ALONE (`class locale::id', forward-declared,
defined out of class) loaded when its name resolves as a type
(`cpp_touch_nested`), so its struct exists for the lowering; (4) A HEADER'S
INLINE VARIABLE -- C++17's, defined in the header with its initializer,
exported by no library: libc++'s digit tables, `__digits_base_10',
`__pow10_64' -- indexed and emitted as a `linkonce' global by the program
that names it (`cpp_lazy_inline_var`, its items desugared; reader version 51,
the index changed); named through the summary alone it was an `external
global' and the link named five; (5) 0.69's RULE IN ITS THIRD AND FOURTH
PLACES: a function template's instance (`cpp_instantiate_function_`) and a
library free function's overload (`cpp_use_fn`) are noted when EMITTED, in
progress while they emit -- `__to_chars_integral' was declared and never
defined; (6) A HEADER'S LOAD DECLARES AT FILE SCOPE (`cpp_isolated` around
`cpp_register_lazy`): met inside a function's body walk, a load declared the
header's functions into that function's open frame -- `ccl_declare` takes the
innermost -- and they went with it: `__convert_to_integral.unsigned_long'
declared in one walk, undeclared at the next call, its type unknown and
`_Size' undeducible; (7) A FUNCTION TEMPLATE'S REDECLARATION TAKES THE DEFAULTS
OF ITS FIRST DECLARATION (`cpp_fn_merge_defaults` over the candidates with the
same template parameters, kind for kind and name for name, through 0.44's
`cpp_merge_defaults`): C++ lets a default template argument stand on the first
declaration only, and libc++'s definition of `__to_chars_integral' refused
`cannot_deduce(anon)' while its prototype held and was emitted as a declare;
(8) A NAME QUALIFIED BY A PARAMETER IS A NON-DEDUCED CONTEXT in a function
parameter too (`cpp_path_dependent` in `cpp_match`): `typename
_IterOps<_AlgPolicy>::template __difference_type<_InIter> __n' binds nothing
and resolves once the others bind it -- taken for a class template by its last
segment it refused deduction_failed; (9) NO STANDARD CONVERSION between a
pointer and an arithmetic parameter in a template's acceptance
(`cpp_scalar_mismatch`: a bool takes a pointer, nothing else does) --
`cout << "hello"' took the CHAR inserter and passed the literal's address
truncated to a byte; (10) A QUALIFIED CALL INSIDE A CLASS PASSES `this'
through the base sub-objects, never virtual (`cpp_base_hops`; a static
method keeps its null): libc++'s basic_ios forwards `good()' as `return
ios_base::good();', and it went out with a null this -- SIGSEGV in
`ios_base::good'; (11) THE BIT BUILTINS AT RUN TIME are LLVM's intrinsics
(`ir_bit_builtin`: `__builtin_clz*', `ctz*', `popcount*' and the generic `g'
forms with their second argument, over the argument's own width, a raw
`declare' line since `i1' has no C spelling) -- 0.60 folded them where the
argument was a constant, and `__countl_zero' calls one at run time; (12) A
CLASS THAT IS NOT TRIVIALLY COPYABLE OR DESTRUCTIBLE CROSSES A CALL BY
INVISIBLE REFERENCE and comes back through a hidden pointer, WHATEVER ITS
SIZE -- the Itanium C++ ABI's rule on both architectures, which the shipped
library follows: `ios_base::getloc()' returns a `locale', one pointer wide with
a destructor, through sret, and taken as a register value the library wrote
its result over `this' -- SIGSEGV in `locale::locale(const locale &)'. The
desugaring marks such classes (`'$cpp_nontrivial'`, `cpp_note_nontrivial`: a
destructor, a copy or move constructor, a virtual function, or a base or a
member that is such) and the lowering classifies them `indirect'
(`ir_nontrivial_class` in `ir_abi_`); the program's own classes follow the
same rule on both sides of every call. Lowering version 28. WHAT RUNS:
`std::cout << "hello, cicili++\n"' -- the library's own object, written to
through libc++'s basic_ostream, its sentry, ostreambuf_iterator,
`__pad_and_output', std::copy and the streambuf's virtuals into libc++'s
`__stdoutbuf' -- and a chained `<< "one " << "two\n"'; 19 s and about 950 MB
warm, the cold read of `<iostream>` 1498 MB. Gated by
`test/cpp/run/stdcout.cpp` and the mangler's check in `test/cpp.pl` (clang's
six symbols). Seven gates GREEN (the C++ one 2125 MB, of which the fixture
itself is 917 -- the peak is the cold flatten of `<sstream>` and ten more
headers the reader's fixtures pull in after the version bump, rewritten inside
the gate; the libc++ one 1833 MB). NOT DONE: the ostreambuf `__pad_and_output' still loses to the
generic one (a conversion counted on the temporary; it works through
std::copy); `std::endl', a number inserted (`num_put', walked and untested),
`std::cin'; a function-type or array parameter in a mangled name; a null
pointer converted to a base at an offset; explicit constructors in the
acceptance test.

**M6's forty-second step (0.74): `std::endl` -- A FUNCTION TEMPLATE'S NAME AS
AN ARGUMENT.** `cout << "hello" << std::endl' hands `endl' -- a function
TEMPLATE, `basic_ostream<C, T> &endl(basic_ostream<C, T> &)' -- to the member
`operator<<(basic_ostream &(*)(basic_ostream &))', and C++ deduces the
template's arguments from the TARGET, the function type the pointer parameter
names ([temp.deduct.funcaddr]); everywhere else a template's name is a
NON-DEDUCED CONTEXT ([temp.deduct.call]/6). Here the inference typed
`std::endl' as the template's RAW signature (a function template is declared
under it, 0.49), `basic_ostream<_CharT, _Traits>' with both names free, and
`_Traits' met a stray BLOCK TYPEDEF of another template's body (`using _Traits
= __segmented_iterator_traits<_SegmentedIterator>' in `__for_each_segment',
in the unit-wide table since 0.43 kept a function's block typedefs there):
`basic_ostream<_CharT, __segmented_iterator_traits<_SegmentedIterator>>' was
instantiated on the free names, then `basic_ios', `basic_streambuf' after it,
115,000 flattens and 412 s to the 2800 MB cap. THE RULE, at the one door an
argument's type has (`cpp_arg_type`): a name that is a function template's
and no local's (`cpp_fn_template_ref`, `id(F)' or `std::F') is `tmplfn(F)',
no type of its own; a candidate's FUNCTION-POINTER parameter (or a reference
to a function, or a function type) DEDUCES it -- `cpp_target_deduces`,
`cpp_target_bindings`: the template's parameter types against the target's,
reference for reference (`cpp_match_target`, since a target is matched
exactly where a call's argument decays), then its result, the defaults and
the constraints, the first candidate of the name that holds, a refusal
inside being no candidate -- and scores it EXACT (`cpp_arg_fit_` 3,
`cpp_arg_exact`, `cpp_param_accepts`); any other parameter takes it not at
all (0); a call's deduction binds nothing from it (`cpp_deduce_one`); and
where the candidate is chosen (`cpp_ref_args_`, the door the member call and
the operator form share) the argument BECOMES THE INSTANCE'S NAME, emitted as
any instance is (`cpp_deduce_target` -> `cpp_instantiate_function_`). Of
basic_ostream's three manipulator inserters only the `basic_ostream &(*)
(basic_ostream &)' one deduces `endl'; the `basic_ios &' and `ios_base &'
ones refuse. TWO MORE it uncovered: A FUNCTION POINTER TAKES ONLY A FUNCTION
OF ITS TYPE (`cpp_pointee_fit` through `cpp_fn_types_agree`: parameter for
parameter and the result, the names dropped; a function DECAYS to a pointer
in `cpp_pointerish`) -- 0.72's `cpp_pointer_fit` let a function pointer take
any function, and `std::hex', `ios_base &(ios_base &)', would have gone to the
first inserter and been called on the wrong sub-object; and A FUNCTION TYPE
KEYS BY ITS RESULT AND ITS PARAMETERS' TYPES, never their names
(`cpp_type_key(fn(...))', `fn_<result>_<params>_p') -- the generic flattening
put the parameter NAMES in, so `(*pf)(basic_ostream &)' declared and
`(*__pf)(basic_ostream &__os)' defined out of class were two members. WHAT
RUNS: `endl' from its own body -- `__os.put(__os.widen('\n'))' through a
sentry and an ostreambuf_iterator, `__os.flush()' through `rdbuf()->pubsync()'
into the streambuf's virtual `sync' and libc++'s `__stdoutbuf' -- and the
inserter's `return __pf(*this);', a call through a function-pointer
parameter; `std::flush' is the same road. Gated by `test/cpp/run/stdendl.cpp`
(after a literal, chained twice, `std::flush', `endl' alone), clang++'s lines;
18 s and 917 MB warm, no more than the hello; the C++ gate GREEN at 1694 MB,
the only gate the change touches. Reader version 51 and lowering version 28
unchanged. NOT DONE: an OVERLOAD SET of plain functions as an
argument (C++ picks by the target; here a name has the one declared type);
`std::hex' and kin scored by type now but not gated; `<iomanip>''s
manipulators, which are classes; a number inserted (`num_put'), `std::cin'.

**M6's forty-third step (0.75): `std::cin` -- THE EXTERN TEMPLATE'S INSTANCE IS
SHIPPED, and the string's true layout.** `cin >> n' in clang's own object is a
call to `_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEErsERi' -- the library
holds `basic_istream<char>' whole (`extern template class basic_istream<char>;'
in the header), and the num_get machinery behind the extractor is never
compiled by a program. THE SAME HERE: an `extern template class X<Args>;' item
of a library header is indexed by the template's name and noted at the load
(`cpp_note_extern`, `'$cpp_extern'(N, Args, all)`); an instance of N with those
arguments first (the defaults fill the rest) does NOT take its out-of-class
member definitions at the merge (`cpp_member_def_key` asks `cpp_extern_shipped`),
so they stay DECLARED, and a declared member of a library class is called by its
Itanium name (0.73's `cpp_shipped_member`, now for an operator member too, whose
clause had sat before the door with a cut). WHICH MEMBERS: libc++ hides a member
from its ABI with `_LIBCPP_HIDE_FROM_ABI', which this preprocessor spells as
visibility hidden plus always_inline; every such out-of-class definition of the
four stream classes is written `inline' and every exported one without it
(measured on the flattened `<iostream>`: 41 + 29 + 16 definitions, no
exception), so the `inline' the reader keeps (`cpp_mdef_item`'s Qs) is the mark,
no attribute kept; a member with its body in the class stays compiled (libc++
writes those hidden without exception); never a nested class's definition, never
a member TEMPLATE (a second template wrapper: no explicit instantiation covers
one). The other spelling, `extern template void basic_string<char>::__init(const
value_type *, size_type);' -- libc++ lists its string's exported members one by
one -- names ONE member by its name and its parameters as written
(`'$cpp_extern'(N, Args, member(M, K))`). WHAT THE INDEX CHANGE COST: reader
version 52, every summary rewritten. THE MANGLER, twice more: an operator member
by the ABI's code (`cpp_ita_op`: `rs', `ls', `pL' ...; a member with no
parameter the unary one, `cpp_ita_unary`), and THE KEY OF A CLASS TYPE IS ITS
CHAIN'S OWN, as a prefix level's is -- the ABI counts `basic_istream<char>' the
prefix and the type as ONE entity, and with `N ... E' around the type's key the
sentry's constructor spelled its parameter afresh (`RNS0_IcS2_EE') where the
library has `RS3_'; c34 spells nine symbols now, the two sentries and
`operator>>' among them, checked against the shipped library's export list.
THREE MORE THE FIXTURE ASKED: (1) A STATIC NAMED THROUGH AN OBJECT, `__ct.space'
(`cpp_static_through_object` in the member and arrow clauses of `cpp_expr`):
ctype_base's masks through the facet, which C++ allows and the lowering met as a
data member that was not there; (2) `m()' WRITTEN OUT IN A MEMBER INITIALIZER IS
VALUE-INITIALIZATION, which ZEROES a class whose default constructor is not
user-provided (`memset' over the member, `cpp_member_inits`): basic_string's
`: __rep_()' left the union as garbage, its `__is_long_' bit read long and
`clear()' wrote through a null pointer; (3) A BITFIELD KEEPS ITS WIDTH
(`cpp_split_members` had replaced every member's third argument with `none';
`cpp_bit_width` folds it in the class's words as an array's bound is): libc++'s
string is `__is_long_ : 1; __size_ : 7' in its short form and `__is_long_ : 1;
__cap_ : 63' in its long one, and with the widths dropped each was a whole byte
or word -- the string 40 bytes where the library's is 24, self-consistent, so
the string fixtures never knew; the library's own `push_back' wrote by its
layout and our `size()' read by ours. `sizeof(std::string)' is 24 now, as
clang's. THE GATE reads a fixture's input from `NAME.stdin' when it exists, else
nothing (`/dev/null'). WHAT RUNS: `test/cpp/run/stdcin.cpp` -- `cin >> n >>
word', `cin >> d', `cout << n * 2 << " " << word << endl', `cout << d + 0.5 <<
endl' -- an int, a word and a double read through the shipped extractors (the
string's through libc++'s hidden template compiled here: the istream sentry
shipped, `rdbuf()->sgetc()' and `sbumpc()' into the streambuf's virtuals,
`ctype<char>::is', the shipped `push_back'), the numbers written through the
shipped inserters; clang++'s lines, 34 s and 895 MB warm. Not one C++ symbol
in the object is outside the library's export list. Seven gates GREEN (the C++
one 1407 MB, 103 checks; the libc++ one 1753 MB; the cold read of `<iostream>`
1949 MB with the extern items in its AST). NOT DONE: `std::getline',
`cin.get()', `cin.fail()' as a test, the manipulators (`std::hex', `setw'),
formatted floating input past a plain double, `std::cin' tied flushing checked
only through the lines printed.

**M6's forty-fourth step (0.76): `std::getline` -- six forms in libc++'s own
body.** `std::getline(cin, line)' is a hidden template compiled from the header
(`getline(basic_istream<C, T> &, basic_string<C, T, A> &, C)': a sentry, the
buffer's `gptr()' and `egptr()' span, `char_traits::find' over it, an append,
a lambda that bumps the stream), and the member `cin.getline(buf, n)' the
shipped `basic_istream<char>::getline(char *, streamsize, char)' (0.75's
rule). Following the template's body: (1) `auto' UNDER A REFERENCE OR A POINTER
is deduced from the initializer (`cpp_auto_deduce`: `auto &__buffer =
*__is.rdbuf()' the referent's type, nothing decayed; `const auto *__first =
__buffer.gptr()' the pointee's, the qualifiers kept; `cpp_has_auto` finds the
`auto' under the layers) -- only a plain `auto' was, and everything read
through the reference local could not be typed; (2) A REFUSAL INSIDE A HELD
CANDIDATE'S BODY IS THE CALL'S (`instance_refused(Name, W)' out of
`cpp_instantiate_function__`; the template road of `cpp_call` and
`cpp_free_operator_call` never fall through on it): the getline that held and
whose body refused (1) fell to the plain overloads of the name, where C's
`getline(char **, size_t *, FILE *)' won by arity and the stream and the string
went to it as pointers -- LLVM refused the cast, and would not have for a
looser one; (3) `__builtin_char_memchr' is `memchr' (`cpp_builtin_call`), what
`char_traits<char>::find' is written on; (4) NO POINTER FOR AN ARITHMETIC
PARAMETER IN THE LAST RESORT EITHER (`cpp_args_no_clash` asks 0.73's
`cpp_scalar_mismatch`): `__str.append(__first, __last)' took the shipped
`append(const char *, size_type)' by arity, the pointer as the SIZE, and the
library asked for a string the size of an address (`std::bad_alloc' at run
time); C++ takes the member template `append(_InputIterator, _InputIterator)',
which the emptied candidate set now reaches; (5) A MEMBER TEMPLATE'S
DECLARATION LENDS ITS TEMPLATE-PARAMETER DEFAULTS to the out-of-class
definition at the merge (`cpp_keep_tdefaults` through 0.44's
`cpp_merge_defaults`, 0.73's rule for a free template's redeclaration):
libc++ declares `template <class _ForwardIterator, __enable_if_t<..., int> =
0> void __init(_ForwardIterator, _ForwardIterator);' and defines it without the
`= 0', and taken whole the definition refused cannot_deduce(anon) -- the
iterator-pair append constructs a string through it; (6) A MEMBER'S DEFAULT
ARGUMENT IS DESUGARED IN ITS CLASS (`cpp_default_ctx` from the declared `this'
parameter, `cpp_in_class` around it in `cpp_fill_defaults`), where C++ looks
its names up: `__reset_internal_buffer(__rep __new_rep = __short())' names the
string's nested `__short', and filled with no context it named nothing; AND A
CLOSURE IS ENCLOSED BY THE CLASS IT IS MADE IN (`cpp_lambda_scope`,
`'$cpp_enclosing'`), as a nested class is, so the enclosing class's types,
statics and enumerators are in scope in a lambda's body whether or not `this'
is captured (the record 0.59 kept only for the captured object). WHAT RUNS:
`test/cpp/run/stdgetline.cpp` -- a line, a comma-delimited field, the member
`getline' into a char array, `while (std::getline(cin, line)) n++' to the end
of input (the stream's `operator bool' through 0.72's contextual conversion,
the failed read clearing the string) -- clang++'s lines, 43 s and 1354 MB warm;
the C++ gate GREEN at 1173 MB, 104 checks, the only gate the change touches
(reader version 52 and lowering version 28 unchanged). NOT DONE: `cin.get()', `cin.ignore()', `std::ws', the manipulators, the
rvalue-stream `getline(basic_istream &&, ...)' overloads (declared, untried),
wide streams.

**M6's forty-fifth step (0.77): `cin.get()` and the unformatted input family --
no new rule.** `int_type get()', `peek()', `get(char_type *, streamsize,
char_type)', `ignore(streamsize, int_type)', `putback(char_type)' and
`unget()' are shipped members of the extern instance (0.75), `get(char_type &)',
`get(char_type *, streamsize)', `ignore()' with its two defaults (`1',
`traits_type::eof()', desugared in the class, 0.76) and `gcount()' the hidden
inline wrappers over them, `std::char_traits<char>::eof()' a static call on a
specialization, `cin.eof()' and `cin.fail()' basic_ios's through the base
hops -- every form went through the rules already there, the first fixture of
the stream work to ask nothing. Gated by `test/cpp/run/stdget.cpp` (a
character as an int, one into a char, a bounded read and its count, a
delimited one and a peek, ignore, unget, putback, a loop to the end of input
and the stream's state after it), clang++'s lines, 15 s and 871 MB warm; the
C++ gate GREEN at 2143 MB, 105 checks, the only gate the change touches. NOT DONE: `std::ws', `cin.read()', `readsome()', `tellg()' and
`seekg()' (`fpos', untried), the manipulators, wide streams.

**M6's forty-sixth step (0.78): THE STANDARD STREAMS' SURFACE, in one step --
`std::ws' asked for, and the module done whole (the owner's rule, 2026-09-13:
a module at once, not function by function).** `std::ws' ran as it stood (the
manipulator's road of 0.74, the whitespace loop of 0.76); the rest of what
`<istream>', `<ostream>', `<ios>' and `<iomanip>' offer a char stream came in
four more fixtures, and asked sixteen forms, each named: (1) THE HIDDEN
FRIEND, a function defined in a class body that only argument-dependent lookup
finds -- how `<iomanip>' writes every manipulator's inserter and how a program
prints its own class -- is split out of the members at registration
(`cpp_split_friends`) and registered as the free function it is
(`cpp_register_friends`: a template as a template, a plain one of a library
class as a lazy function of the header, a plain one of the program's class
declared at file scope and EMITTED WITH THE CLASS, `'$cpp_friends'`); (2) A
FREE OPERATOR IS AN OVERLOAD SET like a function's (0.56): noted by its word,
named by its parameters where two definitions share it, chosen by the
arguments through the free-function road (the `'$cpp_free_ops'` branch of
`cpp_operator` is gone) -- two classes' friend inserters are both
`operator<<(ostream &, ...)', and the first took the second's argument; (3) A
HEADER'S TEMPLATES AND FUNCTIONS OF A NAME JOIN THE PROGRAM'S (`cpp_hdr_join`
in `cpp_template` and `cpp_fn_ready`): loaded on the first ask whether or not
the program has one -- the friend registered `op.shl.2' first, the lookup
found it and never loaded libc++'s inserters, and every string went to the
`const void *' member; (4) FORWARDING REFERENCES: `T &&' with T a parameter,
given an LVALUE, deduces T as the argument's type AS A REFERENCE
(`cpp_deduce_one`, the `_Args &&...' packs alike, a call returning a reference
counted an lvalue, `cpp_lvalue`), with REFERENCE COLLAPSING in `cpp_type`
(`cpp_collapse_ref`) -- so `std::forward<T>' hands an lvalue back as one, and
the rvalue-stream inserter's `is_base_of<ios_base, _Stream>' is false for
`basic_ostream &'; deduced as the plain class it was viable for an lvalue
stream, and, the friend unknown, called itself until the stack ran out; (5) A
HEADER'S INLINE FUNCTION IS DECLARED WITH ITS TYPES RESOLVED
(`cpp_resolved_params`), and THE UNIT'S OWN ITEMS COME FIRST in the bulk noter
(`ccl_own_first` in `ccl_items_note`, the includes after), so an emitted
definition shadows a summary's raw declaration of the same name -- the passes
rebuild the tables from the summary, where `setiosflags(ios_base::fmtflags)'
is raw, and the lowering converted the call's argument to `ios_base::fmtflags';
(6) A CLASS VALUE WHERE A SCALAR IS WANTED converts through its CONVERSION
OPERATOR (`cpp_conv_to`: a declaration, an argument, a cast; scored exact
after it where the operator's result is the parameter's type, else 1,
`cpp_arg_fit_`) -- fpos's `operator streamoff()', `streamoff off =
cin.tellg()', `cout << cout.tellp()'; a CAST admits an explicit one and a cast
to bool takes the contextual road (`cpp_cast_to`: `(bool) cin'); (7) A
CHARACTER LITERAL IS A `char' IN C++ (the inference and the lowering, C's
`int' kept in C; lowering version 29): `cout << ' '' printed 32; (8) AN
INTEGER TYPE'S SPELLING IS ONE where sameness and exactness are judged
(`cpp_canon_specs`: `unsigned' is `unsigned int'): the member
`operator<<(unsigned int)' was no exact match for an `unsigned', every
arithmetic member tied at 2, `operator<<(bool)' won the tie and the free
`unsigned char' template took the call; (9) A FUNCTION FITS ONLY A FUNCTION
POINTER, in the fit (`cpp_pointee_fit`), the template acceptance
(`cpp_scalar_mismatch`) and exactness (a function decays, `cpp_arg_exact`):
the character-string inserter took `std::hex' and printed the manipulator's
code bytes, the char extractor took `std::noskipws' and wrote into code; (10)
A HEADER'S FUNCTION NAMED AS A VALUE, bare or `std::'-qualified, is emitted
as a call would emit it (`cpp_lazy_fn_value`): nineteen manipulators the link
named; (11) `T()' with T bound to a builtin or a pointer is the type's zero
(`cpp_subst`): `*__s = _CharT()' ends the char extractor's string; (12) a
class-scope typedef CALLED THROUGH ITS CLASS, `ios_base::fmtflags(0)', takes
the type-call road (a cast for a scalar, a temporary for a class); (13) THE
ARITY-ONLY LAST RESORT, free and member alike, refuses a class parameter for a
scalar argument and a pointer for an arithmetic one (`cpp_args_no_clash`,
`cpp_fn_best`); (14) a parameter is RESOLVED before exactness is judged
(`cpp_arg_exact` through `cpp_type_or_self`): a program's `operator<<(
std::ostream &, const P &)' is noted raw, and `std::ostream' is nothing to the
inference; (15) an operator function's RESULT type is resolved at declaration
and emission as a plain function's is; (16) the auto forms and the getline
forms of 0.76 carried the rest. WHAT RUNS, five fixtures against clang++'s
lines: `test/cpp/run/stdws.cpp` (`getline(cin >> ws, line)', `ws' before a
character, before a word, at the end); `stdistream.cpp` (the extractors for
short, unsigned short, int, unsigned, long, unsigned long, long long,
unsigned long long, float, double, bool, char and unsigned char, a `char *'
word, `getline', `read', `gcount', `readsome'); `stdistream2.cpp' (`sync',
`tellg' through fpos, `(bool) cin', `noskipws' and `skipws', `hex' and `dec'
on input, a `void *' extracted, a failed read, `clear', `ignore', `eof');
`stdostream.cpp' (a program's plain and template friend inserters, the
inserters for every arithmetic type, `bool', `char', `unsigned char', `signed
char', `const void *', `nullptr', a string and its `c_str()', `write', `put',
`flush', `cerr' and `clog' redirected through `rdbuf(streambuf *)', `tellp',
the state queries, `tie'); `stdmanip.cpp' (`hex', `oct', `dec', `showbase',
`uppercase', `boolalpha', `setw', `left', `right', `internal', `setfill',
`fixed', `scientific', `defaultfloat', `setprecision', `showpos', `showpoint',
`setbase', `setiosflags', `resetiosflags', and `width', `precision', `fill',
`setf', `unsetf', `flags' called). Not one form of the surface for a char
stream is outside them but `long double' (lowered as a double where the
library's is x87), the money and time facets, `quoted', `seekg'/`seekp' (a
pipe has no position), `sync_with_stdio', the exceptions mask, and an
overload SET of plain functions named as a value. Reader version 52 unchanged,
lowering version 29. Seven gates GREEN (the C++ one 2519 MB, 110 checks, 457 s;
the libc++ one 1747 MB); the two input fixtures peak near 2.4 GB each, which is
why the extractors and the stream's state are two fixtures and not one.

**M6's forty-seventh step (0.79): `std::map`, whole -- the int map's surface, a
map of strings walked by structured bindings, and `std::multimap`.** The owner's
rule of 0.78 (a module at once, not function by function) applied to `<map>`:
`test/cpp/run/stdmap.cpp` (`operator[]` reading and writing, `insert` of a braced
list and of a `make_pair`, `find` with `->first`, `count`, `erase`, `size`,
`empty`, `at`, `lower_bound`, `clear`, a range-for with `auto &`, an iterator
loop `begin()`/`end()`/`++`/`->`) and `stdmapstring.cpp` (string keys, `+=` and
`++` through `operator[]`, `for (const auto &[k, v] : w)`, `find` and `count`
with a `const char *`, `erase`, and `std::multimap` with `insert({k, v})`,
`count` and `equal_range` walked -- three fixtures, `stdmapstring.cpp` the
writing half, `stdmapstring2.cpp` the reading half, `stdmultimap.cpp`, for the
memory reason below) match clang++ line for line, and `<map>` is read WHOLE in
`test/libcxx.pl`. What the two asked, thirty-odd forms, each with
its reproduction (the piecewise `pair` probe first, then the map's own road):
THE READER (version 57): (1) a STRUCTURED BINDING whose right side the reader
cannot type -- unknown, dependent, or `auto` -- is DEFERRED to the desugaring
(`bindings(L, Ref, Ns, E)`, `ccl_bind_names`, `ccl_declare_autos`, `ccl_auto_type`),
where 0.44's read-time destructuring refused `cannot_infer(pattern)` on
`auto [__parent, __child] = __find_equal(__key)`; and a binding may be a
range-for's declaration (`ccl_range_decl(_, bindings(Ref, Ns))`); (2) a class
member `using Base::Base;` keeps its name (`using(L, name(Q))`); (3) `const'
KEPT on a member DEFINED OUT OF ITS CLASS, as `const(Sto)' in the storage slot
(`ccl_sto_quals`; the desugaring's `cpp_sto_quals` reads it): dropped, the
const overload's body attached itself to the non-const declaration; (4) a C++
`constexpr' OBJECT is a `const' one, the C23 rule, and the clause sits BEFORE
the qualifier clause that would take the word: `inline constexpr
piecewise_construct_t piecewise_construct' carried `constexpr' in its TYPE, and
`is_same<__remove_const_ref_t<decltype(piecewise_construct)>,
piecewise_construct_t>' was false, so libc++'s key extraction for a map's
piecewise emplace fell to its fallback.
THE DESUGARING, the pair's piecewise road first: (5) the bindings statement
(`cpp_stmt_(bindings)`: the value typed through `cpp_arg_type`, a temporary
`$bind` -- a reference when `auto &' binds an lvalue -- and one `auto' (or
`auto &') per name from its member by POSITION; A BINDING TO A REFERENCE
MEMBER IS A REFERENCE, [dcl.struct.bind], `cpp_binding_vt`: libc++'s
`__find_equal' answers `pair<__end_node_pointer, __node_base_pointer &>' and
the tree STORES THE NEW NODE THROUGH `__child' -- copied, the pointer went
nowhere and `__tree_balance_after_insert' walked a null root); (6) A RANGE-FOR
OVER AN OBJECT WITH `begin()' AND `end()' is C++'s (`auto __b = r.begin(), __e
= r.end(); for (; __b != __e; ++__b) { decl = *__b; body }', the iterator's `!=',
`++' and `*' the class's own -- a map's are hidden friends), placed BEFORE
0.38's `size()'/`[]' rewrite, which is this compiler's shortcut for a container
indexed by position: a map has both, and indexed it would have inserted the
keys 0, 1, 2; a prvalue range is bound to `auto &&' first, a structured binding
as the declaration becomes the statement above; (7) INHERITING CONSTRUCTORS
(`cpp_inherit_ctors`: one per base constructor but the copy and the move,
handing its parameters to the base -- libc++'s tree node destructor is
`struct __generic_container_node_destructor<...> : __tree_node_destructor<_Alloc>
{ using __tree_node_destructor<_Alloc>::__tree_node_destructor; }'); (8) TWO
OF CLANG'S BUILTIN TEMPLATES, `__make_integer_seq<S, T, N>' = `S<T, 0 .. N-1>'
(libc++'s index sequences) and `__type_pack_element<I, Ts...>' = the I-th of Ts
(tuple_element, which `get<I>' is typed by), in `cpp_instantiate_type`; (9) A
CONSTRUCTOR TEMPLATE'S SIGNATURE IS CHECKED IN ITS CLASS (`cpp_try_ctor`, as a
member template's is since 0.51; `unique_ptr''s `template <class _Deleter =
deleter_type, ...>' bound its default unresolved), and every step of a
candidate that FAILS says so under the trace (`ctor_candidate', `ctor_holds',
`ctor_no', `member_refused', `member_error', `sig_failed(F, explicit | deduce |
defaults | constraints | accept)'), where a candidate that neither held nor
refused cost an afternoon; (10) A TRAILING PACK IN A TEMPLATE-ID ARGUMENT
takes every argument left (`cpp_match_targs`: `tuple<_Args1...>' against
`tuple<int &&>'), DEDUCTION THROUGH AN ALIAS (`cpp_alias_pattern`,
`cpp_alias_binds`: `__index_sequence<_I1...>' is `__integer_sequence<size_t,
_I1...>'), a specialization's pattern deducing through an alias of a class
template-id too (`cpp_alias_through`: `__tuple_impl<__index_sequence<_Indx...>,
_Tp...>' -- held non-deduced, the tuple's base stayed the declared-only
primary, an incomplete type); A PACK BINDING HOLDS A LIST and an expansion
`pack(id(_I1))' handed through an alias's own pack is an ELEMENT
(`cpp_pack_list` asks `is_list'), and an expansion over packs of DIFFERENT
LENGTHS REFUSES (`pack_lengths_differ') where it failed without a word; (11)
A DELEGATING CONSTRUCTOR (`cpp_ctor_body`: the other constructor over `this'
and nothing else initialized -- pair's piecewise one delegates to its private
one with the index sequences); (12) THE TYPE AN ARGUMENT HAS, FOR DEDUCTION,
comes through the desugaring where the inference cannot tell it
(`cpp_deduce_type` over 0.68's `cpp_arg_type`, the temporaries that walk
registers dropped again): `__index_sequence_for<_Args1...>()' is a call of an
alias template's instance, and typed unknown its pack `_I1' stayed empty
beside a bound `_Args1'; (13) AN EXPLICIT TEMPLATE ARGUMENT'S KIND IS CHECKED
(`cpp_bind_explicit`, `kind_mismatch'): `get<0>(tup)' is no candidate of the
by-TYPE `get', whose `_T1' bound to 0 instantiated
`__find_exactly_one_t<0, ...>' without end (412 s to the cap); (14) AN UNNAMED
TEMPLATE PARAMETER IS NAMED BY ITS POSITION at the three registration doors
(`cpp_name_anon`, `$anon1' ...): libc++ forward-declares `template <size_t,
class> struct tuple_element;' with neither named, and two bindings of one name
`anon' answered the first to both, keying `tuple_element<0, tuple<int &&>>'
as `tuple_element.tuple.int_rr.tuple.int_rr'; (15) AN EXPANSION OVER A CLASS'S
PACK AND A MEMBER TEMPLATE'S OWN WAITS FOR THE MEMBER'S INSTANTIATION
([temp.variadic]: every pack in one pattern expands together): the member's
pack is marked `$later' when the class's bindings shadow it (`cpp_shadow`),
and the pattern travels with the class's packs bound, `pack_zip(Bound, X)'
(`cpp_subst_elems`), expanded once all are -- `__tuple_impl' constructs
`__tuple_leaf<_Indx, _Tp>(std::forward<_Args>(__args))...' with `_Args' the
constructor's own, and expanded over the class's packs alone the `...' was gone;
(16) A LAMBDA'S OWN PARAMETER PACK expands with the enclosing template's
bindings (`cpp_subst(lambda)`, `cpp_param_packs`): `[this](_Args &&...
__args2) { ... }' inside `__tree::__emplace_unique'; (17) AN EMPTY MEMBER
INITIALIZER VALUE-INITIALIZES ([dcl.init]/8: a scalar's zero, a class without
constructors zero-filled), which pair's piecewise constructor writes as an
empty pack expansion (`second()') -- left alone it was the member's garbage;
(18) `x->m' WITH x A CLASS OBJECT goes through its `operator->', again until a
pointer (`cpp_arrow_object`: a unique_ptr's node, `__h->__get_value()'); (19) A
CALL WHOSE RESULT IS A REFERENCE NAMES AN OBJECT (`cpp_addressable`) and
`decltype' OF A CALL IS THE FUNCTION'S DECLARED RESULT, its reference kept
(`cpp_decltype_of`: `std::declval<T>()' is `T &&', and the inference DECAYS
every reference, so declval gave the closure by value and its `operator()'
found no object -- the type `__try_key_extraction' returns); (20) A C++ CAST TO
A REFERENCE is typed as its object (`ccl_type_of(ccast)' unrefs, as every
other lvalue is) and a cast to an lvalue reference is an lvalue
(`cpp_lvalue(ccast)`): `std::addressof(const_cast<value_type &>(*__p))' had
deduced `_Tp' as a reference and refused; (21) A VALUE OF THE CLASS ITSELF
PLACED where the class writes no copy or move constructor of its own and holds
nothing that needs one is the implicit copy of the bytes
(`cpp_trivial_copy_init` in `cpp_new_at`): a map's node takes its
`pair<int, int>' so through `std::__construct_at'; (22) A BRACED ARGUMENT to a
class-typed parameter list-initializes a temporary of the class
(`cpp_copies_`; scored as a class it constructs, or an `initializer_list<T>'
whose items fit T, `cpp_arg_fit_`): `m.insert({4, 40})' builds the pair, an
`initializer_list' argument the compiler alone can build is refused by name;
(23) A FOR'S DECLARATION IS A DECLARATION IN THE FOR'S OWN SCOPE
([stmt.for]/1: `{ init; for (; c; step) s }'), so `auto it2 = m.begin()' is
deduced and a class local constructed there; (24) `sizeof' OF AN INCOMPLETE
TYPE REFUSES (`cpp_incomplete_class`), which in a template argument is the
substitution failure libc++'s `__has_default_three_way_comparator<L, R,
sizeof(__default_three_way_comparator<L, R>) >= 0>' detects by, and A VALUE
PATTERN NAMING A PARAMETER IS EVALUATED ONCE THE OTHERS BIND IT
([temp.deduct.type]/5; `cpp_non_deduced`, `cpp_match_later`'s value branch)
-- compared raw it folded to true for every pair of types, and the eager
comparator called an `operator()' of nothing; (25) A TEMPLATE-ID RESULT TYPE
IS SUBSTITUTED IN THE IMMEDIATE CONTEXT ([temp.deduct]/8, `cpp_sfinae_result`):
libc++'s conjunction is `__expand_to_true<__enable_if_t<_Pred::value>...>
__and_helper(int)' beside `false_type __and_helper(...)', and unresolved at
the check the first held for a false predicate -- every `_And' was true; and A
PARAMETER USED AS A PATH SEGMENT is seen by the expansion (`cpp_names_in`:
`__enable_if_t<_Pred::value>...' names the pack); (26) a block alias CALLED
OVER SEVERAL ARGUMENTS is the class's temporary (`cpp_subst`: `using _Pair =
pair<...>; return _Pair(__end, __end->__left_);'); (27) A FREE OPERATOR SET'S
NAME, `op.eq.2' exactly, IS ALWAYS AN OVERLOAD SET (`cpp_fn_overloaded`): the
first hidden friend `operator==' registered -- `__tree_iterator''s, alone at
that moment -- was declared under the bare name, and once the others arrived
the call's `op.eq.2.<keys>' named nothing and `__i == end()' stayed a
comparison of two structs; an INSTANCE of one, `op.lt.2.c21.char...', is one
function under its own name; (28) A CONST METHOD IS ANOTHER FUNCTION
([over.match.funcs]: the implicit object parameter differs): its name ends
`.c' (`cpp_mangle_q`, at every door the plain name had; a shipped member keeps
its Itanium symbol, which spells the const itself), the out-of-class merge
matches constness (`cpp_member_const`), and the OVERLOAD IS CHOSEN BY THE
OBJECT'S CONSTNESS where the parameters tie (`cpp_method_on`, `cpp_pick_q`,
`'$cpp_obj_const'`: a non-const object takes the non-const overload, a const
one the const overload; unsaid, the first declared) -- libc++ declares
`iterator find(const key_type &)' beside `const_iterator find(const key_type &)
const', and under one name the const one's result type was declared last and
won every `auto it = m.find(3)' while the body emitted was the other's: a
const_iterator cast from an iterator, which LLVM refused; (29) A VALUE OF
ANOTHER TYPE RETURNED converts through the result class's converting
constructor, as a call's argument does (`cpp_stmt_(return)`: `map::find'
returns `__tree_.find(__k)', a `__tree_iterator' where its iterator is a
`__map_iterator' holding one), a constructor TEMPLATE written over its own
parameters converts through the template road (`cpp_converting_ctor`'s third
clause: `pair(const pair<_U1, _U2> &)', no fit readable off the raw type) and
an EXPLICIT constructor never converts implicitly ([class.conv.ctor]:
`explicit basic_string(const _Tp &)' from a string_view); (30) A DERIVED OBJECT
WHERE ITS BASE IS TAKEN BY VALUE IS SLICED to the base sub-object
(`cpp_copies_`): `__priority_tag<1>()' to the `__priority_tag<0>' fallback of
`__try_key_extraction_impl'; (31) A MEMBER TEMPLATE CALLED BARE WITH EXPLICIT
ARGUMENTS passes `this' unless it is static (0.47's null was for the static
detection helpers): `__lower_upper_bound_unique_impl<true>(__v)' inside
`__tree' read the tree through a null this; (32) A CLASS VALUE WHERE ANOTHER
CLASS IS WANTED converts through its CONVERSION OPERATOR, at the fit
(`cpp_arg_fit_`), the clash (`cpp_args_no_clash`), a template's acceptance
(`cpp_type_accepts`), the argument (`cpp_ref_args_`, `cpp_conv_to` to a class
target too) and a temporary of the class from such a value (`cpp_temporary`,
[over.match.copy]): `compare(__self_view(__str))' is basic_string's
`operator basic_string_view()' -- taken for the `const char *' constructor,
the string was cast to a pointer; and `typename X::y(args)', the reader's
`construct/2' since 0.44, is desugared at last (the type resolved, then the
type-call road); (33) TWO CLASS TYPES ARE THE SAME BY CLASS (`cpp_same_type`:
a struct spec resolved by one road carries its members one way and by another
another) and the remove-qualifier builtins keep a NAMED type; (34) the
template acceptance looks through EVERY reference layer (`cpp_unref_all`: a
forwarding `_Tp &&' bound to an lvalue is `T & &&' before it collapses); (35)
THE COPY PASS RUNS ON AN OPERATOR'S CALL TOO (`cpp_operator`): `w["apple"]'
hands `const char *' to `operator[](const key_type &)', which takes it only
through the string's converting constructor -- passed raw, the key was a
pointer read as a string; (36) IN THE METHOD ROAD THE ARITY ALONE IS THE LAST
RESORT, after every member template (0.63's rule, which `cpp_ctor' had and
`cpp_method' did not): basic_string's `compare(const _Tp &)' template takes a
string_view, and the arity-only `compare(const basic_string &)' took it first
and called itself. THE CHECK: A LIBRARY CLASS'S VALUE IS OPAQUE
(`ck_carries_`, `ck_library_class`): its pointers are libc++'s own discipline,
as its functions' bodies are since 0.45 -- a map's iterator, `auto it =
m.find(3)', holds a node pointer the safe part cannot follow and need not,
where it refused `no owner behind'; and THE ADDRESS OF A PATH UNDER A
REFERENCE THE CHECK DOES NOT FOLLOW IS NO FRESH VALUE (`ck_ref_rooted` in
`ck_fresh_value`): a reference bound to a call has no state, and `const auto
&[k, v] = *it' binds v to a member of it -- a plain value, never a loose
pointer refused at the scope's end. THE LOWERING: a global initialized by an
EMPTY CLASS TEMPORARY (`ir_gconst(compound_lit(...))`: `inline constexpr
piecewise_construct_t piecewise_construct = piecewise_construct_t();'), `int{}'
a scalar's zero, and under the C++ trace the whole item the lowering refuses
is printed (`ir_item_error`), which is how three of the above were found.
Lowering version 30. Seven gates GREEN, twice: under cocolog 1.2.12 (the
C++ one 2407 MB, 114 checks, 602 s; the libc++ one 1953 MB, `<map>` 430
items) and, the module rebuilt, under 1.2.13 with its store compaction (the
C++ one 1398 MB, 673 s; the libc++ one 1374 MB; the reader's 85 MB and 6 s
where it was 329 MB and 39 s), every fixture's output the same; the int map builds in 18 s at about 1.1 GB, each string-map half in
35 s at 1.0-1.4 GB. AND A FINDING THAT COST THE EVENING, and was read wrong here first: the
string map's two halves were ONE fixture, which the gate's watchdog killed at
2876 MB twice while the same file built alone at 1.7 GB by the same counter;
four runs under `/usr/bin/time -l' gave 3252, 1821, 1728 and 3506 MB for
identical work. I read a heap growing by doubling. cocolog's owner's session
measured it: macOS's counters READ LOW after a realloc remap (the high number
is the honest one), and the honest cost was 2.9 GB, half of it the STORE's
dead rows -- a hundred thousand `nb_setval' overwrites whose old values
nothing reclaimed -- which cocolog 1.2.13 compacts away (the finding below).
The cap stays (the owner's rule); the fixture stays split near a gigabyte a
half; the module is rebuilt against 1.2.13. NOT DONE: `emplace',
`insert_or_assign', `try_emplace', `extract' and node handles, `merge',
`std::set' and the unordered containers, a map of the program's own class, an
`initializer_list' argument (refused by name), a class whose members need a
MEMBERWISE copy placed by the implicit one (refused as `no_constructor'), an
array member value-initialized, the `less<void>' transparent comparator's
`operator()' emitted where a program never calls it, and the fallback
key-extraction road (`__without_key', reached by `emplace' with non-key
arguments), which crashed at a null before the piecewise candidate held and
is untested since.

**M6's forty-eighth step (0.80): `std::set`, whole -- and the compile's memory
taken apart again, honestly this time.** THE MODULE: `test/cpp/run/stdset.cpp`
(an int set: `insert`, `size`, `empty`, `count`, `find`, `erase` by key and by
iterator, `lower_bound`, `upper_bound`, `clear`, a loop over `begin()`/`end()`,
a set from an initializer list and from a vector's range, `std::multiset` with
`equal_range`), `stdsetstring.cpp` (string keys), `stdset2.cpp` (a set COPIED,
`==` and `!=`, `emplace`, a hint insert, an erase over a range, `swap`,
`std::greater<int>` as the comparator, `key_comp()` called, `rbegin()`/`rend()`,
a multiset's `emplace` and `rbegin`) and `stdset3.cpp` (`insert(first, last)`,
`insert({...})`, `emplace_hint`, `cbegin`, `crbegin`/`crend`, `<` on two sets,
`value_comp`, `max_size`, `merge`, a TRANSPARENT comparator `std::less<>` on a
set of strings looked up with `const char *` keys, `equal_range`,
`erase(begin())`) match clang++ line for line, and `<set>` is read WHOLE in the
libc++ gate. THE FORMS, each named: (1) AN INITIALIZER LIST IS BUILT BY THE
COMPILER (`cpp_init_list`): a backing array `$il_k[N]` of the element type and
libc++'s private two-argument constructor over its address and its length,
where `initializer_list_argument` had been refused by name; a class with a
constructor taking one (`cpp_il_ctor`) takes a braced initializer and a braced
argument through it (`cpp_ctor_args`), an item of another type converts
through the element class's converting constructor (`cpp_il_item`: `{"bob",
"amy"}' for strings, the temporaries dying with the statement as the array does
in C++), and the items are collected ONCE -- a `findall' over a goal with a
second answer registered a second temporary and the array held both, one of
them declared nowhere; (2) `C(const C &) = default' and `C(C &&) = default'
ARE MEMBERWISE (`memberwise(S, Kind)' in the constructor's initializer slot at
`cpp_norm_members`, `cpp_ctor_body`: every data member from the source's,
moved under a move, a union as one assignment), where the dropped declaration
left `set(const set &) = default' to the rule that refuses a copy of a class
with a destructor; `cpp_user_ctor` tells such a marker from a written one
(`cpp_trivial_class`, `cpp_note_nontrivial`); (3) A PARAMETER'S CLASS WITH A
CONSTRUCTOR TAKING THE ARGUMENT'S CLASS accepts it (`cpp_class_converts` in
`cpp_type_accepts`; [over.ics.user]): libc++'s tree copies itself through
`unique_ptr<__node, __tree_deleter>(node, __node_alloc_)', the deleter made of
the allocator; (4) `__builtin_invoke(f, args...)' is the call (`cpp_builtin_call`),
which `__invoke_result_impl' asks; (5) A CALL RETURNING A CLASS BY VALUE,
CALLED -- `g.key_comp()(3, 1)' -- materializes the prvalue in a temporary of
the statement and calls its `operator()' over it (`cpp_temp_call`'s third
clause), where the lowering met a call whose callee was a call; (6) A CLOSURE
HAS NO IMPLICIT CONSTRUCTOR (`cpp_closure_class`, in `cpp_implicit_ctor_needed`):
it is built from its captures, and libc++'s `[this, __p]' captures an iterator
BY VALUE, a class with constructors, whose implicit one was walked under the
closure's `this' -- the enclosing object's -- and named a member the tree has
not; (7) AN ASSIGNMENT FROM ANOTHER CLASS CONVERTS through the target's
converting constructor (`cpp_expr(assign)`, as an argument and a return do):
`__f = erase(__f)' stores an `iterator' into a `const_iterator', and taken raw
the lowering cast one struct to the other; (8) A FREE OPERATOR SERVES A CLASS
ON EITHER SIDE (`cpp_free_operator_call`): `"amy" < s' is
`operator<(const _CharT *, const basic_string &)', which the transparent
comparator writes as `std::forward<_T1>(__t) < std::forward<_T2>(__u)', and
with the class on the right only the form stayed raw -- a pointer compared with
a struct; (9) THE COPY AND THE MOVE CONSTRUCTOR CONVERT NOTHING
(`cpp_own_class_param` in `cpp_converting_ctor`): `__self_view(__str)' fitted
string_view's defaulted copy constructor (now synthesized, (2)) THROUGH the
string's conversion operator, and the copy took the string's bytes for a
string_view's -- `memcmp' at a wild address; the conversion operator is the
road; (10) `decltype(*p)' AND `decltype(a[i])' ARE `T &' ([dcl.type.decltype],
`cpp_decltype_of`): `using __reference = decltype(*__first)' is
`const string &', and read as the plain type the range insert's
`forward<__reference>' handed an rvalue on and the MOVE constructor took each
element out of the caller's range. THE MEMORY, measured with cocolog 1.2.13's
`statistics/2' -- `globalused', `store_used', the honest instrument where the
process's RSS read low (0.79's finding) -- printed on every trace line
(`cpp_trace_mem`, `ir_mem`, `kb(Heap, Store)') and at each phase
(`phase(check)', `phase(lowering)', `phase(assemble)' in `ccl_ir_units`, and
`lower(Item, Mem)' per item): stdset2's desugaring left 1.85 GB of heap behind
it, and the check and the lowering added ten megabytes -- a deterministic run
keeps every intermediate (the no-GC finding), and 0.68 had scoped only a class
instantiation. EVERY EMISSION ROAD RUNS INSIDE `\+ \+' NOW: a lazy member
(`cpp_make_lazy`), a header's free function (`cpp_use_fn`), a function
template's instance (`cpp_instantiate_function_`), a member template's
(`cpp_make_member`), a nested class (`cpp_nested_class`) and a header's load
(`cpp_hdr_load`) -- their results are facts and globals, which survive the
scope, and their walks are reclaimed; so does each lowered item (`ir_items`)
and each checked function (`ck_items`), and a function's text is a global of
its own (`'$ir_fdef:K'`, `ir_add_fdef`), where a list of every text so far was
copied at each addition. 1.85 GB -> 186 MB at the check, and the build's RSS
2.8 GB (killed at the cap twice) -> 650 MB. `stmt_out(S)' traces the program's
own statements as they come out. NOT DONE: node handles (`extract',
`insert(node_type &&)') hold a `std::optional<allocator>', and `<optional>' is
a module of its own (`base_constructor(__optional_iterator_base)' is where it
stops); C++20's `contains' and `erase_if' (the level's fixtures); a lambda as
the comparator; a program's constructor taking `std::initializer_list<std::string>'
is keyed by the raw template-id (`typedefscopedstdtmplinitializerlist...'), which
works and is ugly. Seven gates GREEN (the reader's 94 checks, 6 s and 78 MB;
the compile gate's 73 at 213 MB; the driver's 23; the objects' 29; the proof;
the C++ one 118 checks, 798 s, 1220 MB; the libc++ one 279 s and 1269 MB,
`<set>` read whole, 426 items); the four set fixtures build in 40 to 90 s at
630 to 920 MB each.

**M6's forty-ninth step (0.81): THE UNORDERED CONTAINERS, whole.** THE MODULE:
`test/cpp/run/stdunorderedmap.cpp` (an int map: `operator[]` writing and
reading, `insert({k, v})`, `find`, `count`, `erase`, `size`, `empty`, a
range-for, `at`, `+=` through `operator[]`, `bucket_count`, `clear`),
`stdunorderedmapstring.cpp` (string keys: `operator[]`, `+=` and `++`, `find`
and `count` with a `const char *`, `erase`, `at` with a string, a range-for),
`stdunorderedset.cpp` (`unordered_set<int>` from an initializer list, `insert`,
`count`, `erase`, a range-for, `find`; `unordered_set<std::string>`: `insert`,
`count`, `erase`, `empty`, `clear`), `stdunorderedmap2.cpp` (a map from an
initializer list, COPIED, `==`, `emplace`, `insert` returning its pair,
`erase(iterator)` returning the next, `insert(first, last)` from a vector of
pairs, `reserve`, `bucket_count`, `load_factor`, `rehash`, `unordered_multimap`
with `equal_range`, `clear`) and `stdunorderedset2.cpp` (`unordered_multiset`:
an initializer list, `insert`, `emplace`, `count`, `equal_range`, `erase`; a set
of strings copied and compared, `erase(find(...))`, `reserve`) match clang++
line for line, and `<unordered_map>` and `<unordered_set>` are read WHOLE in
the libc++ gate. THE FORMS, each named: (1) THE LOCALS DECLARED ON THE WAY TO
THE FIRST RETURN are in scope when a lambda's or an `auto' method's result is
deduced (`cpp_declare_before`, in `cpp_lambda_ret` and `cpp_method_ret`): the
hash table's emplace lambda writes `pair<iterator, bool> __r = ...; if (...)
...; return __r;', and with the parameters alone declared `__r' had no type
(`lambda_result_type'); every declaration before the return -- in its block,
the blocks around it, a for's own -- is desugared for its declarations only,
and the refusal behind such a failure is traced (`lambda_ret_refused'); (2)
THE MATH BUILTINS ARE LIBM'S FUNCTIONS (`cpp_builtin_call` through
`cpp_math_fn`, a table of stems and their arities): libc++'s `<cmath>` wrappers
are `inline float ceil(float __x) { return __builtin_ceilf(__x); }', which
the rehash calls, the prototype is emitted once where no header declared it
(`cpp_math_declared`, as a mangled declaration is), and the long double form
goes to the double one (a long double is lowered as a double here); (3) A
MEMBER TEMPLATE IS A TEMPLATE THROUGHOUT ITS CLASS'S BODY ([class.mem]: a
member function's body is a complete-class context) -- THE READER (version
58, `ccl_member_templates_ahead`) scans the class body's tokens for `template
< ... >' declarators before the members are read, attributes and `[[...]]'
skipped, and notes each name: libc++ calls `__rehash<true>(__n)' a hundred
lines before it declares `template <bool> void __rehash(size_type)', and read
in order the call was the comparison `(__rehash < true) > (__n)'; (4) `void()'
IS THE VOID VALUE (the reader's functional cast of nothing, `cpp_expr`):
`for (__pp = __cp, void(), __cp = ...)' keeps an overloaded comma out, and
desugared to nothing the lowering met a missing operand; (5) A CONDITIONAL
WITH A `nullptr' ARM TAKES THE OTHER ARM'S TYPE ([expr.cond],
`ccl_type_of(cond)`), unknown included: typed `void *' by its nullptr while
the other arm was still unknown, `__nbc > 0 ? allocate(...) : nullptr' chose
the array unique_ptr's `reset(nullptr_t)' and the buckets were never kept; (6)
THE ARGUMENTS ARE TYPED IN THE CALLER'S WORDS (`cpp_as_callee` at every
overload door, `cpp_caller_ctx` in `cpp_arg_type`): a candidate's parameters
are read in the callee's class (0.65's rule) and an argument that must be
DESUGARED to be typed is read in the caller's -- `__pointer_alloc_traits::
allocate(__npa, __nbc)' names the hash table's own alias, which resolved to
nothing in unique_ptr's words; (7) `nullptr_t' TAKES A NULL POINTER CONSTANT
AND NOTHING ELSE ([conv.ptr]; `cpp_nullptr_param` in `cpp_arg_fit` and
`cpp_args_no_clash`): resolved to `void *' it took every pointer; (8) A MEMBER
CLASS TEMPLATE, WITH ITS PARTIAL SPECIALIZATIONS (`cpp_nested_template_put`,
`'$cpp_nested_tmpl'`, `cpp_nested_template`; refused as
`template_without_body' since the fourth step): `template <class _From> struct
_CheckArrayPointerConversion : is_same<_From, pointer> {};' and its
`<_FromElem *>' specialization guard the array unique_ptr's `reset(_Pp)'; it is
a class template under the enclosing class's name (`C.N', as a nested class
is named), its specializations with it, the bare name resolves in the class,
its nested classes and its bases AT THE INSTANTIATION DOOR ITSELF
(`cpp_instantiate_type`, since the scope walk of `_CheckArrayPointerConversion<
_Pp>::value' asks there and not through `cpp_type`), and an instance is
ENCLOSED by the class, so `pointer' and `element_type' are in scope in its
members; (9) A MEMBER OF A CONST OBJECT IS CONST ([dcl.type.cv],
`cpp_obj_const`): `__table_.begin()' inside `unordered_map::begin() const' is
the const begin, where the member's own type -- no const of its own -- chose
the non-const one and a `__hash_iterator' was stored as a const one; a
REFERENCE member keeps its referent's own constness (`cpp_member_own_const`);
(10) THE OBJECT'S CONSTNESS ORDERS THE MEMBER TEMPLATES too (`cpp_prefer_const`,
0.79's rule for the plain overloads): libc++ writes `template <class _Key>
iterator find(const _Key &)' beside its const twin, and `find' inside
`unordered_map::find(...) const' took the non-const one first. The unordered
map's `__try_key_extraction', its `__hash_value_type', the bucket list as an
array `unique_ptr' with its deallocator, `__constrain_hash', the rehash
loop and `std::hash<std::string>' (libc++'s murmur, compiled from the header)
all went through the rules already there. Seven gates GREEN (the reader's 94
checks, 37 s and 277 MB cold after the version bump; the compile gate's 73;
the driver's 23; the objects' 29; the proof; the C++ one 123 checks, 1111 s,
1258 MB; the libc++ one 357 s and 1344 MB, `<unordered_map>` 322 items and
`<unordered_set>` 318 read whole); the five fixtures build in 50 to 95 s at
620 to 1200 MB each, the string-keyed ones the heaviest. NOT DONE: `std::hash' of
a program's own type (a specialization the program writes), `extract' and
node handles (`<optional>', as `<set>''s), the bucket interface (`begin(n)',
`bucket_size', `bucket'), `max_load_factor' set, C++20's `contains'.

**M6's fiftieth step (0.82): `std::optional`, whole.** THE MODULE:
`test/cpp/run/stdoptional.cpp` (an `optional<int>`: empty and engaged,
`has_value`, `*`, `value`, `value_or`, assigned a value, `reset`, returned
from a function as a value and as `std::nullopt`, `emplace`, compared with a
value, COPIED, `==` and `<` on two optionals, tested in an `if`),
`stdoptionalstring.cpp` (an `optional<std::string>`: a long string engaged,
`->`, `value_or` with a `const char *`, assigned a literal, `reset`
destroying the string, returned, `emplace("...")`, copied and compared,
`std::make_optional`, `swap`) and `stdoptional2.cpp` (an optional of the
program's own struct returned by `return P{n, n * 2}`, of a `double`, of a
`pair` from `make_pair`, assigned `nullopt`, compared with `nullopt`,
assigned an optional temporary, MOVED from, `>` with a value) match clang++
line for line, and `<optional>` is read WHOLE in the libc++ gate. THE FORMS,
each named: (1) A MEMBER ALIAS TEMPLATE NAMED BARE IN ITS CLASS resolves
(`cpp_nested_alias` at the instantiation door, as a member class template
does since 0.81): optional's `_CheckOptionalArgsCtor<_Up>::template
__enable_implicit<_Up>()' guards every converting constructor, and 0.47 had
resolved such an alias only through `C::template _Select<A, B>'; (2) THE
IMPLICIT COPY AND MOVE CONSTRUCTORS ARE MADE ON DEMAND, memberwise
([class.copy.ctor]; `cpp_implicit_copy_ctor` in the constructor road,
`'$cpp_implicit_copy'`, the marker of 0.80's `= default' synthesis, so they
count as no user-written special member): optional's `__optional_iterator_base'
inherits its base's constructors, which brings no copy constructor, and the
memberwise copy of `optional' asked its base for one; (3) A CONSTRUCTOR
INITIALIZER NAMING THE BASE THROUGH AN ALIAS (`cpp_alias_base_init`): `using
__base = __optional_iterator_base<_Tp>; ... : __base(in_place, ...)' -- dropped,
the base was default-constructed and the optional never engaged; (4)
INHERITING CONSTRUCTORS TAKE THE BASE'S CONSTRUCTOR TEMPLATES TOO
(`cpp_inherit_ctors`, `cpp_named_params_t`; [namespace.udecl]), a pack
forwarded as an expansion: the storage chain inherits `template <class...
_Args> __optional_destruct_base(in_place_t, _Args &&...)' level by level, and
`using __base::__base;' through the class's own alias (`cpp_alias_names_base`);
(5) AN ANONYMOUS UNION'S MEMBER INITIALIZED BY NAME (`cpp_member_inits`,
`cpp_union_member_init`): `union { char __null_state_; value_type __val_; };
... : __val_(std::forward<_Args>(__args)...), __engaged_(true)' named no
member of the class itself, the initializer was dropped and the value read
back was garbage; (6) A HEADER'S INLINE GLOBAL OF AN EMPTY CLASS IS ITS ZERO
BYTES, its constructor not run (`cpp_lazy_inline_var`): `inline constexpr
nullopt_t nullopt{nullopt_t::__secret_tag{}, nullopt_t::__secret_tag{}}' is a
tag with nothing to construct, and this compiler runs no dynamic
initialization; (7) A CAST TO A CLASS IS ITS CONVERTING CONSTRUCTOR
([expr.static.cast]/4; `cpp_cast_to`): `value_or' returns
`static_cast<value_type>(std::forward<_Up>(__v))', a string from a `const char
*', which the lowering met as a pointer cast to a struct; (8) A RETURN OF A
CONDITIONAL OVER CLASS ARMS RETURNS EACH ARM ON ITS OWN ([class.copy.elision]:
the chosen arm's prvalue IS the result object; `cpp_stmt_(return)`): `return
has_value() ? __get() : static_cast<value_type>(...)' as one value copied the
lvalue arm BITWISE and destroyed the temporary arm under the caller; (9) A
FORWARDING REFERENCE'S ARGUMENT IS JUDGED ON ITS DESUGARED FORM
(`cpp_lvalue_deep` in `cpp_deduce_one` and the pack road of `cpp_deduce_args`):
`std::forward<_That>(__opt).__get()' is a member call whose instance returns
`const value_type &', read raw it was no lvalue, `_Args' deduced the plain
string and the copy of an optional MOVED the source's string out (its size read
0 after the copy); (10) REF-QUALIFIED MEMBER FUNCTIONS ([dcl.fct]/6,
[over.match.funcs]/5): the reader keeps `&' and `&&' after the parameters
(`refq(lvalue | rvalue)' in the qualifiers, `ccl_method_quals`, reader version
59), the name carries them (`.r', `.rr' after the `.c', `cpp_mangle_q`), and
the overload is chosen by the OBJECT'S VALUE CATEGORY (`cpp_obj_cat`,
`cpp_ref_bonus` in `cpp_best_q`, `'$cpp_obj_cat'` beside the constness; a
member template alike in `cpp_prefer_const`): optional's storage writes
`__get() &', `const &', `&&' and `const &&', and on one name the last
declared won -- `const &&', whose result no lvalue test took for one. Reader
version 59; the module rebuilt as 0.82. Seven gates GREEN (the reader's 94
checks, 39 s and 224 MB cold; the compile gate's 73; the driver's 23; the
objects' 29; the proof; the C++ one 126 checks, 1127 s, 1013 MB; the libc++
one 366 s and 1356 MB, `<optional>` read whole, 222 items); the three optional
fixtures build in 12 to 24 s at 240 to 460 MB. NOT DONE: node handles
(`set::extract', `map::extract', `insert(node_type &&)'): with `<optional>`
through, the probe builds `<set>`, `<map>` and `<string>` together in 189 s
at 1.26 GB and stops at `no_constructor(pair<string, int>, 1)' inside
`std::__construct_at' -- the map's node handle placing its value with `_Args'
deduced as `const pair *', a POINTER where the value was meant (the trace:
`call_types(__construct_at, [__p - pair *, forward<pair *>(__args$1) - const
pair *])') -- which is the next thing; `optional<T &>' (C++26), `and_then',
`transform', `or_else' (C++23), `std::hash<optional>', `bad_optional_access'
caught (exceptions are off: it aborts with its message).

**M6's fifty-first step (0.83): NODE HANDLES, and the value category of
`std::move`.** `<set>`'s and `<map>`'s not-done item since 0.80, taken up once
`<optional>` compiled: `test/cpp/run/stdnodehandle.cpp` (`set::extract` by key,
the handle's `empty`, `value` and `operator bool`, `insert(node_type &&)` into
another set, an extract that finds nothing, `map::extract`, `key()` rewritten
and `mapped()`, the handle inserted back) and `stdmapinit.cpp` (a map of strings
from an initializer list of braced pairs, walked and looked up) match clang++
line for line. THE FORMS, each named: (1) `std::move` OF A CLASS VALUE KEEPS ITS
MOVE ([expr.xvalue]; `cpp_expr(move)`): 0.40 had made `move(x)' of a value
without owners the value itself, and the value category was gone before
overload resolution -- `t.insert(std::move(nh))' found no `insert(node_type &&)'
and took `insert(const value_type &)' through the handle's `operator bool'; the
class an expression has looks through the move (`cpp_class_of_type_of`), a
by-value parameter of a class with a destructor given `std::move(x)' takes the
MOVE constructor into the callee's copy (`cpp_move_temp` in `cpp_copies_`; the
copy one over the object where the class has no move), `return std::move(x)'
of a local likewise, and a reference bound to a move binds the object
(`ir_ref_of`); (2) A NON-CLASS ARGUMENT CONVERTS TO A CLASS PARAMETER ONLY
THROUGH A CONSTRUCTOR WHOSE PARAMETER TAKES ITS KIND (`cpp_converting/2` in
`cpp_type_accepts`): any one-argument constructor let `const pair *' pass for a
map's `const_iterator', so `insert(__il.begin(), __il.end())' in the map's
initializer-list constructor took `insert(const_iterator, _Pp &&)' over the
range template, and a node was built from a pointer to a pair; (3) A BRACED
ITEM OF AN INITIALIZER LIST list-initializes the element class through its
constructors (`cpp_il_item`): `{{"a", 1}, {"b", 2}}' for a map builds each
`pair<const string, int>', which as an aggregate of the backing array stored
the literal's pointer into the string; (4) THE COPY PASS RUNS ON A TEMPORARY'S
CONSTRUCTOR CALL TOO (`cpp_temporary`): `pair(const T1 &, const T2 &)' took
the literal raw for the `const string &', and the map's keys were the
pointer's bytes; the temporaries register is read AGAIN after the pass, since
the pass registers temporaries of its own (a string for that parameter) and the
list read at the head dropped them (`undeclared('$tmp_8')'); on a MEMBER's
constructor call the same pass LOOPED through the string's allocator member
(`__alloc_(std::move(__str.__alloc_))' converting into itself without end, 4.3
GB in 486 s to the cap) and is not run there; (5) AN AGGREGATE WHOSE MEMBER
CONSTRUCTS IS BUILT MEMBER BY MEMBER, as a temporary and as a braced return
(`cpp_temporary`, `cpp_stmt_(return)`, through 0.41's `cpp_aggregate_inits`):
the tree's `_InsertReturnType{end(), false, _NodeHandle()}' put a
`__tree_iterator' into a `__tree_const_iterator' member bitwise, where its
converting constructor was meant; (6) THE MEMBERWISE COPY OF AN ANONYMOUS UNION
IS ITS BYTES (`cpp_member_inits`): the implicit copy constructor of optional's
storage assigned the union, and the lowering converted its bytes as a pointer;
(7) A VALUE OF THE CLASS ITSELF TAKES ITS COPY OR MOVE CONSTRUCTOR, written or
implicit, and never another constructor taking a class ([over.best.ics];
`cpp_ctor`'s first clause): the C++ gate's first run of this step was RED on
all ten stream fixtures (exit 139), and the backtrace led into `std::copy''s
unwrap road, where (5) built `__in_out_result{__first, __rewrap_iter(...)}'
member by member and the fit set gave the `ostreambuf_iterator' member
`ostreambuf_iterator(ostream_type &)' for an ostreambuf_iterator argument --
the stream buffer's pointer was the iterator's bytes; and the second run RED
on the three `getline' fixtures by a slip of (2): the one-argument
`cpp_converting/1' the traits' `is_convertible' still asks was gone with the
two-argument one, an existence error the driver reported as the file's
(restored beside it); and the third RED on the node-handle fixture itself, by
(8) AN ARGUMENT TYPED BY A FUNCTION TEMPLATE'S RAW SIGNATURE IS NOT TYPED
(`cpp_raw_type` in `cpp_arg_type`): the inference types a call of a function
template from the raw signature a summary declares it under (0.49), so
`std::exchange(__other.__alloc_, nullopt)' in the node handle's move constructor
was a `_T1', optional's `optional(_Up &&)' deduced `_Up' as that free name, and
an allocator was built from a `_T1' -- a type naming a parameter the tables do
not know now falls to the desugaring, which instantiates the call and types it.
A trace names the member template instance an overload set settles on
(`member_holds(C, Name)'), which is how (2) was found. The module rebuilt as
0.83. Seven gates GREEN (the reader's 94 checks, 5 s and 84 MB; the compile
gate's 73 at 209 MB; the driver's 23; the objects' 29; the proof; the C++ one
128 checks, 1237 s, 1090 MB on its fourth run, GREEN at last; the libc++ one
415 s and 1348 MB, unchanged by a desugaring step); the node-handle fixture
builds in 100 s at 1.0-1.2 GB, the map one in 50 s at 0.5. NOT DONE: `unordered_map::extract' and the unordered node
handle (its `__hash_node_handle'), `merge' between a set and a multiset, a node
handle's `get_allocator'.

**M6's fifty-second step (0.84): THE NOT-DONE LISTS OF THE CONTAINER MODULES,
closed -- and the levels' headers read whole.** The owner asked for every
not-done item of 0.79 to 0.83 at once. THE MODULES' REMAINDERS, five C++17
fixtures matching clang++ line for line: `test/cpp/run/stdmapemplace.cpp`
(`emplace`, `insert_or_assign`, `try_emplace`, `merge`, `emplace_hint`, a node
handle's `get_allocator`), `stdmapown.cpp` (a map of the program's own struct
as the key and as the value; `emplace` on a string map without the key, the
`__without_key` road; a braced subscript `pm[{1, 2}]`; a copy of the value),
`stdsetlambda.cpp` (a lambda as the comparator; `merge` between a set and a
multiset, both ways), `stdunorderedhash.cpp` (`std::hash` specialized by the
program for its own key; the bucket interface -- `bucket_count`, `bucket_size`,
`bucket`, `begin(n)`/`end(n)`, `load_factor`; `max_load_factor` set, `rehash`,
`reserve`; `unordered_map::extract` and the hash node handle; an
`unordered_set<string>` extract) and `stdaggregate.cpp` (a plain struct holding
a string pushed into a vector by the implicit copy, an array member
value-initialized, an aggregate with fewer items than members, a nested braced
list, an array of strings as a member, a constructor taking
`initializer_list<string>`). Three of those (the lambda comparator, the merges,
the whole hash surface) asked nothing: they ran as they stood. THE FORMS, each
named: (1) A PLAIN STRUCT WHOSE MEMBER IS A CLASS IS A CLASS
(`cpp_struct_promotes`, `'$cpp_promoted'`, at registration and in the program's
own header): the reader keeps a C++ `struct` of data members as C's
(`ccl_make_class`), and `struct Rec { std::string name; int n; }` had a member
the tables never resolved and no constructor, destructor or copy for the string
it holds; promoted, it goes a class's whole road, and a struct of plain members
has its member types resolved in place (`cpp_plain_members`); (2) AN AGGREGATE
IS A CLASS WITH NO CONSTRUCTOR WRITTEN (`cpp_aggregate_class`,
[dcl.init.aggr]): the implicit constructor made for a member that constructs
does not count, where `Val{"beta", 2}` had asked for `Val(const char *, int)`;
the rest of an aggregate's members are VALUE-INITIALIZED where fewer items are
given (`cpp_aggregate_inits`, `cpp_value_init`: `Grid2 g2{}` names nothing and
gets its array zeroed and its string default-constructed), a nested braced
list fills an array member element by element or a nested aggregate through
its own list (`cpp_member_from`), and a class member from a braced list goes
through its constructors; (3) AN ARRAY MEMBER OF OBJECTS (0.41's not-done):
constructed element by element by the implicit constructor, copied element by
element by the implicit copy and move (a plain array as its bytes), destroyed
in reverse (`cpp_member_dtor`), `: cells()` zeroing it where it had been `cells
= 0`, an int into an array; `cpp_elem_class` looks through the array for the
class the members' rules ask -- and THE RESOLVER LEAVES AN ARRAY AS IT IS, so
its element is resolved before its size is taken (`ccl_size_align`), where
`std::string s[2]` had no size, the whole layout failed silently and the empty
layout was cached (`no_member(s, ...)` in the lowering, found by asking the
layout directly after the build); (4) THE IMPLICIT MEMBERWISE ASSIGNMENT
([class.copy.assign], `cpp_implicit_assign`, `'$cpp_implicit_assign'`): a class
with a destructor and no `operator=` written assigns each member through its
own -- a string member takes basic_string's, an array its bytes, a base its
sub-object -- the move form moving each, made once per class and kind as a
method written out would be; never for a class holding owners of its own,
whose plain copy the safe part refuses as ever (`vm[1] = Val{"alpha", 1}`);
(5) THE IMPLICIT COPY AND MOVE MADE ON DEMAND FOR A LOCAL (`cpp_ctor_args`:
`Grid2 g4 = g3`), where only the constructor road had them (0.82); (6) A
MEMBER TEMPLATE'S CANDIDATES ARE RANKED BY THE FEWEST CONVERSIONS
([over.match.best]; `cpp_ctor_holding`, `cpp_member_holding`, the free-function
road's rule since 0.45): the FIRST that held won before, and libc++'s pair
declares `pair(const _T1 &, const _T2 &)` before `pair(_U1 &&, _U2 &&)` --
given a `char *` the first held through the string's converting constructor,
where the second is exact, and `emplace("one", 1)` on a map of strings built
its node from the pointer's bytes; the copy pass runs on placement new's
constructor call too (`cpp_new_at`); (7) THE CLASS'S OWN VALUE IS READ OFF THE
DESUGARED FORM where the inference cannot type the raw one (`cpp_own_value` in
`cpp_ctor`'s first clause, 0.66's rule): pair's piecewise constructor hands
`std::forward<_Args2>(std::get<_I2>(args))`, a `Val &&`, to Val's member
initializer, refused as a copy; (8) A NESTED CLASS OF A LIBRARY CLASS IS THE
LIBRARY'S (`cpp_lib_class` through `'$cpp_enclosing'`): basic_string's `__rep`'s
implicit move constructor was emitted as the program's and checked (`move of a
non-owner`); (9) a scoped template-id parameter keys by its name and arguments
(`cpp_spec_key`: `initializer_list.string`, where the term was spelled letter
by letter, 0.80's ugliness); (10) a braced list as a subscript, `pm[{1, 2}]`
(the reader, `ccl_postfix_p`). THE READER (version 61), THE C++20 STRETCH by
the census loop over the level's flattened headers -- `<set>` at C++20 had
stopped at line 792 of 15,650, and every summary of a level held a tenth of
its header, silently: `X<T>::template f` alone as a template template
argument (`ccl_qrest`); a requires-clause on a MEMBER template's head, a
TRAILING one after a function's parameters (a member's, a definition's, a
prototype's: `ccl_method_quals`) and on a LAMBDA, after its template parameters
and after its declarator (dropped: a generic lambda is refused by name anyway);
THE CONSTRAINT GRAMMAR, primary expressions joined by `&&` and `||`
([temp.pre]; `ccl_constraint`), where the full expression took `[[nodiscard]]`
after a concept-id for a subscript; a CONSTRAINED TYPE PARAMETER, `template
<__exchangeable _Tp>`, `Concept<A> T`, `ns::Concept T` (`ccl_tparam_c`: a type
parameter and its concept-id as a requires entry of the head, conjoined with a
written one by `ccl_gather_requires` so the binders meet one entry, last),
read before as a value parameter of type `__exchangeable`; `f.template
operator()<I>()` (`ccl_member_name`); a MEMBER VARIABLE TEMPLATE, `template
<class _Up> static constexpr bool __check = ...;`, its name noted as a template
so `__check<_Up, _Up &>` reads as a template-id in the requires-clauses beside
it; a CONSTRAINED `auto`, `__integer_like auto operator()(...)` (`ccl_specs`: a
template's name before `auto` is a concept, dropped); LLVM 21's builtin traits
(`__builtin_lt_synthesizes_from_spaceship` and kin, answered false: no
`operator<=>` synthesizes a comparison here); a CONCEPT INDEXED BY ITS NAME
(`cpp_template_name(concept(...))`, registered on the first ask,
`cpp_hdr_join_concept`). WITH THEM `<set>` (482 items where C++17 reads 426),
`<map>` (486), `<unordered_map>` (377) and `<unordered_set>` (373) read WHOLE at
C++20, `<optional>` (272) and `<string>` (492) at C++23, `<optional>` (273) at
C++26 -- seven checks of the libc++ gate, a header at a level being a check of
its own (`at(H, Std)`, the level set for the read as `test/cpp.pl`'s `unit_at`
does) AND THE UNITS READ SO FAR FORGOTTEN BEFORE IT (`'$ccl_unit_paths'`): a
header is read once per process by its PATH (`ccl_unit_cached`), so the C++17
read was served to the level's check -- seven identical item counts, which is
what said so. THE DESUGARING AT THE LEVELS: a concept-id as a
template argument is its truth (`cpp_targ_value`: `conditional_t<
__primary_template<iterator_traits<...>>, ...>`, C++20's iterator_traits); a
VARIABLE template in a requires-clause is its value (`cpp_satisfied`: `requires
(!is_same_v<...> && is_constructible_v<_Tp &, _Up>)` on optional<T &>, taken
for a concept-id and refused `concept_without_body(is_same_v)`);
`__reference_constructs_from_temporary` and kin answer false; THE BLOCK
TYPEDEFS BEFORE THE FIRST RETURN are substituted into it before its type is
asked (`cpp_body_typedefs` in `cpp_method_ret` and `cpp_lambda_ret`, 0.60's rule
at walk time beside 0.81's declarations): libc++'s `transform` writes `using
_Up = remove_cv_t<invoke_result_t<_Func, _Tp &>>; ... return optional<_Up>(...)`,
and the first return typed raw instantiated `optional<_Up>` on the free name,
its bases refused one by one. THE LEVELS' FIXTURES, matching clang++ line for line:
`test/cpp/run/stdcontains.cpp` at C++20 (`contains` on a set, a map and the unordered
pair; `erase_if` on a set and on a map), `stdoptional3.cpp` at C++23 (the monadic
`and_then`, `transform`, `or_else`, the two chained, `value_or` on an empty optional)
and `stdoptionalref.cpp` at C++26 (`optional<int &>`: bound, written through, rebound,
an empty one's `value_or`). AND THREE MORE OF THE OLDER LISTS, closed by the same
work: `stdstringops.cpp` (0.66's `operator+`, `substr`, `find`, and the rest of the
string's surface: `rfind`, `append`, `push_back`, `insert`, `erase`, `replace`,
`compare`, `front`, `back`, `at`, `npos`, a range-for over the characters, `to_string`)
and `stdctad.cpp` (class template argument deduction, in an expression and in a
declaration). AND WHAT THE LEVELS' PROBES ASKED FOR, each
its own rule: (11) THE ARGUMENT PASS RUNS ON A TEMPLATE'S INSTANCE TOO (`cpp_call`'s
template clauses, the free road's since 0.79) -- a class value where the parameter
wants another class goes through its conversion operator, and libc++'s
`std::__concatenate_strings(a.get_allocator(), __lhs, __rhs)', whose parameters are
`__type_identity_t<basic_string_view<...>>', stored a basic_string's bytes into a
string_view, which LLVM refused; (12) A FUNCTION THE SHIPPED LIBRARY ONLY DECLARES
gets its result and parameters RESOLVED (`cpp_use_mangled`, 0.58's rule for an inline
one): `string to_string(int)' is declared under the raw alias, and `std::to_string(x)
+ "!"' deduced nothing for `operator+(const basic_string<...> &, const _CharT *)';
(13) CLASS TEMPLATE ARGUMENT DEDUCTION ([over.match.class.deduct], [dcl.type.class.deduct]:
`cpp_ctad_args' at the expression road and at a declaration) -- a class template's name
written with arguments deduces them from the IMPLICIT GUIDES, each constructor taken as a
function template over the class's own parameters, else an aggregate's data members in
order: libc++'s C++23 `__allocate_at_least' returns `__allocation_result{__res.ptr,
__res.count}', and with the bare name deduced its `.ptr' had no type; (14) A DEDUCED
RESULT'S CONDITIONAL is the arm the other converts to ([expr.cond]/4, `cpp_deduced_ret');
(15) A CANDIDATE'S RESULT TYPE IS RESOLVED ONLY WHERE ITS NAMES ARE BOUND
(`cpp_result_holds', [temp.deduct]/2): `__invoke_result_t<_Args...>' resolved with the
pack free instantiated `__invoke_result_impl<void, _Fn>' on that name; (16) A FILE-SCOPE
ALIAS IS THE CLASS IT NAMES in a path (`cpp_path_class'): `std::string::npos' was
flattened to the bare `npos'; (17) A STATIC CONST NAMED BARE AS A TEMPLATE ARGUMENT
folds to its value (`cpp_targ_value', 0.60's rule for an expression), which is how
libc++'s find calls `__str_find<value_type, size_type, traits_type, npos>'; and (18) IN
THE LOWERING, A REFERENCE TO A FUNCTION IS THE FUNCTION'S ADDRESS, with nothing to load
([conv.func]; `ir_convert' and the call's reference result): `std::forward<_Func>(__f)'
over `optional<int> (&)(int)' loaded the first eight bytes of the code and called them.
AND THREE THE GATE FOUND, each a defect of this step's own making:
(19) THE IMPLICIT DEFAULT CONSTRUCTOR IS NOTED WHERE THE CLASS EMITS IT, so a later
naming does not emit it again (`cpp_item`; `cpp_use_member' takes a lazy class's written
`C()' by the same name -- two identical definitions, which LLVM refuses); (20) A UNION'S
MEMBERWISE COPY IS ITS BYTES, copied by `memcpy' from the source's ADDRESS (0.83's rule
for an anonymous union member, here for a union class): as an assignment the two sides
were typed by two roads and basic_string's `__rep' loaded its source as `[0 x i8]' where
the slot was `{ i64, [16 x i8] }'; and (21) the implicit copy made ON DEMAND for a local
is THE PROGRAM'S OWN classes' (`cpp_ctor_args'), a library class's special members coming
through its own lazy road. Lowering version 31; reader version 63.
Seven gates GREEN under cocolog 1.2.14 (the module rebuilt for it: the reader's 94
checks, 6 s and 96 MB; the compile gate's 73 at 175 MB; the driver's 23 at 68; the
objects' 29; the proof; the C++ one 138 checks, 2157 s, 1350 MB; the libc++ one's 15
reads, 909 s, 1858 MB), and the C++ gate RED twice before them, each failure this step's
own (the three above); the libc++ gate died ONCE with no output at all, 155 s in and a
third of the way, straight after the C++ gate's 2157 s -- its script keeps only the lines
that match, so a crash leaves nothing to read, and the same query run alone gave the same
fifteen reads (896 s, 1980 MB) as the rerun did. AND WHAT 1.2.14 BOUGHT, warm against warm on the same fixtures:
the reader's peak 179 -> 96 MB, the compile gate's 326 -> 175, the driver's 83 -> 68,
the C++ one's 1489 -> 1350 -- the compaction's own peak, which the engine's owner cut by
sizing the new cell array at the live length instead of letting it double into place.
NOT DONE: the C++23 optional's
`transform` to a STRING and its `and_then` whose lambda returns a conditional over
`optional<int>` and `nullopt` (both stop at `__invoke_result_impl<void, _Fn>`, an
instance asked while the pack is free -- the trace `free_name_instance' names every
such ask now); `std::hash<optional>` (a local's `operator()' on that specialization);
`find_first_of` (`__str_find_first_of' cannot deduce its `_BinaryPredicate'); the
unordered containers' `erase_if`; `<vector>`, `<string>` and `<iostream>` read at
C++20 (only the associative containers and `<optional>`/`<string>` are); a program's
own `operator<=>`, `std::format`, the ranges.

**M6's fifty-third step (0.86): `<memory>`, whole -- `std::unique_ptr`,
`std::shared_ptr` and `std::weak_ptr` compiled from libc++'s own bodies.** THE
MODULE: `test/cpp/run/stduniqueptr.cpp` (a `unique_ptr<int>` over `new`, `*`,
`get`, `operator bool`, `reset`, `make_unique`, MOVED from and the source left
empty, a `unique_ptr` of the program's own class with a destructor counted, a
method through `->`, `release` and the raw pointer `delete`d, a default-built one
assigned from a `make_unique`), `stdsharedptr.cpp` (`make_shared<int>` with
`use_count` through a copy's scope, `make_shared` of a class with a destructor,
a `weak_ptr` from it, `expired`, `use_count`, `lock` into a second owner,
`reset` destroying the object and the weak pointer expiring with it,
`shared_ptr<int>(new int(12))` and its `operator bool`) and `stdmemory.cpp` (a
`unique_ptr<int[]>` over `new int[4]` and over `make_unique<int[]>(n)` with
`operator[]`, a CUSTOM DELETER whose parameter is `own`, `swap` as a member and
as `std::swap`, the comparisons with `nullptr`, `addressof`, a `unique_ptr` as a
class's member built in its constructor's initializer, an ALIASING `shared_ptr`
into the object's own member keeping it alive, two `weak_ptr`s and the object
outliving its first owner) match clang++ line for line, and `<memory>` is read
WHOLE in the libc++ gate. THE FORMS, each named:
(1) A POINTER TO MEMBER, `_Rp (_Cp::*)()` and `int C::*` ([dcl.mptr]), its own
node (`memptr(Class, Quals)`, `ccl_pointers`, `ccl_apply_pointers`) so it can
never be taken for a plain pointer: libc++'s `__weak_result_type` specializes
over one for every member-function shape, and the reader stopped at
`<memory>`'s line 4317 of 8957 on the first of them. Nothing lowers one; a
program that writes one is refused by name, and a specialization's pattern over
one matches nothing a program has. (2) AND ONLY A POINTER TO MEMBER FUNCTION
TAKES THE CV- AND REF-QUALIFIERS AFTER ITS PARAMETERS, `_Rp (_Cp::*)() const`
and `() &&` (`ccl_memptr_quals` in `ccl_decl_syntax`, the declarator's own
memptr the test) -- read in `ccl_suffix_quals`, where a function TYPE's
`noexcept` is dropped, they take a METHOD's own `const` with them, which is the
method rule's (`ccl_method_quals`): every const method in the language lost its
mark, the const overload, the const ordering and the `K` of a shipped member's
Itanium name with it (the link named
`__shared_weak_count::__get_deleter(const type_info &)` without it). The gate
did not find this -- our own mangling is `.c` on both sides of a call and
agrees with itself; the shipped library's does not. (3) A MEMBER CLASS
TEMPLATE'S NAME IS NOTED AHEAD with the member function templates' (0.81's
`ccl_member_templates_ahead`, now `struct`/`class`/`union` after the parameter
list): `shared_ptr` uses `__shared_ptr_default_delete<_Tp[], _Yp>` two hundred
lines before it declares it, which a complete-class context allows
([class.mem]/6), and read in order it was a pair of comparisons. (4) A TYPE THE
READER CANNOT SETTLE STAYS `auto` OUTSIDE A TEMPLATE TOO (`ccl_free_name`:
inside one every name the tables do not know is some parameter's, which is
0.60's rule unchanged; outside one a name the tables know as a typedef, a tag,
a template or an env entry is settled and anything else is somebody's
parameter): 0.60 asked the question only inside a template, and `auto q =
std::make_unique<int>(7)` written in `main` took `unique_ptr<_Tp>` off the raw
declaration a summary holds a function template under, with `_Tp` free -- the
lowering met `typedef(_Tp)`. The two branches are kept apart on purpose: a
template's own parameters ARE in the global env while its item is read, so
testing the env inside one would have made them settled and undone 0.60. (5) `typeid` is read
as its own node and refused by name. Reader version 67.
AND NO RTTI, the question 0.50 asked of exceptions asked again: libc++ decides
its `_LIBCPP_HAS_RTTI` by `#if defined(__cpp_rtti) && __cpp_rtti >= 199711L`,
and this compiler emits no `type_info` object for any type, so neither
`__cpp_rtti` nor `__GXX_RTTI` is predefined any more (`ccl_pp.pl`, commented
with the reason) and the library compiles its own no-RTTI configuration, as
`-fno-rtti` gives it. `shared_ptr`'s control block writes
`__t == typeid(_Dp) ? addressof(__deleter_) : nullptr` in an override; without
RTTI the override is not there and the base's shipped one answers null. Four
headers change (`any`, `exception_ptr`, `shared_ptr`, `function`) and the
VTABLES do not -- `__shared_weak_count::__get_deleter` is declared
unconditionally and only the derived override is guarded -- so our control
blocks lay out as the shipped library's. A program's own `typeid` and
`dynamic_cast` are refused by name with it: the cast had been passed through as
a plain one, which is a WRONG ANSWER for a downcast rather than a missing form.
THE DESUGARING: (6) A CLASS TYPEDEF THAT ASKS FOR ITSELF WHILE IT IS BEING
RESOLVED IS LEFT AS WRITTEN, a guard per (class, name) as `cpp_fold_static` has
one: libc++'s `type_info` writes `typedef __type_info_implementations::__impl
__impl` over a NAMESPACE, and the namespace flattening makes that `typedef
__impl __impl`, which asked for itself without end (139,393 flattens, 140 s to
2803 MB). THE SHAPE IS NO TEST, which is how this was first written and what
cost the day: `allocator_traits` writes `typedef typename __base::pointer
pointer`, the same spelling through a scope that DOES resolve, and refusing it
by shape left every `pointer`, `size_type` and `allocator_type` parameter of
the allocator traits raw at the lowering (`not lowered yet: typedef(pointer)`).
The guard is 4 s and 140 MB and resolves both. (7) `nullptr_t` TAKES A NULL
POINTER CONSTANT AND NOTHING ELSE in the TEMPLATE road too ([conv.ptr];
`cpp_param_accepts`, where 0.81 had put it at the fit and the arity-only last
resort): libc++ writes `unique_ptr(nullptr_t)` beside `explicit
unique_ptr(pointer)` as two constructor templates under one guard, both held
for `unique_ptr<int> p(new int(5))`, the first declared won, and `*p` read a
null. (8) `std::move(x)` NAMES AN OBJECT and is no temporary to elide
([basic.lval]: an xvalue, not a prvalue; `cpp_decl_pieces`' elide guard):
elided, `auto r = std::move(q)` made `r` the bytes of `q`, both unique_ptrs
held the pointer and both freed it. (9) THE ARRAY AND REFERENCE TRAITS
(`cpp_builtin_type`): `__remove_extent` and `__remove_all_extents`
([meta.trans.arr]), `__add_pointer`, and `__add_lvalue_reference` and
`__add_rvalue_reference` with REFERENCE COLLAPSING, where they had unreffed
first -- `shared_ptr`'s `element_type` is `__remove_extent_t<_Tp>`. (10) `new
T[n]()` and `new T[n]{}` VALUE-INITIALIZE every element ([expr.new]/24), which
for a scalar is its zero bytes -- `calloc` exactly, and `make_unique<_Tp[]>(n)`
is `unique_ptr<_Tp>(new _Up[__n]())`, the one place the form is asked for;
refused by name since 0.71.
THE CHECK: (11) A LIBRARY CLASS'S VALUE MAY BE MOVED (`ck_moves_library` in
`ck_expr(move)` and `ck_kind(move)`): what it holds is libc++'s own discipline,
as its pointers already are (0.79's `ck_carries_`) and its functions' bodies
are (0.45), and `auto r = std::move(q)` over a `unique_ptr` is the ordinary way
to use one -- refused as `move of a non-owner`, since the check has no owner
behind it and needs none.
THE LOWERING: (12) THE ATOMIC BUILTINS ARE LLVM'S OWN INSTRUCTIONS, never a
call to anything (`ir_atomic_rmw` and kin): `__atomic_add_fetch(p, -1,
__ATOMIC_ACQ_REL)` is how `shared_ptr` counts its owners
(`__libcpp_atomic_refcount_decrement`), and the compiler is asked for it by
name. An `atomicrmw` answers the OLD value, so a `*_fetch` form applies the
operation once more to it and a `fetch_*` form takes it as it is; `exchange`,
`load`, `store` and the two fences go with them, the load and the store
carrying the type's alignment beside the ordering. The memory order is the constant the header
spells, clang's own numbering, which this preprocessor predefines
(`__ATOMIC_RELAXED` 0 .. `__ATOMIC_SEQ_CST` 5); anything that does not fold is
sequentially consistent. Lowering version 32.
Seven gates GREEN, warm, at cocolog 1.2.15 (the reader's 94 checks, 40 s and
429 MB; the compile gate's 73 at 364 MB, 35 s; the driver's 23 at 68 MB; the
objects' 29; the proof; the C++ one 141 checks, 1885 s, 1480 MB; the libc++
one's 16 reads, 829 s, 2316 MB, `<memory>` 324 items) -- and the cache was
warmed OUTSIDE them first, one header a process at each of the four levels
(21 summaries), since the reader's version moved twice in this step and a cold
first run peaks far above the steady state. The three fixtures build in 6 to
50 s at 150 to 870 MB; `leaks` finds none.
NOT DONE: `shared_ptr::get_deleter` and `dynamic_pointer_cast`, which are not
there without RTTI -- what `-fno-rtti` means; `enable_shared_from_this`,
`owner_before` and `std::atomic<shared_ptr>` (untried); `make_unique<T[]>` of a
CLASS, whose elements need their constructor run over each and their destructor
over each at `delete[]`, which needs the ABI's ARRAY COOKIE (the count written
before the first element) that nothing here writes -- refused by name
(`new_array_of_objects`), with `new T[n]{a, b}` beside it; a program that calls
`std::allocator::allocate` directly, whose raw pointer the safe part refuses as
a loose one, exactly as it refuses a bare `malloc` with no `own` slot behind it;
`std::uninitialized_copy` and the `destroy_*` algorithms called by a program;
`std::unique_ptr`'s ordering operators; a POINTER TO MEMBER lowered (the reader
takes one, nothing else does); and `<atomic>`'s own surface -- the
compare-exchange builtins, the waits and the fences' scopes -- which is a module
of its own.

**M6's fifty-fourth step (0.87): THE RESULT TYPE OF AN UNINSTANTIATED TEMPLATE, and
the first LINUX port.** TWO PIECES, the first a defect three steps had named and none
had caught. `std::optional`'s C++23 `transform` to a class, its `and_then` over a
conditional and `std::hash<optional>` all stopped at
`no_member_type('__invoke_result_impl.void._Fn_', type)` -- an instance keyed by `_Fn`,
which is `std::invoke`'s OWN template parameter. THE RULE: `cpp_class_of_type_of`, the
class an EXPRESSION has, must not take a RAW type -- the guard `cpp_arg_type` has had
since 0.83 -- and `cpp_raw_type` now knows two more shapes: a template-id whose argument
is a free name, and one sitting in a SCOPED PATH, which is what `invoke_result_t<_Fn,
_Args...>` is once the alias is followed (`typename invoke_result<_Fn, _Args...>::type`,
whose last segment is `type` and whose scope carries the free name). Left raw, the value
falls to `cpp_init_arg_class`, which desugars the call, instantiates it, and reads the
instance's concrete result. WHY IT WAS FATAL rather than merely wrong: resolving that
type instantiated the traits on a free name, and the SFINAE specialization -- whose first
element is a `void_t<decltype(...)>`, matched in the non-deduced pass (0.46) -- cannot
match one, so the PRIMARY was chosen and the primary deliberately has no `type`.
THE INSTRUMENT THAT FOUND IT, and the reason 0.65's lesson had to be learned twice:
`cpp_where` kept ONE frame, so a trace inside an instantiation reported the ask naming
ITSELF (`in(class(__invoke_result_impl))`). It is a bounded stack now, six frames, kept
only while `'$cpp_trace'` is on -- an ordinary build pays nothing, since `nb_setval`
copies what it stores and the breadcrumb is entered at every statement -- with a frame on
the scope walk and the class context beside the free-name trace. It took the reproduction
from fourteen seconds over all of `<optional>` and `<string>` to a TWENTY-LINE program
that fails in one second at 3 MB, and three ingredients are necessary and sufficient: a
function template whose declared result is a dependent alias over its own parameters, a
class template whose constructor initializes a CLASS-typed member from a call to it, and
a specialization whose first pattern element is a SFINAE `void_t<decltype(...)>`. Drop
the third and it runs; drop the second as well and the bad ask never happens.
AND THE FIRST LINUX PORT, on a Colab runtime over an ssh tunnel: Ubuntu 24.04.4,
x86_64, two cores, clang 18.1.3, LLVM 18, SBCL 2.2.9, libc++ from the distribution.
Three things in THIS repository were macOS-shaped, each found by running and none by
reading. (1) `module/build-llvm.sh` linked `-lLLVM-C`, which is Homebrew's layout;
Debian keeps the C API inside the one `libLLVM` and the link simply fails ("cannot find
-lLLVM-C"). The name is read off disk now (`llvm-config --libdir`, `libLLVM-C.*` if it is
there, else `-lLLVM`), with the rpath following it. (2) THE INCLUSION PATH NEVER LOOKED
IN THE MULTIARCH DIRECTORY: Debian and Ubuntu split the C library's headers, `<bits/...>`
and `<sys/cdefs.h>` living in `/usr/include/<triplet>`, which clang searches BEFORE
`/usr/include` (`clang -E -v` lists it there). Without it the closure of `<stdio.h>` was
146 lines against clang's 828 over 35 files, and `__BEGIN_DECLS`, `__THROW`, `__wur` and
`_Nonnull((1))` reached the reader unexpanded; with it, 514 and every one expanded
(`ccl_multiarch_dirs`, both triplets offered and `ccl_existing_dirs` keeping whichever is
there, so macOS is untouched). (3) A NULLABILITY WORD MAY CARRY AN ARGUMENT LIST. glibc's
`__nonnull(params)` reaches this reader as `_Nonnull ( ( 1 ) )`, a spelling no compiler
emits on purpose -- and it is OURS: the predefined table is clang's, so `__clang__` is
defined, while `__has_attribute` answers 0 (the preprocessor's plainest path), and
`sys/cdefs.h` then takes a branch neither compiler would. Read as the bare qualifier
Apple's headers write, that `((1))` stopped the read of `<stdio.h>` at `fclose`, 69 lines
before `printf` was declared. Reader version 68.
WHAT THE SYMPTOM LOOKED LIKE, and it looked like nothing of the kind: `undeclared(printf)`
for a two-line program, because A PARTIAL READ IS SILENT (0.44) -- a reader that stops two
thirds of the way through a header leaves a unit that simply lacks the rest. The bisect
that settled it is worth keeping: the declaration ALONE, `extern int printf(const char *
__restrict, ...);`, compiles and runs, so the reader was stopping short and not reading
and dropping. Those are different defects and only a measurement tells them apart.
AND A TRAP THAT COST A WRONG CONCLUSION mid-chase: `cicili++ -fsyntax-only` PASSES on that
same file on Linux, because in C++ mode the driver skips the check and the lowering under
that flag. A flag that skips the stage under test passes for a reason that has nothing to
do with the question, so it reads as evidence of health and is evidence of nothing; the
tell is that the good news arrived too cheaply.
Seven gates GREEN, at cocolog 1.2.16 and reader 68, the cache warmed OUTSIDE them first at
all four levels (21 summaries), since the reader's version moved and a cold first run peaks
far above the steady state: the reader's 94 checks, 39 s and 388 MB; the compile gate's 73 at
370 MB; the driver's 23 at 68; the objects' 29; the proof; the C++ one 141 checks, 1995 s,
1441 MB; the libc++ one's 16 reads, 859 s, 2278 MB.
NOT DONE: the Linux gates. cicili-lang compiles and runs C and C++ there, and the C++ gate
reaches 83 of its checks where before the three fixes it reached none, but six fail and each
is its own glibc gap -- `stdcin.cpp' stops at `template_without_body(basic_string)', a
template body that did not survive into the summary, which says `<iostream>''s closure is
short there as `<stdio.h>''s was. The libc++ gate has not run there at all. AND THE RULE THAT
DID NOT TRAVEL WITH THE GATES: every cocolog run of mine on the Mac goes through a watchdog
that samples resident size and kills past 2800 MB, and the Linux chain was written without
one -- an hour of gates with no cap on a box whose `/sys/fs/cgroup/memory.max' reads `max'
from inside, so the real ceiling is imposed from outside and invisible to the obvious check.
Nothing of ours was killed (the OOM took a 9.7 GB neighbour and the notebook's own node), but
that was luck and not design; the cap goes in before Linux runs again, and a gate that dies
with no output is `dmesg | grep -i "killed process"' before it is anything else.

**M6's fifty-fifth step (0.88): `<functional>`, whole -- `std::function`, `std::bind`
and the callable adaptors compiled from libc++'s own bodies.** THE MODULE:
`test/cpp/run/stdfunction.cpp` (a `std::function<int(int)>` from a function pointer, a
lambda, a functor and an empty one; `operator bool', the null comparisons, a copy, an
assignment, `swap'; a void result, two arguments, a capturing lambda, and a vector of
them walked by a range-for), `stdbind.cpp` (`std::bind' with the placeholders, one
reordering its arguments and one repeating a placeholder; `mem_fn' of a nullary and of a
one-argument method; `std::invoke' of a free function, of a pointer to member and of one
with an argument; a pointer to member written out and called with `.*' and `->*';
`std::ref' into a `std::function'; a member function bound to an object) and
`stdfunctional.cpp` (the arithmetic, comparison, logical and bitwise function objects, the
transparent `less<>' and `plus<>', `reference_wrapper' with `ref', `cref', `get' and a
rebind, `std::hash' of an int and of a string, a function object as a set's comparator)
match clang++ line for line, and `<functional>` is read WHOLE in the libc++ gate (472
items). THE READER (version 69), by the census loop: (1) A POINTER TO MEMBER FUNCTION
TAKES THE NOEXCEPT-SPECIFIER after its cv- and ref-qualifiers ([dcl.fct]/1, the order cv,
ref, noexcept), which `__strip_signature<_Rp (_Gp::*)(_Ap...) const noexcept>` and its
fifteen siblings spell -- 0.86 read the cv- and ref- ones and stopped there, and the header
died at line 4421 of 18167; `ccl_suffix_quals' is the one rule for `noexcept' and `throw(...)',
and the member-pointer qualifiers now end in it. (2) THE RIGHT SIDE OF AN ASSIGNMENT MAY BE
A BRACED LIST ([expr.ass]/9: `x = {}' value-initializes, `x = {a, b}' list-initializes),
which is how `__policy_func''s move constructor empties the one it moved from,
`__f.__func_ = {};'. (3) `x.*pm' AND `p->*pm' ([expr.mptr.oper]) are read from the two
punctuators the lexers already have -- no C writes `.' before `*' and none writes `->'
before one -- so NEITHER LEXER CHANGES and k84 still compares them token for token; only a
CALL of the node means anything here. (4) `__alignof' and `__alignof__' beside `alignof',
and `alignof(T)' FOLDS to the alignment the layout already computes (nothing evaluated it
before: the reader made the node and no pass took it).
TWO NAMESPACES OF ONE FLATTENED NAME, the open item since M6's first step: `<functional>`
declares `std::__maybe_derive_from_unary_function<_Tp, bool>' -- what `__weak_result_type'
derives from, named unqualified -- and `std::__function::__maybe_derive_from_unary_function<_Fp>'
-- what `std::function' derives from, written `__function::...' -- and flattened to one bare
name the first won both, so `function<int(int)>' took the two-parameter one, whose defaulted
second argument asks a detection over a member pointer that nothing could answer. THE
OUTERMOST NAMESPACE KEEPS THE BARE NAME (an unqualified use from there is what C++ finds);
every deeper namespace's items are indexed under `<innermost namespace>.<name>' with the
name inside the item rewritten (`cpp_ns_quals', `cpp_qualify_item'), and a use QUALIFIED by
that namespace resolves to it (`cpp_ns_key', in `cpp_type'). The decision is a function of
the header's own items, so the index and the AST beside the summary reach it alike without
either telling the other -- and it is the reader version's business, since the AST's keys
change. Measured on `<functional>`: exactly two names collide.
THE DESUGARING, each form named: (5) A PARTIAL SPECIALIZATION'S PATTERN MAY BE A FUNCTION
TYPE, `function<_Rp(_ArgTypes...)>' ([temp.deduct.type]/8: the result type and the parameter
types are deduced elements of their own, a trailing pack taking every parameter left) --
`function', `__func', `__value_func', `__policy_func' and `__alloc_func' are each a primary
template declared and never defined beside one specialization over a function type, and
without it every one of them fell to the primary and the instance was an incomplete type; a
function type as a TEMPLATE ARGUMENT is matched exactly, never decayed. (6) A FUNCTION TYPE
DECAYS TO A POINTER TO FUNCTION ([conv.func]), as an array does to a pointer to its element:
`std::function<int(int)> f = twice' hands `twice' to `function(_Fp)', whose `_Fp' is `int
(*)(int)' -- deduced as the FUNCTION type, `__decay_t<_Fp>' kept it, and `__func<int(int),
int(int)>' held its callable in a member of function type whose ADDRESS was then called
instead of its value; and a function CONVERTS to a pointer to itself, which is what
`is_constructible<_Fd, _Gp>' asks of `std::bind''s `int (&)(int, int, int)'. (7) A VIRTUAL
OVERLOAD SET: a slot is named by the method AND ITS ARITY, since `__base''s `virtual __base
*__clone() const' and `virtual void __clone(__base *) const' are two slots -- named alike,
the table's struct had the member twice, the dispatch took the first, and a COPY of a
`std::function' called the nullary clone with two arguments. (8) A VIRTUAL `operator()'
DISPATCHES, as a named method already did: `std::function' calls what it holds through
`(*__f_)(std::forward<_ArgTypes>(__args)...)', whose `__base::operator()' is PURE, and
called directly the link named it. (9) MULTIPLE INHERITANCE WHERE A BASE AFTER THE FIRST HAS
STORAGE OF ITS OWN ([class.derived]: the non-virtual bases in declaration order, then the
class's own members): each is a sub-object `$base$2', `$base$3' ... laid out after the first
base, constructed and destroyed with it, reached by the member lookup, the hops and the
lowering's base walk (`ir_base_route', one route found and walked where two walks found
their own); an EMPTY extra base is still a scope and no bytes (0.71), and only a POLYMORPHIC
one is refused, since two tables need a `this' adjusted at every call. `std::tuple' is built
this way -- `__tuple_impl<__tuple_indices<_Indx...>, _Tp...> : public __tuple_leaf<_Indx,
_Tp>...', one base per element -- and `std::bind' stores its bound arguments in one.
(10) A POINTER TO MEMBER FUNCTION keeps its shape through the passes (`memptr(C, Q, T)'),
so the deduction and the thirty specializations `__weak_result_type' writes over it read it
as it stands, and only the lowering turns it into what it is here: the ADDRESS of the one
function this compiler emits for that method, whose first parameter is the object. `&C::m'
is that address cast to the member-pointer type; `__builtin_invoke(pm, obj, args...)' and
`(obj.*pm)(args)' are the indirect call. A pointer to a VIRTUAL member (which would have to
carry a table index), to a DATA member (an offset) and an OVERLOADED member's address
(no target here to choose by) are refused by name. (11) A DECLTYPE'S EXPRESSION AND A
TEMPLATE ARGUMENT ARE WALKED IN THE CLASS they are written in, where C++ looks their names
up: `using type = decltype(__find_base(static_cast<_Tp *>(nullptr)))' names a static member
of that class, and `aligned_storage<sizeof(__buf_)>::type __tempbuf' names a member of the
enclosing one -- walked with no context both stayed as written and neither had a type.
(12) A STATIC METHOD NAMED BARE inside its class takes a null `this', as a static member
template has since 0.47, and AN ELLIPSIS IS C++'S WORST MATCH for a plain overload too
([over.ics.ellipsis]): `static void __find_base(...)' is the answer where the template
beside it deduces nothing, and it is tried after every other overload and every template.
(13) A FILE-SCOPE `const' OBJECT OF INTEGRAL TYPE WITH A CONSTANT INITIALIZER IS A CONSTANT
EXPRESSION ([expr.const]; the rule 0.63 gave a `const' LOCAL): libc++ writes `inline const
size_t __aligned_storage_max_align = alignof(__max_align_impl<...>);' and every
`aligned_storage' asks for that name inside a variable template's initializer, where only a
constant will do. The initializer is desugared before it is folded, under a guard per name,
and only a SUCCESS is remembered -- asked once from inside a candidate whose walk is
abandoned, a remembered failure would stand for ever. (14) A CLASS WHOSE ONLY CONSTRUCTOR IS
A TEMPLATE takes arguments as a temporary: libc++'s `bind' writes `typedef __bind<_Fp,
_BoundArgs...> type; return type(f, args...)', and counted by its data members the call took
more than the class has and was left as a call to the class's own name. (15) A DATA MEMBER OF
FUNCTION-POINTER TYPE IS CALLED THROUGH, as C calls one, where the refusal `no_member' is
for a name the class does not have at all. (16) `cpp_is_type' knows a pointer to member, so
the two-pass pattern matching puts one where it belongs.
Reader version 69, lowering version 33. Gated by the three module fixtures above and by
`test/cpp/run/multibase.cpp` (two bases with storage and an empty one, the offsets, a
deeper derivation and the memberwise copy) and `detectbase.cpp` (the detection idiom
`__weak_result_type' is written on: a variadic static member function beside a template one,
read through a decltype at class scope).
NOT DONE: `alignas' is still dropped, so `__aligned_storage_max_align' folds to 1 and
`std::function''s inline buffer is 24 bytes aligned 1 where clang's is 32 aligned 16 -- self
consistent, and in practice 8-aligned by its place in the object, but not the ABI's layout;
`sizeof' OF AN EMPTY CLASS IS 0 here and 1 in C++ ([class]/4), which cannot be fixed by
itself, since the empty base would then take a byte where C++'s optimization gives it none
-- the pair belongs to one step of its own; `sizeof' a pointer to member function is 8 and
not the ABI's 16, the price of refusing the virtual case; an UNQUALIFIED use of a colliding
name from inside the deeper namespace still finds the outer one (libc++ qualifies every one
of them); `std::function::target' and `target_type' (RTTI is off, 0.86); `std::not_fn',
`std::identity' and `std::bind_front' (C++17/20, untried); `std::invoke' of a pointer to
DATA member; `std::bind' of a member function pointer as the callee with `std::ref'ed
arguments; and `<tuple>' as a module of its own, which the multiple inheritance above is
the road to.
Seven gates GREEN at cocolog 1.2.16, the cache warmed OUTSIDE them first at all four levels
(22 summaries, `<functional>` the new one), since the reader's version moved: the reader's 94
checks, 38 s and 396 MB; the compile gate's 73 at 358 MB; the driver's 23 at 77; the objects'
29; the proof; the C++ one 146 checks at 1623 MB; the libc++ one's 17 reads, 945 s, 2306 MB.
AND THE C++ GATE'S CLOCK IS NOT A NUMBER THIS TIME: it read 16655 s against 0.87's 1995, and
`pmset -g log` says the machine was ASLEEP for 173 of those 278 minutes -- a clamshell sleep on
battery at 16:05 for eighty minutes, then five maintenance sleeps. The gate measures elapsed
time with `date +%s`, so it measured the lid. I read the number as an eight-fold REGRESSION
and named a cause before measuring; the owner said sleep, and the log said sleep. What the
regression would have looked like was in front of me and I passed it twice: the sampled rate
was four fixtures in one half-hour and twelve in the next, and a slowdown in the compiler is
evenly slow. The measurement that settles it is one fixture against a recorded number, awake,
with the CPU time beside the wall clock: `test/cpp/run/stdmap.cpp` builds in 28.3 s of user
time at 489 MB (18 s at about 1.1 GB when 0.79 recorded it, nine steps and cocolog's store
compaction ago), and with `cpp_global_const' STUBBED TO FAIL -- 0.87's behaviour, the predicate
being new here -- 28.6 s: this step's one addition to the hot path costs nothing measurable.
The libc++ gate ran in a window with no sleep in it and is the honest comparison: 945 s against
859 at 0.87, for one header more.

**M6's fifty-sixth step (0.89): THE LAYOUT RULES A CLASS'S BYTES ARE MADE OF -- the empty
class, the empty base, `alignas' and `[[no_unique_address]]'.** 0.88's not-done list opened
with a PAIR that cannot be taken one at a time, and said so: `sizeof' AN EMPTY CLASS IS ONE
in C++ ([class]/4) -- two objects of it must have two addresses, an array of three is three
bytes, and `new' must hand back something -- while an EMPTY BASE takes NO BYTES (the empty
base optimization), so the first rule written alone would grow every class derived from an
empty one by a byte C++ does not give it, and libc++'s allocators, comparators, tuple leaves
and `__weak_result_type' are empty bases everywhere. It became a TRIO, since two more of that
list are the same question asked of a member: `alignas' was dropped by the reader, so
`std::function''s inline buffer came out aligned 1, and `[[no_unique_address]]' was dropped
with it, so libc++'s marked allocators and paddings each took a byte the ABI does not give
them. THE FOUR RULES: (1) A CLASS WITH NO DATA MEMBERS AT ALL IS ONE BYTE (`ccl_class_size',
in cpp only: in C an empty struct is a GNU extension of no bytes and stays so), and the test
is the MEMBERS and not the layout -- keyed on `lays out to zero', `struct Z { char p[0]; }'
came out 1 where C's answer and clang's is 0, and libc++'s compressed-pair padding, `char
__padding_[sizeof(_ToPad) - __datasizeof_v<_ToPad>]', is exactly such a member. (2) AN EMPTY
BASE HAS NO SUB-OBJECT (`cpp_base_layout_'): no `$base' member is laid down for it, the
base's address IS the object's (`cpp_base_place', `cpp_base_src', `cpp_base_hop', the three
doors that named `$base' on their own), and its typedefs, statics and methods are found
through `cpp_base_scope' as the EXTRA empty bases have been found since 0.71 -- this is that
rule, moved to the first base, where 0.71 could only have it after the first. A MEMBERWISE
COPY MUST NAME THE SOURCE'S BASE AS THE BASE (`cpp_base_src''s reference cast): handed the
object itself, the overload choice looked for a base constructor taking the DERIVED class and
refused `base_constructor'. AND SLICING TO SUCH A BASE IS A CHANGE OF TYPE AND NOTHING ELSE:
`cpp_copies_' sliced a derived object handed to a by-value base parameter only where the base
walk gave HOPS (0.79's rule), and an empty base leaves none -- libc++'s `__priority_tag<N> :
__priority_tag<_N - 1>' is a CHAIN of empty classes, so `__priority_tag<1>()' reached the
`__priority_tag<0>' fallback of `__try_key_extraction_impl' carrying its own type and LLVM
refused the store (`stdmapown' in the C++ gate, the one fixture of 149 that said so). With no
hops every base on the path is empty, so the value carries nothing and only the TYPE moves; the
argument's evaluation is kept beside the base's own empty aggregate, since it may have effects. (3) `alignas' ON A CLASS, A STRUCT OR A UNION ([dcl.align]) is
KEPT by the reader where every other attribute is dropped -- as `align_as(E)' at the END of
the members, the head being where `union_tag' and `enum_base' sit -- folded in the class's
own words by the desugaring as a bitfield's width and an array's bound are (`cpp_align_tag'),
and read by the layout (`ccl_align_as' through `ccl_tag_size': never smaller than the natural
alignment, the size rounded up to it). AND AN EMPTY BASE STILL CONTRIBUTES ITS ALIGNMENT
though it takes no bytes ([class.derived]: the optimization is about storage), which is
written as an `align_as' marker of its own (`cpp_empty_base_align'): libc++ finds the widest
alignment a platform has by deriving `__max_align_impl' from six `alignas'-carrying EMPTY
bases and asking `alignof' of it, and with their alignment dropped it answered 1 --
`alignof(T)' itself has folded since 0.88, so the alignment was there to be read and nothing
carried it. `alignas(T)' is read as that same `alignof_type(T)' (`ccl_align_arg', the type
name tried once and only where a `)' follows it, so `alignas(16)' stays the expression it is).
(4) `[[no_unique_address]]' ([dcl.attr.nouniqueaddr]) is C++20's empty base optimization for a
MEMBER, and the ONE attribute the reader does not drop: an empty member marked with it takes
no bytes and keeps its alignment, a member with bytes of its own lies where it always did.
libc++ marks every container's allocator and comparator with it. The mark is noted as the
attribute goes past (`ccl_skip_attr', since the attributes sit inside `ccl_decl_specs', which
every declaration in both languages shares) and CLEARED ONCE PER MEMBER in `ccl_members' --
not in the declarator, since `ccl_member_decl' has a clause that drops an attribute and
RECURSES, and a reset there wiped the very flag that attribute had just set; it travels in
the member's BIT-WIDTH slot, where a width would sit and no width can (`ccl_plain_width',
`cpp_bit_width'), so nothing else in the passes changes shape, and the layout gives `lay(N,
T, Off, empty)'. AND THE LOWERING'S SHAPE AGREES WITH THE LAYOUT (`ir_struct_shape' through
`ccl_tag_size'): an empty class is one byte in LLVM too, an `alignas' class is padded to the
size its alignment gives it, and a marked empty member is a zero-sized element, `{}', so the
GEP still gives its address.
AND A MEMBER THAT OWNS NO STORAGE MOVES NO BYTES, which the byte of rule (1) made urgent: an
empty class's byte is PADDING as a complete object and NO byte at all as a marked member,
whose address may be one past its holder's own or shared with a neighbour. So such a member is
zero-filled by nothing and copied by nothing (`cpp_zero_fill', at the four value-initialisation
doors and the memberwise copy beside them), and in the lowering a store through its slot writes
nothing while a load answers the type's zero (`ir_store_slot', `ir_load_slot' over the `empty'
mark the shape map now keeps) -- the net under every road that reaches a member slot. Before
it, libc++'s `: __alloc_()' over a marked allocator was a `memset' of sizeof, zero before this
step and ONE after, at an address the member does not own. Two roads fell out of writing it:
`ir_ref_of' handed a SLOT out as a pointer without passing `ir_slot_addr', which leaked a
bitfield's slot into the emitted text long before this step, and `ir_gelems' had no clause for
a member with no bytes and would have fallen into the bitfield packer for a global.
AND THE TEST FOR AN EMPTY CLASS IS ITS MEMBERS, NOT ITS LAYOUT -- written ONCE
(`ccl_no_data_members', asked by `ccl_class_size' and `ccl_empty_layout' alike). Written as
`lays out to zero' the second was wrong in exactly the way the first had already been wrong in
this same step, and I did not carry the lesson three lines down: `ccl_members_layout_' SKIPS a
member whose type it cannot size yet (its last clause takes any term), so a class whose members
are not resolvable at the moment of asking lays out to zero and reads as EMPTY. libc++'s
`_LIBCPP_COMPRESSED_PAIR' marks `__rep_' ITSELF with `[[no_unique_address]]', so basic_string's
24-byte union became a member of no bytes: the emitted struct was `{ {}, padding, {}, {} }'
with no `__rep_' in it at all, `a + ", "' came back EMPTY and `substr' then aborted on
out_of_range, while `a' alone still printed `hello' and `sizeof(std::string)' still read 24.
AND THE RIGHT LAYOUT IS CHEAPER, measured on the same machine within the hour, the spread cold at
reader 71 before and after the one-line rule: `stdvector' 82 -> 14 s and 788 -> 380 MB,
`stdfunctional' 253 -> 60 s and 1412 -> 894 MB -- a struct whose union had vanished sent the
desugaring down roads the program never needed.
FOUND ON THE WAY, each a defect older than this step: A PLAIN STRUCT NAMED AS A BASE IS A
CLASS (`cpp_note_bases', `'$cpp_base_named''), since `struct Tag { }; struct X : Tag { ... }'
is everyday C++ and every empty base there is, while the reader keeps a C++ struct of data
members as C's -- nothing registered Tag and the derived class refused
`base_not_registered'; the names are collected BEFORE anything is registered, as the free
functions have been since 0.56, since a base is named after its own item and the decision
must be made once for the registration and the emission alike. THE LAYOUT MARKERS ARE TAKEN
OUT AT ONE DOOR (`ccl_members_of'): the check's field walks and the lowering's member roads
read that predicate, and an `align_as' where a `member/3' is expected failed a walk without a
word -- `phase(check)', the diagnostic 0.53 put there for exactly this. AND A TAG WHOSE
MEMBER LIST CARRIES A MARKER IS STILL A PLAIN STRUCT (`ccl_class_shape', one predicate where
two places tested the shape by hand): read as a class's, an `alignas' struct answered its raw
class where its desugared struct was meant and `sizeof' had nothing to lay out.
Reader version 71 -- 70 for `alignas', 71 for the mark, and BOTH bumps were owed: the mark
lives in the member terms an AST beside a summary holds, so left at 70 every cached header
kept serving members with `none', `sizeof(std::string)' read 40 against the library's 24 and
its `__data_' sat one byte late, which read as a fresh defect and was a stale cache. The rule
this repository already had (a change to what the AST holds bumps the version, 0.71) covers
the index and covers this.
Lowering version 34.
Gated by `test/cpp/run/emptyclass.cpp' (an empty class, an empty base, two of them, a MEMBER
of empty class type taking its byte, an array of three, and a pointer to an empty base at the
object's own address), `alignas.cpp' (on a struct, over-aligned, `alignas(T)', on a union, as
a member of another class, on an empty base, and the object's address checked at run time) and
`nounique.cpp' at C++20 (a marked empty member costing nothing and the same member unmarked
taking its byte, two marked, an over-aligned one, a marked member WITH bytes lying where it
always did, a trailing one, and libc++'s compressed pair's shape), clang++'s numbers.
Seven gates GREEN at cocolog 1.2.16, warm (the cache had been warmed outside them at all four
levels when the reader moved to 71): the reader's 94 checks, 6 s and 99 MB; the compile gate's 73
at 226 MB; the driver's 23 at 67; the objects' 29; the proof; the C++ one 149 checks -- 146 and
this step's three -- at 1739 MB; the libc++ one's 17 reads, 993 s, 2035 MB.
AND THE C++ GATE'S CLOCK IS A NUMBER THIS TIME, and it is a bad one: 6147 s against 0.87's 1995
for 141 checks, with `pmset -g log' showing NO sleep in the window (the first thing to ask since
0.88). The libc++ gate, which only READS the headers, is 993 s against 945 -- five percent -- so
the reader is untouched and every one of those minutes is in the passes that COMPILE. I NAMED A
CAUSE AND IT WAS WRONG: this step put `ccl_tag_size' inside `ccl_size_align', the hottest
predicate there is, with a `findall' in `ccl_align_as' allocating at every struct sizing, and that
is a good story -- but measured one variable at a time, warm against warm, the same fixture built
against the COMMITTED 0.88 costs the SAME (`stdmap': 37.5 s of user time at 0.89, 38.6 at 0.88,
519 MB against 420). The layout rules cost nothing measurable. The gate's average is 41 s a check
where 0.87's was 14, so the time is in OUTLIERS and not spread evenly -- `stdset3' alone took
twenty minutes of it -- and an outlier is where the next measurement goes. A THIRD number of mine
was no measurement either: the spread's `stdmap' at 105 s and 1182 MB, which I offered as evidence
of a slowdown, was the same code on a MIXED-AGE summary cache; wiped and warmed it is 31 s and
519 MB.
NOT DONE: an empty marked member that is NOT THE FIRST lies one past the members before it where
clang overlaps it with them, and two marked members of ONE empty type share an address where C++
gives them two -- the SIZES agree with clang in both, the addresses do not; `sizeof' a pointer to
member function is still 8 and not the ABI's 16; and A CONVERSION NEVER FIRES FOR A REFERENCE
PARAMETER -- `ccl_resolve_type' passes a `ref' through unchanged and the type-level class test
must not unref (0.51's rule), so `cpp_conv_fits' falls to `RT == RCT' and fails -- which is why
`std::string_view v = s;' takes string_view's COPY constructor over the string's own bytes; that
one is older than this step, found by a probe written for it, and a step of its own (the
by-value road, which is what `__concatenate_strings' uses, works).

**M6's fifty-seventh step (0.90): `<tuple>`, and the conversion 0.89 left named.** The owner's rule
of 0.78 (a module at once) over `<tuple>`, whose every element libc++ keeps in a BASE of its own
(`__tuple_impl<__index_sequence<_Indx...>, _Tp...> : public __tuple_leaf<_Indx, _Tp>...'), so the
module rests on 0.88's multiple inheritance and 0.89's empty base -- and the first thing it found
was that neither of those laid an object out wrong, but a CAST to one of them did. THE FORMS, each
named: (1) A CAST TO A REFERENCE IS A CONVERSION OF ITS OWN, and the offset is from the OPERAND's
class to the CAST's target ([expr.static.cast]): `ccl_type_of' of a cast answers that target, so
taken whole by `ir_ref_to' the two classes were EQUAL, no base hops were walked and the object's
own address went out -- `L1::sw(static_cast<L1 &>(o))', which is how libc++'s tuple swaps its
leaves, swapped the second leaf of `this' with the FIRST of the argument (`t.swap(u)' on two
tuples gave 5 1 / 2 6 where C++ gives 5 6 / 1 2). The cast's own conversion is made at the one
door and whatever the binding still needs after it follows on the result; a local reference and a
pointer already took their offsets, which is why this survived 0.72. Lowering version 35;
`test/cpp/run/basecast.cpp'. (2) THE TUPLE PROTOCOL ([dcl.struct.bind]/4): where
`std::tuple_size<E>::value' is a constant, THAT many bindings are asked for and each is `get<i>(e)'
-- a tuple has no data member of its own, so the by-position member road found none and refused
`bindings_count'; an E that is no tuple has no such constant and the member road stands. (3) A
BOUND TYPE PARAMETER CALLED takes its ARGUMENTS SUBSTITUTED FIRST and its arity read off the
result, since a PACK EXPANSION is ONE element until it expands: `_TupleDst(std::get<_Indices>(
std::forward<_TupleSrc>(__src))...)' was taken for the one-argument functional cast and its pattern
substituted whole, refusing `pack_unexpanded'. One predicate for the three shapes (`cpp_type_called',
the owner's rule) where three clauses each matched an arity of the RAW list;
`test/cpp/run/packcall.cpp'. (4) AN ARRAY BOUND DEDUCES ([temp.deduct.type]/9: `T (&a)[N]' binds N
from the argument's own bound), which a REFERENCE parameter brings undecayed -- there was no clause
for an array PATTERN at all, only for a pointer pattern against an array argument. (5) A STATIC
MEMBER ARRAY's initializer is RECORDED (the `static' sits in the innermost base's qualifiers, so an
array's is reached through `cpp_static_type' as 0.72 already reached its type; a plain `base(Q, _)'
missed it) and is ITS OWN DEFINITION, `linkonce', as a folding scalar's has been since 0.45
(`cpp_static_aggregate', the items desugared in the class's words); and A STATIC DEFINED IN THE
CLASS IS NOT A SHIPPED SYMBOL -- named by its Itanium symbol (0.73) libc++'s `__matches' had no
type at the call that searches it. (6) A CONSTEXPR CALL AND AN INDEX INTO A CONSTANT ARRAY FOLD
WHEREVER THEY SIT: libc++ writes its search as `__i == _Nx ? __not_found : __find_idx_return(__i,
__find_idx(__i + 1, __matches), __matches[__i])', a conditional whose arms hold the recursive call,
so `ccl_const_eval' failed on the whole expression and nothing reached 0.72's call clause; the
forms that one evaluator cannot take are folded to their literals first and the arithmetic left to
it (the table is written once). (4) to (6) together are `std::get<T>', the by-type get;
`test/cpp/run/arraybound.cpp' has the shape on the program's own classes. (7) A HEADER'S INLINE
VARIABLE WITH NO INITIALIZER, which C++ VALUE-INITIALIZES ([dcl.init]/8; a `constexpr' object must
be initialized and none written is that): `inline constexpr __ignore_type ignore;' is
`std::ignore', and the index took only an inline variable WITH an initializer, so it was never
registered and reached the lowering as an `external global' the link named. Only an EMPTY class is
taken -- a class with a constructor would have to be constructed, and nothing here is evaluated at
compile time. The index is what the AST beside a summary is written by, so reader version 72.
(8) AND AN ASSIGNMENT TEMPLATE COUNTS where a class is asked whether it is ASSIGNABLE, as a
constructor template already counted in `cpp_ctor_arity_fits' (0.46): `__ignore_type''s only
`operator=' is `template <class _Tp> const __ignore_type &operator=(const _Tp &) const', so
`is_assignable<__ignore_type &, int const &>' read FALSE, tuple's CONVERTING assignment
(`operator=(tuple<_Up...> const &)') was rejected with it, and the copy assignment then took a
`tuple<int, int>' for a `tuple<int &, __ignore_type &>' -- an int read as an address, and
`std::tie(a, std::ignore) = f()' died before its first line. It was hidden until (7) made
`std::ignore' link at all.
AND THE CONVERSION 0.89 NAMED AND LEFT: a class value where `const T &' is wanted converts through
its `operator T()' and the reference binds to the PRVALUE the operator makes ([over.ics.user],
[dcl.init.ref]/5), so neither the reference NOR THE `const' ON IT is the conversion's business. THE
SCORER AND THE EMITTER DISAGREED: `cpp_arg_fit_' unrefs the parameter before it asks and so looks
through `const Yards &', and then `cpp_ref_args_' handed `cpp_conv_to' the type AS WRITTEN, where
`cpp_conv_fits' had neither an arithmetic pair nor two pointers nor two REGISTERED classes to
compare -- a plain struct is no registered class -- and fell to `RT == RCT', which the reference,
and then the `const' under it, each defeat on their own. Stripping at the emitter's one door leaves
every SCORE where it was and only makes the emission agree with the choice. 0.89 recorded the
symptom as string_view taking its copy constructor over the string's bytes; measured one variable
at a time against the committed library, `std::string_view v = s;' SEGFAULTS at 0.89 and gives
C++'s answer with this. `test/cpp/run/convref.cpp'.
WHAT RUNS: `test/cpp/run/stdtuple.cpp' -- a tuple built, subscripted by index and BY TYPE, written
through, made by `make_tuple' and `forward_as_tuple' and from a `pair', its `tuple_size' and
`tuple_element', `tie' and `tie' with `std::ignore', the comparisons, structured bindings by value
and by const reference, a `std::string' held and a tuple of them MOVED, a copy, the member `swap'
and `std::swap', and `std::apply' -- clang++ line for line, and `<tuple>' read WHOLE in the libc++
gate. Beside it `basecast.cpp', `packcall.cpp', `arraybound.cpp' and `convref.cpp', each the shape
on the program's own classes.
Seven gates GREEN at cocolog 1.2.16, the cache warmed OUTSIDE them first at all four levels (the
reader moved to 72): the reader's 94 checks, 44 s and 393 MB; the compile gate's 73 at 365 MB; the
driver's 23 at 80; the objects' 29; the proof; the C++ one 154 checks -- 149 and this step's five --
6850 s at 1760 MB, with no sleep in its window (`pmset -g log', the rule since 0.88); the libc++
one's 18 reads, 1096 s, 2310 MB, `<tuple>' 182 items. The C++ gate's 6850 s against 0.89's 6147 for
149 is the five new fixtures and nothing else measurable -- `stdtuple' alone builds in 125 s -- and
0.89's open question, why a check averages 41 s where 0.87's averaged 14, is untouched by this step
and still wants its outlier measured.
AND SEVEN GATES GREEN A SECOND TIME, at cocolog 1.2.18 with the module rebuilt (0.79's precedent for
recording both): the reader's 94 checks, 6 s and 150 MB; the compile gate's 73 at 184 MB; the
driver's 23 at 68; the objects' 29 at 74; the proof; the libc++ one's 18 reads, 1242 s, 1903 MB,
every item count identical to the 1.2.16 run; the C++ one's 154 checks, 6460 s, 1858 MB, no sleep in
its window. NOTHING IS CLAIMED FROM THOSE NUMBERS: the reader's 44 s and 393 MB at 1.2.16 were the
FIRST run after the reader version moved to 72, so they paid the initialization phase over a fresh
store where today's 6 s reads a warm one -- cold against warm, the trap 0.89 recorded -- and the C++
gate's 6850 -> 6460 s and 1760 -> 1858 MB are inside this machine's up-to-a-fifth noise. What the
re-gate says is only what a gate ever says: the engine moved under us (1.2.17's pooled prewarm,
1.2.18's module clauses reaching the knowledge base, both STORE changes, which is why the cheap
store-using gates are the ones that mattered here) and nothing of ours moved with it.
NOT DONE: `std::tuple_cat'. It is the one function of the surface that does not compile, and the
stop is named: `__tuple_cat<tuple<_Types...>, __tuple_indices<_I0...>, __tuple_indices<_J0...> >()
(...)' builds a TEMPORARY of a three-pack class template and calls its `operator()', a member
TEMPLATE with a trailing `_Tuples...', and the recursive overload of that operator is neither
matched by arity nor by its arguments (`member_refused(..., operator(()), argument_mismatch)' then
`arity_mismatch'), so the call stays raw and the lowering meets a call whose callee is a compound
literal. The return-type chain BEHIND it is right -- the trace shows
`__tuple_cat_return_impl.tuple.int_int_double_char' and `tuple_size.tuple.int_int_double_char' ->
`integral_constant.size_t.4' -- and so is `__tuple_cat_select_element_wise', whose pack (3) above
fixed; what is left is the member template on an instance of a class template over three packs, and
it is a step of its own. Also not done, both found on the way and older than this step: a QUALIFIED
DATA MEMBER inside a derived class, `L0::v = a;', is `undeclared('L0.v')' (a qualified METHOD call
has gone through the base hops since 0.73; the data member has no road), and an OUT-OF-CLASS
definition of a static ARRAY member, `const bool Holder::flags[3] = {...};', is
`member_of_class(scoped(['Holder'], flags))' -- the in-class initializer is what (5) defines, and
the out-of-class form is another.

**M6's fifty-eighth step (0.91): `std::tuple_cat`, `<array>` whole, and `<algorithm>` read whole.** 0.90's one
not-done item of the tuple module, and it took three rules, each reproduced on its own before it was
fixed. (1) AN RVALUE PREFERS `T &&' ([over.ics.ref], [over.ics.rank]/3.2.3) WHERE A TEMPLATE'S
CANDIDATE IS JUDGED: `cpp_params_accept' unrefs BOTH sides (`cpp_unref_all'), so `tuple<_Tp...> &',
`const tuple<_Tp...> &' and `tuple<_Tp...> &&' -- the four overloads libc++ writes `std::get' as --
were ONE candidate to it, all held with no conversions, and the tie fell to the first declared. So
`std::get<0>(std::forward<_Tuple0>(__t0))' answered `int &' where C++ answers `int &&',
`forward_as_tuple' deduced `tuple<int &, int &>', and `__tuple_cat''s recursive `operator()', whose
parameter is the class's own `tuple<int &&, int &&>', rightly refused it -- the `argument_mismatch'
0.90 named. The scoring road has had the rule since 0.44 (`cpp_category_mismatch' in `cpp_arg_fit_');
this is that rule in the template road, as an exclusion (`cpp_ref_binds_not': an rvalue never binds a
non-const `T &') and as a RANK (`cpp_ref_rank': the worse binding costs one conversion, which the
road already orders by, 0.45's fewest-conversions rule). The `const' of `const T &' sits on the
REFERENT's qualifiers and not the reference's own, which is why the first writing of the rank charged
nothing and the tie stood unchanged. (2) A PACK EXPANSION IS A DEPENDENT TYPE WHEREVER IT SITS
(`ccl_dependent_type'): it has no meaning outside a template, so a type carrying one cannot be
deduced at READ time -- libc++ declares `tuple_cat' over `__tuple_cat_return_t<_Tuples...>', an ALIAS
with no `scoped/2' and no free name, which the reader therefore called settled. (3) AND A CALL OF A
FUNCTION TEMPLATE'S NAME IS NOT THE READER'S `auto' TO DEDUCE (`ccl_auto_by_overload' over
`'$ccl_ftmpls''): the symbol table holds ONE entry per name and the reader cannot choose an overload,
which is the desugaring's work -- libc++ declares `inline tuple<> tuple_cat()' beside the variadic
template, so `auto c = std::tuple_cat(a, b)' took the NULLARY one's `tuple<>' whatever its arguments.
THE MEASUREMENT THAT LOCATED IT, and it is the cheapest instrument in this file: the SAME call with
its result type WRITTEN OUT compiled and ran (`std::tuple<int, int, double, char> c = std::tuple_cat(
...)'), which says in one line that the call, the recursion and `__tuple_cat_select_element_wise' are
all right and only the `auto' is wrong -- where the trace of the whole build was 6370 lines, of which
1073 were `deduction_failed' refusals from the specialization ordering that are all CAUGHT and mean
nothing. A trace prints a refusal whether or not it escapes, so a refusal in a log is not a cause.
AND THE MIDDLE OF IT WAS MY OWN, worth more than the fix: rule (1) was first written as
`\+ cpp_lvalue(A)' -- "not an lvalue, therefore an rvalue". `cpp_lvalue' is a PARTIAL list (`id',
`member', `arrow', `deref', `index', a call returning `ref'), and every temporary this compiler
builds is a `stmt_expr' outside it, so genuine lvalues were refused from binding `T &' and
`stdtuple', `stdcout' and `stdmap' all fell -- 0.68's lesson exactly, a change to one overload rule
being worth no more than the gate it passes. The rule is a WHITELIST now (`cpp_xvalue_call': only a
call whose DECLARED result is an rvalue reference, which is what `std::forward' and `std::move' are
and all the shape needs), and those three pass again. Reader version 73, lowering version 36.
Gated by `test/cpp/run/refrank.cpp' (the three reference kinds, in BOTH declaration orders, so the
answer is the rule and not the order) and an extended `test/cpp/run/stdtuple.cpp' (`tuple_cat' over
two tuples and three, and once with the result type written out), clang++'s lines.
NOT DONE: a non-const `T &' still accepts a CONST LVALUE, which C++ forbids -- the other half of
[over.ics.ref], left out on purpose since it was part of what broke the three fixtures and
`tuple_cat' does not need it; `refrank.cpp' covers what holds and this is named rather than hidden.
AND `<array>`, WHOLE, in the same step, which cost two rules that both reach further than the module.
(4) A PLAIN POINTER A LIBRARY CLASS'S MEMBER ANSWERS IS A BORROW OF THE OBJECT (`ck_borrows_from''s
library clause, `ck_borrow_of'): `std::array''s iterators ARE raw pointers, where a vector's are a
`__wrap_iter' class and opaque to the check since 0.79 (`ck_carries_'), so the range-for's own
`auto __e = a.end()' was a LOOSE pointer and the owner's rule refused it at the scope's end --
`plain pointer not consumed'. The library's discipline is its own (0.45), and what its member hands
back points INTO the object, which is what a borrow says: modelled so, the lifetime rules still hold
(it dangles when the object goes) rather than the pointer being merely exempted. (5) BRACE ELISION
([dcl.init.aggr]/15, and C's own rule): a struct member that is an ARRAY, given an item that is no
braced list of its own, takes as many of the items that FOLLOW as it has elements -- libc++ writes
`std::array<_Tp, _Size>' as the aggregate `struct { _Tp __elems_[_Size]; }', ONE member, so every
`std::array<int, 4> a = {1, 2, 3, 4}' is an elision. It is in the LOWERING's initializer walk
(`ir_init_items') and in the desugaring's `cpp_aggregate_inits' alike, and the guard at both is that
MORE ITEMS THAN MEMBERS REMAIN, which is what tells it from 0.84's array member taken from an array
VALUE (`S s = {arr}': one item, one member, and its bytes are meant). It fixes the C side too:
`struct S { int a[4]; } s = {1, 2, 3, 4};'. AND THE ARRAY OF STRINGS WAS NOT A SECOND DEFECT: it
stopped at `no_constructor(basic_string_view..., 1)' before the elision and simply fell out with it
-- one defect seen twice, which is worth saying rather than counting as two. Gated by
`test/cpp/run/stdarray.cpp': `size'/`max_size'/`empty', `[]', `at', `front'/`back', `data', the
range-for and an explicit iterator loop, a copy, all six comparisons, `fill', `swap', the TUPLE
PROTOCOL over an array (`std::get', `tuple_size', a structured binding, through 0.90's own rule),
elements that construct and destroy (`std::array<std::string, 2>', assigned into), and `= {}'.
AND `<algorithm>` READ WHOLE, which was three READER forms and not one of them the desugaring's.
`std::sort' was `undeclared(sort)' -- and nothing pointed at the header, since A PARTIAL READ IS
SILENT (0.44) and the summary simply held no `sort'. The census loop named it in three turns:
(6) `if constexpr' TAKES AN INIT-STATEMENT ([stmt.if]; the init-statement is always evaluated, so it
stays outside the branch that may be discarded): 0.42 gave `if constexpr' its own node and 0.43 gave
`if' its init-statement, the two were never joined, and the clause CUTS on `constexpr' so nothing
else could match -- libc++'s algorithm dispatch is written `if constexpr (using _SpecialAlg =
__specialized_algorithm<...>; _SpecialAlg::__has_algorithm)' and the read died at line 6136 of
14177. (7) A LAMBDA'S INIT-CAPTURE, C++14's `[n = e]' and `[&n = e]' (`cap(init, N, E)'), which the
reader never had: the closure's member is named by the capture and initialized by an expression of
the enclosing scope, naming nothing of that name -- libc++'s radix sort writes
`[__map = std::move(__map)](const auto &__x)'. (8) A LABEL'S BODY MAY BE A DECLARATION, which is a
statement in C++ ([stmt.label]) and in C23 (`ccl_label_body' falls to `ccl_block_item'), for
`case 2: __destruct_n __d(0);'. `<algorithm>` goes 375 -> 522 items and reads WHOLE. Reader version
74. NOT DONE: `<algorithm>`'s desugaring stops at
`no_member_type('_IterOps._ClassicAlgPolicy', '__iter_move')' -- a STATIC MEMBER FUNCTION TEMPLATE of
two SFINAE-guarded overloads, asked for as a TYPE where `_Ops::__iter_move(__first)' means a call --
and that build peaks at 2592 MB against the 2800 cap, the heaviest header met so far and a thin
margin.
WHAT WAS RUN, AND WHAT WAS NOT: the owner asked for no gates in this step, so NOTHING HERE HAS A
GREEN LINE. Sixteen fixtures were run one at a time and pass -- `refrank', `stdtuple', `stdarray',
`stdmap', `stdcout', `stduniqueptr', `stdmemory', `stdoptional', `counter', `bag', `convref',
`basecast', `packcall', `arraybound', `cxx20', `cxx23' -- chosen as the ones this step's rules most
expose: the overload roads, `auto' over a library call (`ccl_auto_by_overload' fires on every one),
and the `if constexpr' and label forms. The seven gates have not been run since 0.90, and the step
is committed on that footing and no other.

**M6's fifty-ninth step (0.92): `<algorithm>`, and the fifteen rules between its text and its
answers.** 0.91 read `<algorithm>` whole and stopped in the DESUGARING at
`no_member_type('_IterOps._ClassicAlgPolicy', '__iter_move')`. THE FORMS, each named and each cut
to a file of ten to twenty lines that failed in ONE SECOND before it was fixed:
(1) A MEMBER FUNCTION TEMPLATE'S NAME IS A TEMPLATE AND NO TYPE, 0.45's rule for a free one one
scope deeper: libc++ writes `value_type __t(_Ops::__iter_move(__first));' (push_heap, rotate,
sort), which read as a DECLARATION of a function `__t' taking a parameter of type
`_Ops::__iter_move' -- the vexing parse C++ resolves by knowing what the member is. The class-body
scan that notes member templates ahead (`ccl_member_templates_ahead', 0.81) says WHICH KIND each
is now (`ccl_scan_did' answers `N-type' or `N-fn', `ccl_note_mt'), and a function's name joins
`'$ccl_fn_templates'', which `ccl_qname_typish' excludes. AND THE GUARD THE CENSUS EARNED: a
CONSTRUCTOR template's (or a destructor's) declarator-id is the CLASS's own name, so noting it as a
function template made `pair<_T1, _T2>' no type at all and `<vector>' went PARTIAL at pair's
deduction guide -- silent (0.44), and named in one line by `sh test/census.sh'
(`PARTIAL, 210 items; stopped at line 3219').
(2) A CALL'S EXPLICIT TEMPLATE ARGUMENTS ARE TEMPLATE ARGUMENTS, NOT TYPES: libc++'s sort writes
`std::__introsort<_AlgPolicy, _Comp &, _Iter, __use_branchless_sort<_Comp, _Iter> >(...)', whose
last argument is a VARIABLE TEMPLATE's id -- typed as a class it refused `instance_without_body'.
0.63 evaluates an explicit argument where it BINDS (`cpp_bind_explicit'); `cpp_types' was the
pre-pass that mangled it first, and `cpp_call_targs' diverts only the two shapes `cpp_type' gets
wrong (a variable template's id and a concept-id), so nothing that types today types differently.
(3) A FUNCTION TEMPLATE'S INSTANCE THE SHIPPED LIBRARY DEFINES takes its ITANIUM SYMBOL -- 0.61's
and 0.73's named not-done item. libc++ declares `template <class _Comp, class _RandomAccessIterator>
void __sort(_RandomAccessIterator, _RandomAccessIterator, _Comp);' with NO BODY ANYWHERE, compiles
the instances into libc++.dylib and lists them `extern template ... __sort<__less<int>&, int*>' --
which every `std::sort' of an arithmetic type calls. A function TEMPLATE's symbol differs from a
plain function's in three places, all in `cpp_ita_fn_instance': the nested name carries the
TEMPLATE-ID (`_ZN St3__1 6__sort I <args> E E', the template-PREFIX a substitution candidate and
the function's own template-args never one), the bare-function-type that follows a template-id
begins with the RETURN TYPE, and a parameter written as one of the template's own parameters is
`T_' for the first and `T0_' for the second (decimal, where a substitution is base 36), each a
candidate of its own. Measured against the shipped library: `_ZNSt3__16__sortIRNS_6__lessIiiEEPiEEvT0_S5_T_',
character for character.
(4) A PARTIAL SPECIALIZATION'S ARGUMENT LIST IS FILLED FROM THE PRIMARY'S DEFAULTS
([temp.spec.partial]; `cpp_spec_pattern'): libc++ writes `template <class _Tp, class _Up, class = void>
inline const bool __is_trivially_equality_comparable_impl = false;' and specializes it `<_Tp, _Tp>'
-- TWO arguments where the primary takes three -- so the pattern's length matched nothing.
(5) `__is_trivially_equality_comparable' IS ANSWERED (`cpp_trait_of'): `a == b' is `memcmp(&a, &b,
sizeof(T))' for the integral types and pointers, never a float (0.0 == -0.0 with different bits),
an enum (a user may write ==) or a class (padding). With (4) and (5) false, `std::find' took
libc++'s overload guarded by the trait's NEGATION, whose body calls `__find' again: a STACK
OVERFLOW on `std::find(v.begin(), v.end(), 5)'.
(6) AND NO VECTOR EXTENSIONS, the third question of the shape 0.50 asked of exceptions and 0.86 of
RTTI. libc++ vectorizes its algorithms behind `_LIBCPP_HAS_ALGORITHM_VECTOR_UTILS &&
!defined(__OPTIMIZE_SIZE__)', and the first half is on because it asks whether the compiler is
clang-based -- which this one answers yes to, its predefined table being clang's (0.87's hazard).
`__find_vectorized' is built on `__attribute__((__vector_size__(N)))' types, GENERIC LAMBDAS and
the vector builtins. `__OPTIMIZE_SIZE__' is the library's own switch for it and is read in EXACTLY
TWO PLACES in all of libc++, both this one, so predefining it compiles the scalar algorithms the
library ships for -Oz and changes nothing else. (`__builtin_reduce_and' and `__builtin_reduce_or'
live only behind that guard and are still unanswered: reachable again if it ever changes.)
(7) A GENERIC LAMBDA IS A CLOSURE WHOSE `operator()' IS A MEMBER TEMPLATE
([expr.prim.lambda.closure]/3) -- refused by name since 0.42, and what libc++'s `__find_generic' is,
`[&]<class _ValT>(_ValT&& __val) -> bool { return __val == __value; }'. The template's parameters
are the lambda's own (`tparams(Ps)' among the captures) then one INVENTED per `auto' parameter
(`cpp_auto_params', 0.42's rule for an abbreviated function template), and the result type is
deduced at the CALL. The closure's member-template road, its instance's name (`op.call') and the
fallback from `cpp_method' to `cpp_member_template_call' were all there from 0.44, so the rule is
four lines on machinery eleven steps old.
(8) `wchar_t', `char16_t' AND `char32_t' ARE ARITHMETIC TYPES with sizes, ranks, signedness and LLVM
types (`ccl_is_integer', `ccl_basic_size', `ccl_int_rank', `ir_base'; the mangler knew them
already): LP64 makes wchar_t four bytes and signed, char16_t two and unsigned, char32_t four and
unsigned -- and `sizeof(int) == sizeof(wchar_t)' is why libc++'s `__find' of an INT goes through
`__constexpr_wmemchr'.
(9) THE WIDE MEMORY BUILTINS are the C library's functions, DECLARED here when no header did as the
math builtins have been since 0.81: `__builtin_wmemchr', `__builtin_wmemcmp', `__builtin_wcslen'.
(10) `__builtin_assume_dereferenceable' IS AN ASSUMPTION and nothing at run time, beside
`__builtin_assume' and `__builtin_prefetch': libc++'s `__assume_valid_range' calls it on the way
into EVERY range algorithm over a vector's iterators, so it would have failed most of the module's
fixtures one at a time.
(11) A NULL POINTER CONSTANT CONVERTS TO ANY POINTER ([conv.ptr]/1), which only `nullptr_t' knew
(`cpp_null_to_pointer', asked at the three roads that judge an argument: the template acceptance,
the scoring and the arity-only last resort): libc++'s stable_partition writes `pair<value_type *,
ptrdiff_t> __p(0, 0);' and the pair's `(const _T1 &, const _T2 &)' constructor was refused for the
literal 0, leaving no constructor of arity two. AND ACCEPTING IS NOT CONVERTING: bound to the
`const _T1 &' the literal materialized an INT temporary whose ADDRESS went out as the pointer, so
the fixture printed 4 where C++ prints 5 -- a WRONG ANSWER, not a refusal -- and the conversion
goes in at `cpp_ref_args_', the door the class conversions already use.
(12) A CONDITIONAL OVER TWO LVALUES IS AN LVALUE ([expr.cond]/4), so its ADDRESS is the phi of the
arms' where the value form phis the values (`ir_lvalue_form(cond)', `ir_lval(cond)'): `std::min' is
`return __b < __a ? __b : __a;' in a `const _Tp &'-returning function, and as a prvalue
`ir_ref_of' materialized a temporary, stored the STRUCT into it and returned that dead temporary's
address -- `std::min(a, b).c_str()' read its bytes.
(13) A DELETED MEMBER TEMPLATE IS DROPPED as a deleted plain member has been since 0.44
(`cpp_member_body' through the `template' wrapper): libc++ writes `unique_ptr(pointer,
__libcpp_remove_reference_t<deleter_type> &&) = delete' under `is_reference<_Deleter>' to steer
construction to the deleter-by-lvalue overload, and KEPT it won overload resolution and had no
body to emit.
(14) A PARAMETER IS RESOLVED IN ITS CLASS ON THE TEMPLATE ROAD -- 0.66's rule in the one place that
never took it, as 0.70 found it missing from `cpp_args_no_clash': `cpp_params_accept' judged
`const deleter_type &' with the INFERENCE, which knows typedefs and tags and no class scope, so
`deleter_type' (unique_ptr's own typedef of `__destruct_n &') stayed opaque, the reference was
never seen, and the class test -- which must not unref (0.51) -- met one and refused
`argument_mismatch'.
(15) A FREE OPERATOR SERVES A PLAIN STRUCT (`cpp_op_operand'): the road required a registered CLASS
on one side and a struct of plain members is never promoted to one (0.84 promotes only a struct
holding a class), so a program's own `bool operator<(const S &, const S &)' was never found
anywhere -- inside a template or out -- and `x < y' stayed the raw `bin(<, ...)' the lowering
cannot take.
THE THREE THAT HID EACH OTHER, worth more than any of them: the `unique_ptr' failure was (13),
(14) and 0.66's rule stacked, and each was invisible until the one in front of it MOVED -- the
deleted constructor won while it existed, and only once dropped did the refusal name the candidate
whose parameter never resolved. The trace named each in turn (`ctor_candidate', `ctor_no',
`member_refused', 0.79's rule 9); guessing named none of them. AND A REDUCTION OF (14) THAT PUT THE
TYPEDEF AT FILE SCOPE PASSED, because the inference can resolve one there and libc++'s is
class-scope: a probe that passes can mean the PROBE is wrong, and the plain-constructor probe of
the same rule passed for the same reason -- the plain road works and only the template road was
broken.
Reader version 76 (75 for the member-template kind, 76 for `__OPTIMIZE_SIZE__', every summary
rewritten); lowering version 38.
WHAT RUNS: `<algorithm>`'s surface as TEN fixtures --
`test/cpp/run/stdalgorithm.cpp' (the predicates: all_of, any_of, none_of, for_each, count,
count_if), `stdalgorithm2.cpp' (the searches: find, find_if, find_if_not, search, adjacent_find,
find_end, find_first_of), `stdalgorithm3.cpp' (equal, mismatch, lexicographical_compare,
min_element, max_element, minmax_element, min, max, minmax, clamp), `stdalgorithm4.cpp' (copy,
copy_n, copy_if, copy_backward, fill, fill_n, transform unary and binary, generate),
`stdalgorithm5.cpp' (remove, remove_if, replace, replace_if, swap_ranges, reverse, reverse_copy,
rotate, unique), `stdalgorithm6.cpp' (the partitions and the sorts), `stdalgorithm7.cpp' (the
binary searches and the merges), `stdalgorithm9.cpp'
(the heap and the permutations) and `stdalgorithmstr.cpp' (ALL the `std::string' coverage), each
matching clang++ line for line; beside them `nullconst.cpp', `condlvalue.cpp' and `refparam.cpp',
each the shape of (11), (12) and (14) on the program's own classes.
WHY TEN AND NOT ONE, AND THE MODEL THAT WAS WRONG: the surface written as one fixture was still
building at TWENTY-SEVEN MINUTES and was killed. I split it by the NUMBER OF ALGORITHMS, inferring
a superlinear cost from three points (5 algorithms 25-45 s, 12 with strings 263 s, 22 with strings
>1600 s), and the split worked -- 33 s for six algorithms. THE MODEL WAS STILL WRONG, and one
bisect said so: eleven probes identical but for one line, with a BASELINE that calls no algorithm
at all (28 s, which is what including `<algorithm>' and `<vector>' costs), gave
`min_element' 43 s, `max_element' 30, `minmax_element' 28, `min' 29, `max' 28, `minmax' 27,
`clamp' 28 -- SEVEN AT THE BASELINE, free -- against `equal', `mismatch' and
`lexicographical_compare' at over 180 s each. The cost is not the count: it is the TWO-RANGE
family, and `stdalgorithm3' was slow because it happens to hold all three of them.
NOT DONE, AND MEASURED HONESTLY: those three are still ~250 s each against the 28 s baseline, and I
DID NOT FIX THEM. The trace shows what looks like the cause -- an `enable_if' instance keyed by an
UNFOLDED conjunction spelled letter by letter,
`enable_if.binbinbinbinbinbooltruebooltruebooltruenotscopedtmplisvolatilebaseintvalue...', from
libc++'s `__enable_if_t<... && !is_volatile<_Tp>::value && ..., int>', with 1422 candidates and 637
refusals and NO instance asked twice (so breadth, never a loop) -- but a bad thing in a trace is
not a demonstration that it is THE COST. Two fixes failed: folding a static constant inside
`cpp_const_reduce' fired on every `scoped' subterm of every constant evaluation, dragged
`cpp_scope_class' into instantiating the detection idiom's `__test' and broke EVERY probe including
the baseline (a file calling no algorithm cannot be broken by an algorithm fix -- that is the
edit, immediately); and the same fold at `cpp_targ_value', the right place, never fires on
libc++'s expression -- measured against the library with ONLY that clause stubbed off, 255 s
without it and 239 s with, which is this machine's noise. Both were REVERTED. Two reductions of the
shape fold correctly in one second, so the mechanism is not reproduced and that is why it is not
fixed. THE SET OPERATIONS ARE NOT COMMITTED AT ALL: `stdalgorithm8.cpp' (set_union,
set_intersection, set_difference, set_symmetric_difference) has NEVER been seen to pass -- killed
at 16:40 pinned at 499 MB, and flat memory over that long is the shape of something other than
ordinary work in an engine with no heap collector. They are two-range algorithms, so the family
above is the likely reason and they would probably pass given twenty minutes; but the gate globs
`test/cpp/run/*.cpp', so a fixture committed unverified is a fixture that may hang the gate for
the owner, and it waits outside until it is measured.
WHAT WAS RUN, AND WHAT WAS NOT: the owner asked for no gates, so NOTHING HERE HAS A GREEN LINE.
The thirteen fixtures above were run one at a time and pass (`stdalgorithm' 39 s/350 MB,
`stdalgorithm2' 44/427, `stdalgorithm4' 61/320, `stdalgorithm5' 88/329, `stdalgorithm6' 431/1245,
`stdalgorithm7' 119/564, `stdalgorithm9' 40/540, `stdalgorithmstr' 171/676, `nullconst',
`condlvalue' and `refparam' 1-2 s each); `stdalgorithm3' passes at about 1670 s and `stdalgorithm8'
is unmeasured past 16 minutes, which is the open item above. The seven gates have not run since
0.90, and the step is committed on that footing and no other.

**M6's sixtieth step (0.93): C17 AND C23 WHOLE, C++20, C++23 AND C++26 TO THEIR ENDS, AND THE
LINUX PORT GREEN.** The owner asked for the levels finished, and this step is the not-done lists of
every earlier one, closed where a form can be closed and named where it cannot. Fifty-odd forms,
each gated; the ones that taught something are told here.
THE C SIDE. (1) `_Generic' IS CHOSEN AT THE READ (C11, missing since M1): the controlling
expression's type is asked of the symbol table the parser keeps -- the macros' door -- decayed,
its top-level qualifiers dropped (C17's lvalue conversion, DR 481), and the association whose
CANONICAL type is the same replaces the form (`ccl_type_canon': typedefs resolved through pointers,
arrays and functions, `unsigned' and `unsigned int' one type, the qualifiers BELOW the top kept, so
`char *' and `const char *' are two); `default' otherwise, and a controlling expression the table
cannot type keeps `generic/2', which the lowering refuses. It is a PRIMARY, not a unary, since
`_Generic(x, ...)(x)' is how <stdbit.h>'s type-generic functions call the one chosen. (2) `_BitInt(N)'
IS LLVM'S `iN' EXACTLY (`ir_base'), sized as the psABI has it (the smallest integer type up to 64
bits, whole eightbytes aligned 8 past that), ranked below the standard type of its width and above
every narrower one (`ccl_bitint_rank', a half-rank), and NEVER PROMOTED (6.3.1.1/2, the guard in
`ccl_promote'); the `wb' and `uwb' suffixes give `wb(N)' and `uwb(N)', a _BitInt of the width the
value needs plus the sign, in BOTH lexers (`ccl_int_kind/4', `x->sfx' 4 and 5). (3) THE OVERFLOW
BUILTINS (`__builtin_add_overflow' and kin, what <stdckdint.h> is) compute EXACTLY in i128 over the
operands widened by their own signedness, store the result truncated, and answer whether widening it
again gives the exact value back -- any integer types on either side, a `_BitInt(128)' included.
(4) `__builtin_unreachable()' is LLVM's terminator; `unreachable()' and `nullptr_t' (`typeof(nullptr)')
come from <stddef.h> AT THE LEVEL ONLY, so THE C STORE IS KEYED BY THE LEVEL where it is not 17
(`ccl_kb_key': `c(V, 23)'), since a header's macros and items are served by that key and a C17 read
must not see them. (5) A VARIABLE LENGTH ARRAY is allocated WHERE IT IS DECLARED, in the body, `alloca
T, i64 n' -- the entry block's allocas are fixed -- and `sizeof' of one is its bound's value times the
element at run time, asked BEFORE the layout, whose answer for an unsized array is honestly ZERO (a
flexible member's); the bound is read where sizeof is, not where the array was declared (named). (6)
`_Thread_local' and `thread_local' are a QUALIFIER, not the storage word: `static _Thread_local' has
both and the storage slot holds one -- and the generic storage clause took the keyword before the new
clause saw it, so the new clause sits AHEAD of it and the words are out of `ccl_storage'; the lowering
spells `thread_local global' for a global and a static local (`ir_tls', the qualifier on the innermost
base). (7) THE PREFIXED LITERALS, both lexers (`ccl_lit_prefix', `ccl_lx_string_k'): `u8"..."' is a
byte string as `"..."' is (char8_t and char are one byte here), `L' `u' `U' give `wstr', `u16str',
`u32str' whose BODY IS THE PLAIN STRING'S, UTF-8 bytes, which the LOWERING DECODES into the wide
elements (`ir_wstring', `ir_utf8_decode') -- so a universal character name in a wide string, which the
DCG had already turned into UTF-8 bytes, comes out as its one code point, and the two lexers stay byte
for byte the same. The check counts them static, as it counts `str' (a wide literal bound to a plain
pointer was refused `unconsumed' until it did). (8) `__VA_OPT__' (C23, C++20: `pp_va_group'), `#embed'
with `limit', `prefix', `suffix' and `if_empty' (the resource's bytes where the directive stood, a
quoted name beside the file and an angled one on the path, a code past 255 spelled back into its
UTF-8 bytes), `__has_embed' (found 1, empty 2, nowhere 0), `__has_c_attribute' answering the standard
attributes' dates and the `__x__' spellings (C only; `__has_cpp_attribute' keeps its 0, the plainest
path through libc++), AND THE FILE'S OWN `#error' IS A DIAGNOSTIC -- it was listed in `'$pp_errors''
and nobody read the list, so a program's #error compiled to `cicili: ok' -- with `#warning' printed
after the read in clang's shape (`dr_pp_warnings'; a header's stay what they were). (9) `_Alignof',
`alignof' in C23, `_Alignas' read and dropped as C23's alignas is; `typeof_unqual' wraps its operand
`unqual(X)' and the resolution strips the top-level qualifiers; the decimal floating types are read,
sized and refused by name (LLVM has no arithmetic for them). (10) AN UNBOUNDED ARRAY TAKES ITS BOUND
FROM ITS INITIALIZER AT THE READ (`ccl_sized_by_init', a designator `[i] =' moving the position): the
lowering sized the emitted type this way and the table kept `none', so a GLOBAL's `sizeof' was 0 while
a local's was right -- found by the first `#embed' fixture. (11) THE FREESTANDING <limits.h>: glibc
defines none of the limits itself under a GNU-shaped compiler and asks the compiler's header for them
(`_GCC_LIMITS_H_'), so on Linux `INT_MAX' was simply undefined; the values are the predefined macros'
and glibc's own file follows through `#include_next'; <stdckdint.h> and <stdbit.h> beside it, the
latter's suffixed functions over the bit builtins and its generic forms over `_Generic'.
THE C++ SIDE. (12) THE DEFAULTED COMPARISONS ([class.compare.default]): `operator==' and `operator<=>'
written `= default' are SYNTHESIZED memberwise at `cpp_norm_members_' -- the members in order, the
three-way one lexicographic in an int where C++ has std::strong_ordering (0.42's scalar `<=>' is an
int and <compare>'s classes are not modelled: a written result type is taken as int), a defaulted `<=>'
bringing a defaulted `==' where NONE is declared (declared and defaulted, it was synthesized twice:
`invalid redefinition'); a base sub-object and an array member are not compared (named). THE
REWRITTEN CANDIDATES ([over.match.oper]/3.4, `cpp_rewritten_cmp' at `cpp_operator''s last resort):
`a < b' is `(a <=> b) < 0' where the class has `<=>' and no `<', `a != b' is `!(a == b)'. (13) A
CONSTRAINED `auto' IS KEPT as the qualifier `constrained(C, As)' where 0.84 dropped the concept, and
CHECKED where the type is deduced (`cpp_constrained_ok' in `cpp_auto_deduce' and `cpp_auto_bind'):
`Number auto x = e', `const Number auto &r = x', and an abbreviated template's parameter, whose
invented parameter carries it as a `requires' entry -- ONE entry, LAST, conjoined, as the reader
gathers a written head's (`ccl_gather_requires'), and in the READER'S SHAPE, `tmpl(C, [base([],
[typedef(A)])])': written `typedef(A)' bare, `cpp_subst' never bound it and the concept refused
`constraint_unknown' on the free name, which rejected every candidate and left `half(9)' undeclared;
only a concept the PROGRAM declared is carried, a library's being the library's. And
`cpp_constraints_hold' checks EVERY `requires' entry now, where it took the first. (14) `[[assume(e)]];'
is a statement of its own (`assume(L, E)', the check reads the expression, the lowering calls
`llvm.assume'), where every attribute before a statement was dropped. (15) The suffixes `f16', `f32',
`f64', `f128' and `bf16' in both lexers, dropped as `f' is (the native one re-reads the character
after a `b' -- it did not, and read `0.5bf16' as `0.5' then the name `f16': k84 said so in one line).
(16) `static operator()' and `static operator[]' ran as they stood (a static method takes a `this'
and ignores it, 0.36). (17) C++26: PACK INDEXING (`Ts...[0]' a type, `args...[1]' an expression:
`pack_index', substituted once the pack is bound, `cpp_pack_at', the index folded after its own
substitution, out of range and non-constant refused by name), `= delete("why")', THE PLACEHOLDER `_'
(a second `_' in one block is renamed `_$k' at the read and the first keeps the name, as C++ lets a `_'
be named only while there is one), A STRUCTURED BINDING AS A CONDITION (a temporary holds the object,
the names bind into it through 0.79's deferred `bindings' road, and the test is the temporary's --
a class through its operator bool) and as an init-statement (the binding's items spliced into the
block: `ccl_init_items', where a `'$splice'' inside a block built by a rule is spliced by nobody), and
the init-statement clause sits AHEAD of the declaration clause, which read `auto [c2]' as an ARRAY
declarator named nothing; `friend Ts...;' (already `friend(L, [])'); the contract assertions `pre(e)'
and `post(r: e)' read and IGNORED, the standard's own `ignore' evaluation semantic;
`trivially_relocatable_if_eligible' and `replaceable_if_eligible' dropped with `final'; `#embed' in C++.
THE LINUX PORT, GREEN AT LAST (0.87 reached 83 checks). (18) THE PREDEFINED MACROS ARE THE HOST'S:
the table was the reference compiler's on macOS, so `__APPLE__' and `__MACH__' were `any' and Linux
compiled as a Mac over glibc's headers; `ccl_host_os/1' beside `ccl_host_arch/1' in the module
(`@ifdef __APPLE__'), `pp_os/1', the Apple rows under `darwin' (33 of them, `TARGET_OS_*' included)
and `__linux__', `__gnu_linux__', `__unix__', `__ELF__', `__PIE__' under `linux'; `__is_target_os',
`__is_target_vendor' (pc) and `__is_target_environment' (gnu) answer for the host. (19) libc++ is found
under Debian's `/usr/lib/llvm-NN/include/c++/v1' (`ccl_debian_llvm_roots', the newest first) -- without
it `#include <cstdio>' flattened to NOTHING and every C++ fixture was `undeclared(printf)'. (20) The
driver gate's two macOS-shaped checks are the host's (`_main' against `main', `.dylib' against `.so').
THE INSTRUMENTS, three more for the list: a Cicili function is named AFTER it is defined
(`unknown symbol: ccl_lx_string_k' from the transpiler, the wrapper written above the function it
wraps); cocolog's reader refused ONE clause of this step, `append([declaration(...)] , Ifs, B0)', with
the lone message `its clauses would not consult' for the whole library -- bisected by applying each
hunk of the diff alone onto HEAD (a standalone consult of `ccl_ir.pl' fails for its own reasons, so a
per-file consult said `ccl_ir' was broken when it was not: measure against the base); and the reader
gate's `a cached read is the same AST as a fresh one' goes RED when the grammar moves without the
version, which is exactly what it is for. Reader version 77, lowering version 39.
FOUND AND NAMED, NOT DONE: cocolog's integers are 61-bit (the finding in the lexer's own entry), so
`LONG_MAX' and `LONG_MIN' cannot be spelled through this compiler -- `INT_MIN' is in the fixture in
their stead; a VLA's `sizeof' re-reads the bound; a VLA of a VLA; a wide string initializing an ARRAY
(`wchar_t a[] = L"..."'); `_Atomic' objects are plain loads and stores; `_Alignas' on an object is
dropped; `_Complex'; `\\N{...}'; the base sub-object and an array member in a defaulted comparison;
`std::strong_ordering' as a class; coroutines, modules and `consteval' at compile time (the findings
of 0.42 and 0.43 stand); a template's own `auto' parameter constrained by a LIBRARY concept.
THREE MORE, FOUND BY THE GATES AND WORTH THE MOST. (21) A NEW PREDICATE'S NAME IS CHECKED AGAINST THE
DCG'S ARITY TOO: the init-statement's splice helper was named `ccl_init_items/3', and `ccl_init_items//1' -- the
braced initializer's nonterminal -- IS `ccl_init_items/3' once the DCG adds its two arguments; the extra clauses
were reached only on a BACKTRACK out of a braced list, read the token list as an item, and libc++'s variant raised
`Arguments are not sufficiently instantiated' with no line, four minutes into a read that the committed grammar took
whole. It was found in three measurements, none of them a guess: the flattened header read under HEAD's grammar
with the working tree's other files (whole: the grammar's), each hunk of the grammar's diff applied ALONE onto HEAD
and the file read under it, four reads at a time (one hunk raised), and that hunk split in two (the splice lines,
not the new clause); a per-item `catch' in `ccl_externals_' on a scratch copy of the library then named the item.
The helper is `ccl_init_stmt_items' now, and the rule is the one this file already has for C names, applied to
Prolog: a name is looked up before it is given, at its arity AND at the DCG's. (22) 0.92's `cpp_null_to_pointer'
accepted `nullptr' for `void_t<typename U::category> *' by the pointer's SHAPE alone, so the detection idiom's
refusal (no such member type, [temp.deduct]/8) was never raised and the wrong `test' overload held --
`detect2.cpp' had been RED since 0.92, whose gate did not run; the pointee must resolve now
(`cpp_pointee_settles', a refusal there being the candidate's rejection, caught where the candidates are held).
(23) ELEVEN OF 0.92's EXPECTATIONS LACKED THEIR `exit 0' LINE, since they were run one at a time and never
through the gate, which appends the exit status: added. AND THE WATCHDOG BESIDE A GATE MUST FOLLOW THE GATE'S
PROCESS, not the presence of a cocolog process -- the first version here ended at the first second with none,
which is every gap between two fixtures, and a gate ran on unguarded at 5.7 GB beside four bisect reads (0.90's
and 0.91's hole, arrived at from the other side).
AND THE ROAD TO libc++ 18, WHICH THE LINUX GATES OPENED. The C++ gate's first run here failed every fixture over the
standard library, and a snapshot run earlier in the day, which I had read as passing them, had never reached them -- it
stopped at `stdcin' and its FAIL list was a TRUNCATED list, not a pass list (the eighth instrument in the findings: a gate
that ends early reads exactly like a gate that passed the rest, and only the names it printed say which fixtures it ran).
Measured one header at a time with the census on the FLATTENED header under both grammars (`cicili++ -E', then
`test/census.pl' with `COCOLOG_LIBRARY' set to HEAD's library and cocolog called directly, since `test/census.sh' sources
`config.sh', which puts the working tree's library first whatever the caller had), HEAD's grammar and this tree's stopped at
the same line of `<iostream>' (320 of 793 items) and of `<functional>', and the desugaring under HEAD's library -- with a
HOME of its own, so its summaries at reader 76 never overwrote the tree's, the two grammars keying the same files -- refused
`stdvector' at the same place: every one of these is the environment's, libc++ 18's shapes under this compiler's
configuration, and none is this step's. FIVE OF THEM, CLOSED: (24) AN UNNAMED PARAMETER OF AN UNKNOWN TYPE NAME in a C++
parameter list (`ccl_typedef_name' in the `param' scope, cpp only): a lone name before `,' or `)' can only be a type there,
unless it is a declared object -- the vexing parse `T x(a, b);' reads its arguments, and keeps reading them -- and libc++
18's `shared_ptr.h' writes `atomic_load_explicit(const shared_ptr<_Tp> *, memory_order)' with `memory_order' declared only
under `<__atomic/memory_order.h>', which it includes only where `__has_keyword(_Atomic)' or `__has_feature(cxx_atomic)'
answers 1, and this preprocessor answers both 0 (the plainest path), so the read of `<iostream>' stopped 320 items in,
silently, `cout' never reached; (25) A DESTRUCTOR CALLED WITH ITS CLASS'S TEMPLATE ARGUMENTS SPELLED OUT,
`__f_.~__compressed_pair<_Target, _Alloc>()' (`ccl_dtor_targs', the arguments dropped: the destructor called is the
object's own class's whatever the spelling); with the two, `<iostream>' reads WHOLE (793 items) and `<functional>' with it;
(26) A BASE CLAUSE NAMING A BOUND TYPE PARAMETER takes the class the parameter is bound to (`cpp_subst' on `base(Access,
Name)', told from the type form `base(Qualifiers, Specifiers)' by its first argument): libc++ 18 builds every container on
`__compressed_pair_elem<_Tp, _Idx, true> : private _Tp', and the bare atom was left as written, refusing
`base_not_registered('_Tp', ...)'; a plain struct of data members bound there is still not promoted to a class
(`cpp_note_bases' sees the raw names only), named below; (27) A SCOPE'S NAME IS THE CLASS'S OWN TYPEDEF FIRST
([basic.lookup.unqual]; `cpp_path_class'): `numeric_limits' writes `typedef __libcpp_numeric_limits<...> __base; typedef
typename __base::type type;', and a class named `__base' elsewhere in the header, loaded lazily by that name, won the
scope and refused `no_member_type(__base, type)'; (28) THE C++ RUNTIME IS NAMED AT THE LINK ON LINUX (`ccl_link_libs',
`-lc++'): `c++' is g++ there, whose library is libstdc++, and the one undefined symbol was libc++'s
`std::__1::__libcpp_verbose_abort' -- the driver's link diagnostic keeps ld's first line only, which named the function
and not the symbol, so the object was linked by hand. With them `stdvector' builds and runs through `cicili++' (398 s
cold, the flatten of `<vector>' at reader 78 in it), and `test/cpp/run/tpbase.cpp' -- the bound base, a member reached
through it, a destructor spelled with its arguments, on the program's own classes -- prints clang++'s numbers. Reader
version 78, lowering version 40.
SEVEN MORE, EACH REPRODUCED IN A DOZEN LINES BEFORE IT WAS FIXED (the traits first, since `__unwrap_iter' -- the door of
every range algorithm over a vector -- is guarded by `is_copy_constructible' of the iterator, and it held for nothing):
(29) A TYPE ARGUMENT IS A TYPE (`cpp_expr' on `type(T)'): the reader gives a builtin trait's type arguments as
`type(T)', and the generic expression walk took the term apart and read `typename add_const<_Tp>::type' inside it as
an EXPRESSION -- the nested type's NAME as an id -- so libc++ 18's `is_copy_constructible', written
`__is_constructible(_Tp, __add_lvalue_reference_t<typename add_const<_Tp>::type>)' where 21 writes the class form,
compared a name with a type and answered 0 for every pointer and every plain struct; (30) `const T' WITH T A POINTER IS
A CONST POINTER ([dcl.type.cv]; `cpp_merge_quals'): the qualifier was DROPPED, so `add_const<int *>::type' was `int *'
-- neither `int *const' nor `const int *' -- and with an array it goes to the elements; (31) A VALUE'S TOP-LEVEL
QUALIFIERS ARE NO BAR to initializing from it ([dcl.init]; `cpp_same_unqualified' in `cpp_convertible'):
`is_constructible<S, const S &>' of a plain struct was 0, since neither side is a registered class and `const S' is not
the spelling `S'; measured against clang++ on every spelling, in and out of a template, all equal now; (32) THE
IMPLICIT COPY IS NOTED WHEN IT IS EMITTED (0.69's rule in its fifth place, `cpp_implicit_copy_ctor'): the fact was
asserted before the emission, so a walk abandoned by a throw -- a candidate rejected -- left the name with no
definition behind it, and `allocator<Rec>::construct' met `undeclared(Rec.Rec.Rec_rr)' for the program's own struct;
(33) A LAMBDA'S WRITTEN RESULT TYPE IS RESOLVED UNDER ITS PARAMETERS ([expr.prim.lambda]; `cpp_lambda_written_ret'):
libc++ 18's basic_string move constructor initializes `__r_' from an immediately invoked `[](basic_string &__s) ->
decltype(__s.__r_) && { ... }(__str)', and with no parameter in scope the decltype was untyped, the result unknown and
the member `not constructed'; (34) A DEFAULT ARGUMENT MAY BE A BRACED LIST (`ccl_param_default' through
`ccl_initializer'): `_Pred __pred = {}' is every ranges algorithm of libc++ at C++20, and the four C++20 headers of
the libc++ gate stopped there, 665 items in; (35) C++20's DESIGNATED INITIALIZER TAKES THE BRACED FORM, `.__width_{
__get_width(__ctx)}' (libc++ 18's <format>, in the C++20 closure of <set>), and A BRACED LIST ON A SCALAR IS ITS ONE
VALUE, or the type's zero when empty ([dcl.init.list]; `ir_init'), where the lowering asked a scalar for its members
(`initializer(0, int)'). With them `stdaggregate' (a vector of a struct holding a string, on the compressed pair of
libc++ 18) and `stdarray' build and run on Ubuntu. THE INSTRUMENT, once more: every one of these was a build of
minutes cut to a file of ten lines that failed in a second, the trait ones printed beside clang++'s answers, and the
one that was not (the implicit move's lost definition) was found by the trace's `implicit_copy(Rec, move)' with no
`lower(function(Rec.Rec.Rec_rr, ...))' after it -- a definition's absence read off a list that names every one made.
(36) AND THE FLATTENED TEXT SPELLS THE PREFIXED LITERALS AND THE BIT-PRECISE SUFFIXES (`ccl_pp_spell_tok', `pp_spell'):
`cicili++ -E' printed `L"true"' as a code list and `12wb' as `12', which no reader takes -- the census's road only, since
the gate reads the tokens, and exactly the kind of gap a step that adds token kinds leaves in the one instrument that
spells them back; the third census of the C++20 `<set>' stopped on it at `__bool_strings<wchar_t>'.
(37) A BRACED ARGUMENT TO A SCALAR PARAMETER is its one item or the type's zero, at the argument pass and where a
default is filled in (`cpp_scalar_braced'), AND A FUNCTION TEMPLATE'S INSTANCE FILLS ITS DEFAULTS AT THE CALL
(`cpp_fill_defaults' at the two template call sites): `g(1)' of `template <class T> T g(T a, int b = 5)' went out with ONE
argument to a function of two -- garbage where C++ has 6, older than this step and found by the C++20 probe's
`adv(I, S, int p = {})'; the plain road had filled them since 0.63, the template road never had. Gated by
`test/cpp/run/bracedforms.cpp' at C++20 (a braced scalar, `.b{2}', a braced default and argument, a template's default,
the copy-constructibility of a pointer and of a plain struct through the builtin), clang++'s numbers.
AND THE `std::function' ROAD ON libc++ 18, five more, found from a refusal that named the wrong thing:
(38) A MEMBER CLASS TEMPLATE DECLARED AND DEFINED LATER IS REGISTERED AT ITS DECLARATION
(`cpp_register_class_extras', a `template <class _Fp, bool = ...> struct __callable;' among the members), which is how
libc++ 18's `function' declares its `__callable' before the partial specializations that define it.
(39) A BASE'S MEMBER TEMPLATE CALLED BARE WITH EXPLICIT ARGUMENTS is found where C++ finds it ([class.member.lookup]:
the class's own first, then each base's, the signature checked in the class that DECLARES it; `cpp_member_template_of'
in the bare-call clause of `cpp_call'): `__tuple_sfinae_base' declares `__do_test<_Trait>(...)' and every derived
trait calls it bare -- found in the derived class alone, the call fell to the CLASS-template road and refused
`template_without_body(__do_test)', which the static fold caught, leaving the trait's `value' an undefined extern at
the link. `this' goes through the base sub-objects as a qualified call's has since 0.73, null for a static.
(40) A TRAILING RETURN TYPE IS THE RESULT ([dcl.fct]/2; `cpp_trailing_rets' at `cpp_norm_members'): the reader keeps
`-> T' as `trailing(T)' among a member's qualifiers with the result `auto', and NOTHING READ IT -- a member defined
deduced its result from its first return (0.42) and a member DECLARED had none; `static auto __do_test(...) ->
__all<...>;' has no body and its declared result is the whole point, a decltype reads it. AND THE RESULT TYPE IS PART
OF THE SIGNATURE ON THE MEMBER ROAD TOO (`cpp_result_holds' inside `cpp_member_holding''s catch, 0.55's rule for a
free template): `-> __all<__enable_if_t<_Trait<_LArgs, _RArgs>::value, bool>{true}...>' is rejected where a trait is
false, which is the only way the variadic `__do_test(...) -> false_type' beside it is ever chosen. The shape on the
program's own classes in `test/cpp/run/basetmpl.cpp' (a base's member template chosen by its result's SFINAE, `1 0').
A FREE function's trailing type is still dropped by the reader (`ccl_external_rest' keeps only the `const' of the
qualifiers after the parameters), its definition deduced from the first return as before, and a bodyless free
prototype `auto f() -> T;' stays `auto': named, not done.
(41) THE READER (version 80): A TEMPLATE TEMPLATE PARAMETER'S NAME IS A TEMPLATE INSIDE ITS ITEM AND NOWHERE ELSE
(`ccl_note_tt_param', un-noted by `ccl_tparams_leave' through a frame per item, unless the name was a template before),
and A TAG OR A TYPEDEF IS NO CONCEPT (`ccl_concept_name'). With everything above in, `std::function<int(int)>' still
refused `concept_without_body(_Trait)', and the name pointed at `__do_test' -- the ONE place libc++ 18 writes `_Trait'
outside `<variant>'. It was `<variant>': `enum class _Trait' and `template <_Trait _DestructibleTrait, class...
_Types> class __base;', a VALUE parameter of enum type, read as a CONSTRAINED TYPE parameter (0.84's `template
<Concept T>') because `_Trait' had stayed a known template since `__do_test''s head two hundred items earlier; and
the flattened `<functional>' of libc++ 18 pulls `<variant>' in, whose `__variant_detail.__base' then carried a
`requires(tmpl('_Trait', ...))' that every `__base<...>' instantiation met. WHAT FOUND IT: the AST beside the summary
is a file of one clause per item, and `grep "requires(tmpl('_Trait'" <name>-<fold>.ast.pl' named the item in a
second where the breadcrumb (`in(class(__base))') and the header (no `_Trait' but __do_test's) both pointed
elsewhere -- an instrument worth naming: a refusal's NAME is a symptom, and the summary's AST is where a shape can be
looked up by its text. Every summary is rewritten (the version), and the gates ran again after it.
(42) A SCOPED ENUMERATOR AS A TEMPLATE ARGUMENT IS ITS VALUE (`cpp_enum_scope' in `cpp_targ_value', the enum's name the
path's last segment, its enumerators global names): `holder<Trait::two, 5>' was read as a type and keyed by its
spelling, `scopedTraittwo', and the static it fed never folded; libc++'s variant writes `__base<_Trait::
_TriviallyAvailable, _Types...>' so. `test/cpp/run/ttleak.cpp' (the leak's shape, the enumerator argument, clang++'s
numbers).
(43) A MEMBER ALIAS TEMPLATE'S TEMPLATE-ID IS A NON-DEDUCED CONTEXT in a function parameter too (`cpp_match', 0.45's
rule for a file-scope alias): libc++ 18 writes `unique_ptr(pointer, _LValRefType<_Dummy>)' with `_LValRefType' the
class's own alias template over the constructor's defaulted `_Dummy', and read as a class template-id it refused
`deduction_failed' -- no two-argument constructor was left for `__func::__clone''s `unique_ptr<__func, _Dp>
__hold(__a.allocate(1), _Dp(__a, 1))'. AND A FREE NAME UNDER A PACK EXPANSION MAKES A TEMPLATE-ID RAW
(`cpp_free_arg(pack(T))', 0.83's guard one shape wider): `forward_as_tuple' is declared `tuple<_Tp &&...>', and typed
by that raw result the compressed pair's piecewise constructor bound its `_Args1' to `_Tp &&' and `std::forward<_Tp
&&...>' refused `kind_mismatch'. AND A TRACED REFUSAL PRINTS THE BREADCRUMB STACK (`cpp_refuse' over `'$cpp_wstack'',
0.87's eight frames), not the innermost frame: `in(class(__base))' had named the class being LOADED where the
constraint that refused was `<variant>''s, and the stack named the statement, the function, the call and the
signature in one line.
(44) A CALL THROUGH A CAST TO A REFERENCE CALLS THE OPERAND ([expr.static.cast]: the cast names the object, an
lvalue or an xvalue; `cpp_call''s `ccast' clause, never where the cast changes the class): libc++ 18's `__invoke'
writes `static_cast<_Fp &&>(__f)(static_cast<_Args &&>(__args)...)', and the callee reached the lowering as the cast
itself -- every `<algorithm>' fixture over a predicate stopped there, which the C++ gate at reader 80 said first
(`stdalgorithm' through `stdalgorithm3' RED); libc++ 21 writes `std::forward<_Fp>(__f)(...)', a call whose result is a
reference, which 0.55's `cpp_addressable' already took. AND TWO TRAITS libc++ 18 asks by their builtin names,
`__is_volatile' and `__is_abstract' (`cpp_trait_of'; the second is `cpp_not_abstract''s test as a value), measured
against libc++ 18's own headers: of every `__is_*' and `__has_*' builtin they spell, those two were the ones the
desugaring could not answer. AND A TIME CAP THAT KILLS THE SHELL AND NOT THE WORKER IS NO CAP -- 0.46's finding (a
watchdog that kills only the direct child leaves cocolog, its grandchild, running), met again from the probe's side:
`scratchpad/probe.sh' capped its build with a perl `alarm' around `bin/cicili++', the alarm killed that shell, and
cocolog ran on for ten minutes beside the gate; the cap is coreutils' `timeout -s KILL' now, which signals the whole
group it leads.
(45) THE PACKS AN EXPANSION ZIPS ARE THE ONES NAMED OUTSIDE ITS NESTED EXPANSIONS ([temp.variadic]/5: a pattern
expands over the packs it names UNEXPANDED; a `Ts...' inside it is an expansion of its own, expanded whole in every
element, and `sizeof...(Ts)' names no expansion at all; `cpp_names_outside' behind `cpp_pack_names'): libc++ 18's
`__make_tuple_types_flat' writes `__tuple_types<__apply_cv_t<_Tp, __type_pack_element<_Idx, _Types...>>...>', and
zipped over BOTH packs it refused `pack_lengths_differ' where `_Idx' was empty and `_Types' was not -- the
`__make_tuple_types<tuple, 0>' every tuple constructor over an empty pack asks for; with the lengths equal the answer
had been right by coincidence. (46) AN INSTANCE RESOLVED TO ITS STRUCT SPEC IS THE INSTANCE STILL (`cpp_instance_of''s
first clause): the builtin `__remove_cv_t<__libcpp_remove_reference_t<_Tp>>' hands a tuple's instance back as
`struct('tuple.int_r', Ms)', against which the pattern `_Tuple<_Types...>' matched nothing, so the instance was
incomplete and `__apply_quals' a template without a body. (47) A SCOPED NAME WHOSE LAST SEGMENT IS A TEMPLATE-ID,
`C::template ap<T>', IS A MEMBER ALIAS TEMPLATE AND A TYPE (the `atom(N)' guard on `cpp_targ_value''s scoped clause),
where it was looked up as a static member's value and refused `no_member_type'. `test/cpp/run/packzip.cpp' has the
three on the program's own classes, clang++'s numbers. (48) A CONSTRUCTOR TEMPLATE IS A USER-DECLARED CONSTRUCTOR
([class.default.ctor]/1; `cpp_implicit_ctor_needed', `cpp_trivial_default'): it suppresses the implicit default
constructor as a written one does, unless `C() = default' stands beside it. libc++ 18's `__compressed_pair' has ONLY
templates -- `template <bool _Dummy = true, class = __enable_if_t<...>> explicit __compressed_pair() :
_Base1(__value_init_tag()), _Base2(__value_init_tag()) {}' -- and the implicit constructor made beside it took the
SAME NAME (`C.C.0'), was emitted first and constructed neither base: the tree's end node was garbage, `std::map'
walked it and every container fixture on libc++ 18 built and SEGFAULTED (0.93's first Linux gate). (49) A SECOND BASE
WITH STORAGE IS INITIALIZED THROUGH AN ALIAS as the first base has been since 0.82 (`cpp_extra_inits' through
`cpp_alias_base_init'), and NEVER SILENTLY: libc++ names both bases through `using _Base2 = __compressed_pair_elem<_T2,
1>', and a `findall' that merely failed on the second left it unconstructed -- a base with constructors and no default
one, given no initializer, is refused (base_constructor) as the first base is. (50) A CLASS WHOSE IMPLICIT DEFAULT
CONSTRUCTOR IS MADE IS DEFAULT-CONSTRUCTIBLE (`cpp_constructible' asks `cpp_implicit_ctor_needed'): libc++ 18's
`allocator<T> : private __non_trivial_if<...>' has `allocator() = default' over a base with a constructor, so the
implicit one constructs that base and is no trivial default; answered 0, `is_default_constructible<allocator<...>>'
rejected the compressed pair's only default constructor, which is guarded by it. `test/cpp/run/ctortemplate.cpp' is
the shape on the program's own classes (a template constructor initializing two bases through aliases, alone and as
a member), clang++'s numbers; `stdmap', `stdset', `stdtuple', `stdfunction', `stdfunctional' and `stdbind' are the
library's. (51) THE QUALIFICATION CONVERSION ([conv.qual]; `cpp_quals_added' in `cpp_convertible'): `char *' converts
to `const char *', the pointee gaining qualifiers and losing none. libc++ 18's `__unwrap_range' builds
`std::make_pair(__unwrap_iter(__first), __unwrap_iter(__last))' over a string's characters, and
`is_constructible<const char *, char *const>' answered 0, which rejected every two-argument constructor of the pair
(no_constructor(pair, 2)); `test/cpp/run/qualconv.cpp', clang++'s answers. (52) THE MEMBER-POINTER TRAITS ARE ANSWERED
(`__is_member_pointer', `__is_member_function_pointer', `__is_member_object_pointer' in `cpp_trait_of'; a pointer to
member has been a type of its own since 0.86), AND `decltype' OF A CALL THROUGH A POINTER TO MEMBER FUNCTION is the
member's declared result (`cpp_decltype_of', the desugaring having made `(a.*pm)(args)' a call through the function
pointer the member is here): libc++ 18 writes std::invoke's dispatch as six `__invoke' overloads guarded by
`is_member_function_pointer<__decay_t<_Fp>>::value && is_base_of<...>', and with the trait answered 0 -- a
placeholder from 0.88, when no member pointer was lowered -- every one was refused and the generic `__f(__args...)'
held for a pointer to member function, whose body refused decltype_unknown; `test/cpp/run/memptrtraits.cpp', and
`stdbind' runs. (53) A CALL RETURNING A CLASS BY VALUE IS A PRVALUE, an rvalue as an xvalue is ([basic.lval];
`cpp_prvalue_call' beside 0.91's `cpp_xvalue_call', the second certain shape -- a temporary this compiler builds around
such a call included), so `const T &' binding one costs the conversion that lets `T &&' win, AND A NON-CONST LVALUE
PREFERS THE BINDING WITHOUT THE `const' ([over.ics.rank]/3.2.6; `cpp_ref_rank''s lvalue clause): a forwarding `V &&'
deduced as `S &' beats `const V &' for an lvalue `S'. libc++ 18's `tuple_cat' returns `__tuple_cat<...>()(...)', a
tuple of references BY VALUE, into a tuple of values, and with the prvalue uncharged `tuple(const tuple<_Up...> &)'
tied with `tuple(tuple<_Up...> &&)' and stood first. (54) THE COMMA OPERATOR IS A CONSTANT EXPRESSION (C++11,
[expr.const]; `ccl_const_eval(comma(A, B), V)': the right operand's value, the left a constant or a `(void)' cast of
anything): libc++ writes its conjunction as `_IsSame<__all_dummy<_Preds...>, __all_dummy<((void)_Preds, true)...>>',
and unfolded the second instance was keyed by the term's spelling, so `__all<true, true, true>' was FALSE, every tuple
constructed from another tuple lost its converting constructor template and fell to the impl's bitwise copy, and
`tuple_cat' printed three addresses as an int, a double and a char. `test/cpp/run/commafold.cpp' has (53) and (54) on
the program's own classes, clang++'s numbers; `stdtuple''s `tuple_cat' lines are the library's. (55) NAMED, NOT DONE:
A TYPE'S QUALIFIERS ARE NO PART OF ITS KEY (`cpp_type_key' drops `const' and `volatile'), so `is_const<const int>' and
`is_const<int>', `__tuple_like_ext<const T>' and `__tuple_like_ext<T>' are ONE instance here, and the first made
answers for both -- libc++ 18's `__tuple_like_ext<const _Tp> : __tuple_like_ext<_Tp>' resolved its base to ITSELF
(base_not_registered, the instance in progress) on the road (53) now avoids. Qualified keys were written and measured
on a scratch copy of the library (`const_int', `int_pc' for `int *const'): they uncover the next defect at once
(`__apply_cv' handing `const int &' for a non-const tuple's element), so the road that works by the collision's
coincidence is left as it is and the collision is named here for the step that takes the keys apart. AND THE C++ GATE CAPS EACH FIXTURE'S BUILD (`CPP_FIXTURE_SECS' in `test/cpp.sh', 2400 s unless told
otherwise; `ccl_capped' kills the build's whole process tree past it and records `TIMEOUT after N s' as the fixture's
verdict), since 0.92's finding -- a probe with no time cap is no probe -- held for the gate too: an uncapped
`stdalgorithm7' ran 47 minutes on this box where macOS took 119 s, and the gate behind it waited.
THE `std::function' ROAD ON libc++ 18 IS THROUGH: with (38) to (54) `test/cpp/run/stdfunction.cpp', `stdbind.cpp'
and `stdfunctional.cpp' build and print clang++'s lines on Ubuntu, as do the containers that had built and
segfaulted (`stdmap', `stdset', `stdtuple' with its `tuple_cat', `stdvector', `stdmapstring' and the rest, each named
by the gate below). Every probe of this stretch ran through `scratchpad/probe.sh' (a time cap and a memory cap over
the probe's OWN process group, so a probe may run beside a gate that `watch.sh' -- which sums every cocolog process --
would otherwise kill), a traced build through `scratchpad/trace.sh' (cocolog called directly with `'$cpp_trace'' on,
since `bin/cicili''s filter drops the trace lines), and a fixture through `scratchpad/fx.sh', which removes the
binary before it builds (the finding on a stale binary, 0.89) and compares as the gate compares. THE INSTRUMENT THAT
PAID: the emitted IR read function by function (`cicili++ -S -emit-llvm'), which named `tuple_cat''s defect in four
reads where the trace named none -- a trace prints refusals, and the wrong constructor was CHOSEN without one.
NOT DONE, libc++ 18's: the qualifier-less keys (55); `stdalgorithm2', `stdalgorithm3', `stdalgorithm6' and
`stdalgorithm7' build past the gate's cap here (breadth in the two-range family, 0.92's finding, and libc++ 18's
`__introsort' and `__merge' roads with it: `stdalgorithm7' traced 299 instantiations in 900 s and no instance asked
twice); `stdalgorithm8' (the set operations) stays uncommitted, 0.92's rule.
THE GATES, ON LINUX (Ubuntu 24.04, x86_64, four cores, 16 GB; clang 18, libc++ 18, cocolog 1.8.1, the module
rebuilt as 0.93), on this tree at reader 80 and lowering 40, the C++ summaries warmed OUTSIDE the gates first at all
four levels: the reader's 95 checks GREEN in 4 s; the compile gate's 76 in 4 s; the driver's 25 in 5 s; the objects'
29 in 3 s; the proof; THE LIBC++ GATE GREEN, its 18 reads whole under a fresh HOME in 5513 s (`<vector>` 806 items,
`<string>` 754, `<iostream>` 792, `<map>` 767, `<set>` 767, `<unordered_map>` 751, `<unordered_set>` 833, `<optional>`
602, `<memory>` 533, `<functional>` 831, `<tuple>` 441 at C++17; `<set>` 859, `<map>` 859, `<unordered_map>` 843,
`<unordered_set>` 925 at C++20; `<optional>` 397 and `<string>` 522 at C++23; `<optional>` 397 at C++26 -- libc++ 18's
counts, larger than libc++ 21's on macOS for every header, the cold flatten of each on a box whose two spare cores the
C++ gate shared; the watchdog's 4304 MB peak is the SUM of both gates' processes and no number of this gate's own).
THE C++ GATE, whole and capped per fixture on the library as it stands, IS RUNNING AS THIS IS COMMITTED: its line
follows in the commit that carries its numbers, with every fixture that fails on this box named as the environment's
or as this step's.
Before them, run whole on this box without a cap: 105 of the C++ gate's fixtures passed and `stdalgorithm7' had run
47 minutes when it was killed (the exploratory run, superseded).
AND A FINDING THAT KILLED TWO GATES AT ONCE (2026-09-24): `scratchpad/gate.sh' runs its gate under `watch.sh', which
sums the resident size of EVERY cocolog process and kills them ALL past its cap -- ONE GUARDED RUN AT A TIME, the rule
since 0.46 -- and the reader gate started beside the libc++ gate and the C++ gate at a 3000 MB cap summed their 3.1 GB
and killed both, 1430 s into the libc++ one. A gate beside other runs takes the cap of the SUM (7000 MB here) or waits;
`probe.sh' watches its own process group and is the runner for anything beside a gate.



**`format`, `print`, `println` are global macros** (owner's rule):
`library/ccl_format.pl` is a macro file registered by `ccl_standard_macros/0`
at the start of every unit (found on `$COCOLOG_LIBRARY`, which is also on
the inclusion path). Rust's holes over `ccl_type_of/2`; a struct by its
members. A predicate named `ccl_macro_X` in a macro file is the macro `X`
(`ccl_macro_cname/2`), since `format/2,3` is a builtin; the registry entry
is `macro(CName, Pred, Arity | dcg)`. `ccl_type_of/2` of a statement
expression puts its declarations in scope for its last expression, which
is how `s := format(...)` is a `char *`.
`clone(p)` is the fourth global macro (owner's rule): `ccl_macro_clone/2`
expands to `({ own T *c = malloc(sizeof(T)); *c = *p; c; })`, a fresh owner
for an own parameter so `p` is not consumed; it refuses a non-pointer, a
struct with an own member (`ccl_has_own_member/1`) and a file without
`malloc` declared.

**The knowledge base is the cache.** A file read whole is
`'$ccl_ast'(Path, key(MTime, Version), meta(What, Count, Deps))` plus one
`'$ccl_items:<Path>'(Key, Index, Item)` per top-level item -- one predicate
per file, since the store grows by the written predicate's whole row count
at every writing process (below) -- an include inside
it stored as `ref(Path, How)` and re-linked on load through
`ccl_include_read/2`; `ccl_kb_cached/3` checks `time_file/2`,
`ccl_reader_version/1`, every dep's remembered key, and the item count.
Both predicates are declared dynamic by `ccl_kb_ready/0`. **The store is the user's, `~/.cicili/KB`** (`$CICILI_KB`; owner's rule,
final after two turns: not per working directory): the first call is the
initialization phase, reading the C standard library, the OS's deep headers
and POSIX once, ~40 s; every later call, in any project, is served from the
store as static data, the gates included -- `test/config.sh` exports
`CICILI_KB=$HOME/.cicili/KB` and every gate runs over it. BUMP `ccl_reader_version/1` whenever the
grammar changes, or a partial read from an older grammar stays cached (and
expect that one re-read). `test/reader.sh` runs the checks in one process,
then asks a second process for what the first read.
**The IR joins the store beside the unit (M4):** the driver's `dr_ir/3`
keeps a built file's IR as `'$ccl_ir:<Path>'(Index, Chunk)` -- chunks of
3500 characters, under the clause budget once quoted -- with
`'$ccl_irmeta'(Path, Signature, Count)` the index; the signature folds
(`dr_fold/4`, two folds under 2^31 as a pair: cocolog's arithmetic is not
exact past 2^52) the file's key, the key of every header and macro file
its AST reaches (`dr_unit_deps/2`), `ccl_lowering_version/1` and the
host's arch. A match is served (`cicili -v`: `served F from the store`),
the check having passed when the IR was made; a refused file stores
nothing. BUMP `ccl_lowering_version/1` (in `ccl_ir.pl`) whenever the check
or the lowering changes what it emits; `KB.version` is
`Reader.Lowering`, and a change of either starts the store afresh.

## How the preprocessor is implemented (owner's rule: cocolog, not clang)

`library(ccl_pp)`: `ccl_pp_file(+Path, -Tokens, -Files)` preprocesses a
file standalone -- the target's predefined macros and its own -- into the
reader's tokens, naming every file it pulled (the summary's deps).
`ccl_pp_parse/4` in `ccl_include` runs the grammar over those tokens
inside `ccl_with_file/2`. **Line by line:** `pp_source/2` turns a file
into `line(N, Atom)` terms once per process -- physical lines from
`atomic_list_concat/3`, continuations joined, comments removed, a block
comment's lines counted -- and only a line holding a slash or ending in a
backslash is walked code by code (`pp_clean/3`): a walk in cocolog costs a
microsecond a character and `<stdio.h>`'s closure is 700,000 of them.
`pp_run/3` takes a line: a `#` line is a directive (`pp_directive/6`), a
text line is lexed (`pp_lex_line/3`) and its tokens expanded (`pp_toks/5`,
pulling the next lines when a function-like macro's arguments run on).
A false group is skipped by its `#` lines alone (`pp_skip_group/4`, never
lexing), and a header whose whole text is `#ifndef X … #endif` is
remembered as guarded (`pp_note_guard/2`): its next `#include`, X still
defined, is nothing -- the SDK includes `sys/cdefs.h` ten times. A macro
is `'$pp:<Name>'` = `mac(Params, codes(Cs))`, lexed on its first use
(`pp_macro/3`); `Params` is `obj` or a list with `va(N)` last; the names
are listed in `'$pp_names'` for `pp_reset/0`. Expansion follows the
standard: an argument is expanded before substitution unless `#` or `##`
takes it (`pp_subst/4`), pastes are spelled and re-lexed (`pp_paste_two/3`),
GNU's `, ## __VA_ARGS__` drops the comma (`vamarker`), every token of an
expansion is `h(Token, HideSet)` (`pp_wrap/4`) so a macro never re-expands
inside itself, and carries the invocation's line. `#if` (`pp_eval/1`):
`defined` and the built-ins first (`pp_defined_pass/2`), expansion, the
built-ins again (a macro may expand to one), then every name left is 0,
`true` 1, and the reader's `ccl_cond_expr//1` + `ccl_const_eval/2` decide.
`__has_include` and `__has_include_next` resolve for real
(`ccl_resolve_include/3`); `__has_feature`, `__has_extension`,
`__has_attribute`, `__has_cpp_attribute`, `__has_warning` answer 0 (the
plainest path, the one the reader reads best), `__has_builtin` and
`__is_identifier` 1 (libc++'s other branch is an `#error`),
`__is_target_arch/vendor/os` per host. `#error` drops the rest of THAT
file and is listed in `'$pp_errors'`; `_Pragma("…")` goes with its operand
(`clang -E` made it a `#pragma` line). **The lexer has a mode for it:**
`'$ccl_hash'` = `punct` makes `#` and `##` punctuators and a number a
`tok(num, Spelling, L)` (so `200112L` pastes whole), normalized back to
`int`/`float` at the end (`pp_finish/2`) and inside `#if`; the whole run
lexes in that mode, restored to `line` after. **The predefined macros**
are `pp_predef(any|x86_64|arm64|cpp, Name, Text)` facts at the end of the
file, 580 of them taken once from the reference compiler's `-dM -E` (the
ABI's facts: `__LP64__`, `__SIZEOF_*`, `__*_MAX__`, `__APPLE__`, the arch,
`__cplusplus` …); the host's arch from `uname -m`, cached in `'$pp_arch'`.
The compiler's own headers live in `library/include` (found through
`COCOLOG_LIBRARY`'s directories + `/include`, ahead of the SDK; the SDK
ships `stddef.h` but not `stdarg.h`), and the inclusion path is
`ccl_toolchain_dirs/1`: C++'s library first in C++ and ONE tree only
(two libc++ trees mix their wrappers: the SDK's `ctype.h` under LLVM's
`cctype` defines `_LIBCPP_CTYPE_H` and trips an `#error`), then
`library/include`, `/usr/local/include`, the SDK. Gated by
`test/c/run/pp.c` (a header only the preprocessor can read, its macros'
results as enumerators and a typedef) and `test/reader.pl`'s `k83`.
**The user's file goes through it too** (`ccl_pp_top/3`, called by the
reader's door `ccl_read_file_`): a run in TOP mode (`'$pp_top'`), where a
`#define` or `#undef` is done AND passed on as `tok(pp, Text, L)` (the
parser's `directive/2` item, as before; `pp_pass/4`), an `#include` is
passed on for the parser to resolve as it always did (the unit from the
store, a `.pl` the macro file, one nowhere `missing`) and its header joins
the run's `'$pp_hdrs'` (the last included first), a `#cocolog …
#end` block is one `tok(cocolog, Text, L)` of the raw lines between
(`pp_cocolog_block/5`, re-read from the file: `pp_source` had stripped
the comments), the conditional groups are decided, and every macro --
the file's own, the headers', the predefined -- is expanded; a line that
does not lex whole throws `lexical(N)`, the syntax error it always was.
A run is not re-entrant, so the headers are made ready BEFORE it
(`ccl_pp_prescan/1`: every `#include` line with a literal name goes to
`ccl_header_macros_ready/2` -- the header read through
`ccl_include_read/2`, then its macro table `ccl_header_macros/2`, its
kind kept per process in `'$ccl_hm:<Path>'`). **A header's macros reach
the run by NAME, on first use** (`pp_macro/3` and `pp_defined/1`, the two
doors: this run's `'$pp:<Name>'` first -- `mac(Gen, Params, codes(Cs),
Tokens | none)`, `undef(Gen)`, or `nomac(Gen, Inc)`, a miss remembered
until the next include -- then `pp_outer_macro/3`: the predefined macros,
`pp_predef(Name, any | Arch | cpp, Text)` facts answered by name (first,
since no header redefines one), then the run's headers through
`pp_header_macro/3`, the last included first, by each table's kind;
`pp_reset` bumps the generation `'$pp_gen'`, so an older run's macro is
simply not this run's, no undefine walk, and the 580 predefined ones are
never defined in bulk -- that cost 25 ms a run, and a file names ten).
`<stdio.h>` brings 1200 macros and a file uses a dozen, so no table is
ever parsed whole: in C++ a summary's macros live BESIDE it in
`<name>-<fold>.mac` (`mnames([...])` lines, a hundred names each, then one
`macro(N, Ps, text(A))` line per macro AS WRITTEN; `ccl_mac_lines/3` splits
the file and takes the names off the front, and each line goes into a
FACT, `'$ccl_hml'(Name, Path, raw(Line))` -- `indexed`; an assert is 2 µs
and the lookup by name 3 µs where a global per name cost 25 µs each; a
fact is a store row under `--embed`, which the C++ mode never runs over
-- parsed by `pp_raw_macro/4` when the name is asked); in C the table is
the store's `'$ccl_hmacros:<Path>'(Name, Key, macro(...))` rows, one per
macro under its NAME (`ccl_kb_macro/5`, `store(Key)`), plus a row per
file of the closure under `'$dep'` -- 38 for `<stdio.h>`, over the clause
budget as one term, and the store indexes an atom, not `dep(I)` -- with
`'$ccl_hmeta'(Path, Key, meta(N, ND))` the index (three headers' tables
are 10 MB of store, the init phase's one-time write)
(`ccl_kb_remember_macros/3`, `ccl_kb_macros_cached/2`); a table nowhere
yet comes from one standalone run of the preprocessor over the header
(`ccl_pp_file/3` + `ccl_pp_macros/1`, once per store; a header the store
would not take keeps its macros in a global, `list`, searched; a header
read preprocessed at `ccl_read_unit` remembers its macros then).
`pp_finish` takes a plain decimal by `number_codes/2` and runs the lexer
only on the rest. Measured on the B-tree, in-process, the source touched
so it is read: C++ mode 0.38 -> 0.47 s (the run 0.045, the three `.mac`
files 0.05), C mode over a fresh store 0.37 -> 0.46 s; the eager forms
cost 0.27. A file's time is asked of the system at every key (0.4 ms a
call, 36 per header's table): a per-process memo of it served a touched
file stale within the gate's one process, and bought nothing measurable. `_FORTIFY_SOURCE` is predefined 0, so `strcpy`
stays a function (the SDK's `secure/_string.h` would make it
`__builtin___strcpy_chk`, which nothing lowers), and C++'s `NULL`,
`__null`, reads as C's cast. Gated by `k86` over `test/c/macros.c` and
`test/c/run/macros.c` in the compile gate (the file's own macros, the
headers' NULL, EOF, INT_MAX and stdin, `__LP64__`, `__LINE__`); the
reader's version was bumped for it (28), since the store keyed by the
old one served the old read of an unchanged fixture.
`#elifdef` (0.43), `__VA_OPT__`, `#embed` and `__has_embed` (0.93) are in. Not done: trigraphs, a `//` comment
ending in a backslash; a summary carries a header's macros in the C++
mode only (a C header's live in the store).

## How the lowering is implemented

`library(ccl_ir)`: `ccl_ir_units/2` rebuilds the symbol table from the units
(`ccl_items_note/1`) and emits text. Per function, globals hold the state:
`'$ir_body'` (lines, reversed), `'$ir_allocas'` (the entry block's),
`'$ir_env'` (frames of Name-loc(Addr, Type)), `'$ir_defers'` (frames of
defer bodies), `'$ir_loops'` (break/continue targets with the defer depth
at entry), `'$ir_term'` (is the current block terminated). **`ir_expr/4`
gives a value, its C type (resolved where the lowering resolved it) and
its LLVM type** -- `ptr` for an array that decayed, whatever `ir_type/2`
says of the array (`ir_value_ll/2`) -- and `ir_lval/4` a slot, the C type
there and its LLVM type; `ir_load_slot/4` and `ir_store_slot/4` take that
type, `ir_convert/6` both types' LLVM forms, `ir_binary/8` and
`ir_arith_op/4` the operand's, `ir_cond/2` reads it off the value;
`ir_fp_ll/1` tells a floating LLVM type, `ir_fp_wider/2` which extends to
which. The /3 forms of `ir_expr` and `ir_lval`, the /3 slots and
`ir_convert/4` remain as wrappers for the callers with no LLVM type in
hand (the owner's request, 2026-09-06: the LLVM type travels with the
value so the consumers stop deriving it from the C type; it took 4,500
calls of 50,000 out of the B-tree's lowering, 0.21 -> 0.19 s -- `ir_type`
2300 -> 1400, `ccl_is_float` 680 -> 290 -- the rest being the inference
the check shares, `ccl_type_of` and its resolutions). `ir_cond/2` an i1;
`ir_ins/1` opens a dead block after a
terminator so every block ends once. `defer`: `ir_run_defers/1` inlines a
scope's bodies LIFO at its end, at `break`/`continue` (the frames inside the
loop) and at `return` (all). Doubles print as LLVM's hex (`ir_double/2`);
structs are named types registered once; an anonymous struct is keyed by
its members. Externals used get `declare` lines from their prototypes.
An anonymous struct's name lives in `'$ir_anons'`, not in `'$ir_structs'`
where a name means "defined". Not lowered yet: VLAs, `_Complex`, `long double` (as double) -- each
`error(not_lowered(What), where(F))`.
Every address is `getelementptr inbounds` and signed integer arithmetic
is `nsw` (C's undefined behaviours, past the object and signed overflow),
so LLVM widens loop counters and drops the sign extensions before an
index: a quarter of a B-tree's insert time, measured by
`bench/btree/run.sh` (cicili -O3, clang -O3 on the same algorithm, Rust's
BTreeSet at its own fanout of eleven keys). With the node's children in a
bounded own array -- a 56-byte leaf, no cast -- a branchless key scan
where a key is placed, and deletion that fixes only a node left short on
the way back up, cicili beats BTreeSet on insert and search and ties it
on deletion (owner's goal, 2026-09-05, a million keys, min of 11:
94/90/62/92/66 ms against 107/96/60/95/63 for insert, search, delete
half, search again, delete the rest). Two throwaway experiments showed
the element moves' null test and the drain before free cost nothing
measurable; the run-to-run noise on this machine is up to a fifth, so
only interleaved minimums mean anything.
**Unions, bitfields, static locals** (M2b's gaps, closed): a struct's LLVM
shape comes from its C layout (`ccl_members_layout/4` in `ccl_infer`: SysV
packing, `lay(Name, T, ByteOff, none | bits(BitOff, Width, UnitBytes))`;
`ccl_layout//2` is the LEXER's whitespace rule, hence the name):
`ir_struct_shape/3` gives an element per plain member, one `[K x i8]` per
run of bitfields (the bytes their bits span, runs split where no byte is
shared), padding where C's offset is past LLVM's natural one and at the
tail, and a map `m(Name, Index, T, none | bf(RunLL, BitOff, Width,
Signed))` kept in `'$ir_maps'`. A member is a SLOT (`ir_member_slot/5`): an
address, or `bf(Addr, RunLL, Off, W, Signed)`; every load and store of an
lvalue goes through `ir_load_slot/3` and `ir_store_slot/3` (a bitfield:
the run loaded `align 1`, shifted and masked; `&` of one is
`address_of_bitfield`). A union is `{ iA, [N-A x i8] }` for its alignment
A (or `[N x i8]`), every member at its address; a union global initialized
takes the literal type of the member given. Struct and union allocas and
globals carry `align`. A static local is `@fn.name.K = internal global`,
its constant folded as a global's (`ir_gstruct/3` packs bitfield runs
into `c"…"` bytes). The ABI's leaves come from the same layout.
**Structs by value cross a call as the platform ABI has it** (M3):
`ir_abi/2` classifies a struct -- `scalar`, `direct([piece(LL, Off)...])`,
`memory(LL, Align)` (SysV byval / sret), `indirect(LL, Align)` (AAPCS64's
pointer to a copy) -- from its leaves (`ir_leaves/3`: every scalar at its
byte offset); SysV: over 16 bytes memory, else each eightbyte INTEGER
(`iN`, N the bytes it holds) when any integer or pointer lies in it, else
`double`, `float` or `<2 x float>`; AAPCS64: over 16 indirect, an HFA
`[k x float|double]`, else `i64` or `[2 x i64]`. `ir_fn_sig/6` spells a
signature from it, used alike by a define (`ir_params/4`: pieces stored
into an over-aligned alloca, byval and indirect used in place), a call
(`ir_call_/6`, `ir_arg_parts/5`: the value stored to a temporary and
loaded back as pieces; an sret temporary first; a direct return stored
and reloaded as the struct) and a declare. The host decides (`uname -m`,
`'$ir_arch'`). Proven on x86-64 against clang-built code both ways
(`test/driver.sh`, `test/c/link/abi_*`; `abi_libc.c` through `div`/`ldiv`);
the arm64 side is written, not proven.

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
i-th parameter is `own`. The lowering treats `move(E)` as `E`. **Borrows:**
a plain pointer declared or assigned from an expression `ck_borrows_from/3`
traces to an owner (`id`, `+`/`-`, a cast, `&p[i]`, `&p->x`, another
borrow) is `N-borrow(P)`; `ck_consume` turns every `borrow(P)` into
`dangling(P)` (`ck_dangle/3`), a use of which is `borrow_after_move`; a
`return` of anything that borrows is `borrow_escapes` (`ck_no_escape/2`);
assigning a borrow from something else unbinds it. Every statement node
carries its line first (`ccl_add_lines/3` gives a macro's short forms the
call's line), `ck_line/1` keeps it, `ck_short/2` names the form without it.
**Owners inside structs (M3 complete):** an owner is a KEY, a name or a
path atom (`'p->name'`, `'c.name'`, `'c.inner.name'`, `ck_path/2`); a
variable's own fields (`ck_var_fields/3`: an own pointer to a struct opens
`->`, a struct by value `.`, a member held by value recurses, an own
pointer member is one key and stops) are declared with it, the base at the
frame's head so a leak names it first. States: live, null (a null constant
assigned; free, move and overwrite are fine), unset (no value yet, or a
field of a struct from malloc), moved, partial. `ck_consume/6` takes a
`How`: free demands the fields consumed (`owner_leaked` on the field),
move demands them complete (`owner_unset`, `use_after_move`) and moves
them along; `ck_into_own/6` is every own slot's assignment (an owner moved
in with its fields transferred, `ck_transfer/5`; null; fresh; a borrow
refused, `borrow_stored`), `ck_into_plain/4` every plain slot's (an owner
or a borrow refused, `owner_stored`/`borrow_stored`); `ck_fill/6` a struct
by value receiving a whole value (fields moved from a struct, item by item
from an initializer through `ck_init_slots/5`, all live from a call). The
checker now declares every local in the symbol table (`ccl_declare/2`,
scopes pushed per block), so `ccl_type_of/2` types a slot and `ck_is_local/1`
tells a global from a local. Fixtures: `own_fields.c` runs, seven `safe/`
programs are refused. **Parameters are borrows:** a plain pointer (or
array) parameter enters as `N-borrow(N)`, its own name the tag
(`'$ck_params'` lists them); `ck_no_escape/2` lets a borrow of a parameter
return (and checks only pointer-typed returns); `ck_borrows_from/3` looks
through `->`, `.`, `[]` and `*`, so a borrow is declared only for a
pointer-typed variable or slot; `ck_args/5` refuses a borrow where the
callee consumes (`borrow_consumed`), the callee being `id(F)` or
`params(Ps)` from a function pointer's type (`ck_fn_params/2`). The own
fields of a struct a plain pointer parameter points to are live keys of
the struct's (`'$ck_borrowed'`): freeable and replaceable, exempt from the
leak check, and `ck_complete_owners/2` demands them live or null at every
return (`borrow_incomplete`). `params.c` runs, five `safe/` programs are
refused.

**Ties (`<*>`):** `'$ck_ties'` holds Key-Root for every declared tie -- a
local's, a parameter's, a field's per instance (`ck_note_tie/2`; dropped
when the key is declared again). A tied plain value is `borrow(Root)`
whatever its type (`ck_var_tie/4`; `ck_field_ties/5` in member order, a
tie naming a later member is `tie_unknown`; `ck_param_ties/4` after the
owners, an earlier parameter only), the root being what y borrows when y
is a borrow. A tied owner keeps its state: `ck_consume` refuses it live
when its root goes (`ck_tied_consumed/3`, `tie_outlived`), and
`ck_into_own`, `ck_args_` and `ck_no_escape` let it move only within its
tie (`ck_tie_kept/4`, `tie_escapes`). A slot under a tied base is tied to
the base's root (`ck_tied_to/2`, the base path from `ck_base_path/2`) and
is assigned through `ck_into_tied/6`: `tie_mismatch` unless `ck_within/3`.
A result tie is `'$ck_ret_tie'` -- the callee's returns must lie within
it, the caller's `ck_borrows_from(call(...))` borrows the argument through
`ck_call_tie/3` -- and a parameter tie is checked at every call by
`ck_arg_ties/3`. A tie to a plain local, `&x` of one, or a local array
used as a pointer ANCHORS it (`ck_anchor/3`: `Y-anchor` in the state
frame of Y's symbol frame, the two pushed in lockstep; `ck_anchor_addrs/3`
runs before an expression statement, an initializer, a return): a root
nothing consumes; `ck_scope_end` dangles every borrow of a closing frame's
keys. A borrow of an anchor may sit in a plain slot (`ck_into_plain`), as
C always had it; a static local is never anchored (`'$ck_statics'`).
Borrows are declared for any type that carries a pointer
(`ck_carries_type/1`), not only pointers. A statement expression's last
value is consumed when it is an owner, which is how `clone`'s copy leaves
its block. **Loose pointers (owner's rule: every pointer has an ownership path, or
the program is refused):** a plain pointer local given a fresh value
(`ck_fresh_value/1`: not none, not an initializer, not null, not static)
is `N-loose`, a root for borrows (`ck_borrow_source`) that nothing tied to
it can outlive (`ck_within`); `free`, `fclose`, `realloc` (in
`ck_consumes`) and an own parameter consume it (`ck_consume_loose/3`:
none, its borrows dangle), a `return` takes it (`ck_loose_taken/3`), an
own slot takes it over (`ck_into_own`: none, its borrows retargeted to the
owner by `ck_retarget/4`); `ck_leaks` refuses a loose key as `unconsumed`
where an owner would be `owner_leaked`, and so does the id-assignment when
it overwrites one. A rebind or a loose lands in the frame of the variable's
symbol scope (`ck_declare_at/4`, which `ck_anchor/3` also uses). `untied`
("no owner behind") is for what the check cannot follow:
`ck_no_owner_behind/4` for a struct by value and `ck_into_plain/5` for a
field, an element, `*p`, a global, an initializer item (named by
`ck_slot_label/4`), given a fresh value or a loose pointer. There is no
warning channel: both were warnings for one commit (0.14) and are errors
by the owner's decision; `ck_squash/2` keeps a macro's expansion out of a
diagnostic's form. The ties' direction: a slot tied to y takes a value
whose ROOT OUTLIVES y (`ck_within(Y, Root)`), an owner tied to y moves
only into a slot WITHIN y (`ck_within(Slot, Y)`); a value rooted at a
field counts as rooted at the field's holder (a child of x returned as
x's). A result tie may name a static local of the function's
(`ck_body_static/2`) or a global: the root is `static(Name)`, which
nothing ends, freeing it is `borrow_consumed`, and `ck_call_tie/3` gives
it to the caller. `ck_refine/4` under `if`: `!p`, `p == NULL` make an
owner null on the then path, `p`, `p != NULL` on the else path, its own
fields with it (`ck_set_null/3`). An owner moved in from an own FIELD
(whose pointee is not opened) has complete fields (`ck_complete_rest/4`),
and a struct's fields move out, or fill, only for a struct held BY VALUE
(`ck_by_value/1`), never for a pointer parameter whose pointee's fields
are keys. **A struct with owners handed BY VALUE hands them to the
callee's copy** (0.40, the rule `person d = c` already had for a copy):
the caller's fields move at the call (`ck_args_`, the branch after the
consumers), the callee's by-value parameter owns its copy's fields
(`ck_param_owners`, the last branch) and must consume them; `own_fields.c`
takes its structs by pointer since, and `safe/by_value_move.c` frees a
field after handing the struct over (`use_after_move`). `statics.c`
ties its static results, `untied.c` and `unconsumed.c` are refused.

**Own arrays (owner's rule: a constant bound, or nothing):** `own node
*C[4]` is one key -- a local's name or a field's path, listed in
`'$ck_arrays'` (`ck_note_array/1`, `ck_own_elem/2`) -- with the state
`array`: readable, a root for borrows, exempt from leaks, never consumed
by the check, since the LOWERING drains it. An element `index(Path, _)` is
an own slot with no key (`ck_into_own(none, ...)`): an owner moved in, a
null, a fresh value, never a borrow; `move(C[i])` is `fresh` to the
receiver and dangles the array's borrows (`ck_dangle(K)`), as does
freeing or overwriting an element. The struct's birth sets its fields by
mode (`ck_alloc_mode/2`: malloc/realloc garbage, calloc zeroed, else
complete; `ck_set_fields/5`), and a garbage array is `array_unset`; a
local array needs an initializer. `ck_type_rules/3` at every local and
parameter: `ck_bounds_ok/3` (`own_unbounded`: an own pointer behind a
plain pointer, an array with a non-constant bound; an array parameter
too), `ck_array_struct_ok/3` (`own_array_untagged`, and the members'
bounds), `own_array_by_value` for a struct with an own array declared,
copied (`ck_no_array_copy/3` in `ck_fill`), passed or returned by value.
The lowering (`ccl_ir`): `ir_drain_functions/1` makes one
`function(0, static, void, ccl_drain_<tag>, [x], ...)` per tagged struct
in `'$ccl_tags'` with an own array (`ck_has_own_array/1`), its body a
`for` per array path (`ir_drain_loop/3`: `if (a[i]) { ccl_drain_T(a[i]);
drain_free(a[i]); }`, recursive through the element's struct), noted with
`ccl_items_note/1` and lowered after the units; `free(E)` of a pointer to
such a struct becomes `({ drain(E); drain_free(E); })` (`ir_drain_free/2`,
E bound to a temporary unless an id; `drain_free/1` is the lowering's own
node for a free past the drain); `a[i] = R` becomes `({ T **p = &a[i]; T
*n = R; if (*p) { drain(*p); free(*p); } *p = n; })` (`ir_elem_assign/3`);
`move(a[i])` loads then stores null (`ir_own_elem/1`); an element handed
to a consumer is wrapped in `move` first (`ir_moved_args/3` over
`ck_consumes`); a local own array registers its drain loop as a defer
(`ir_array_defers/2`). A struct's LAST member may be bounded by an
earlier integer member, `own node *C[nc]` (`ck_members_ok/3`: the
sibling in Seen, integer, last; else `own_unbounded`): a flexible member
of no bytes (`ccl_size_align(arr(_, E), 0, A)`, `ir_type_` gives `[0 x
T]`), the drain's bound `arrow(x, nc)` from `ir_array_bound/4`; the
developer allocates `sizeof(node) + k * sizeof(node *)` and sets `nc`.
An array's bound is any constant expression (`ccl_const_eval/2`: a
literal, an enumerator, arithmetic), in the layout, the LLVM type and the
check alike, so `enum { MAXK = 11 }; int key[MAXK];` sizes as C does.
`btree.c` on `own node *C[4]` and `btree_del.c` on `own node *C[nc]`
with deletion (minimum degree 2, the expectation made by the C mirror
under AddressSanitizer) are the ownership test case (`leaks` finds none),
`slots.c` a local array, `flex.c` the bounded one; five `safe/` programs
are refused; `tie.c` and `clone.c` run, eight `safe/tie_*.c`
are refused.

## How the LLVM module is written (the Cicili module pattern)

Every C function a Cicili module calls that is not in Cicili's std is
declared with `(decl) (func Name ((Type arg) ...) (out Type))`, mirroring
the header (compatible types, one token each -- `LLVMBool`,
`LLVMContextRef`, `char **`; `unsigned` needs an alias,
`(@define (code "uint_t unsigned"))`). An enum constant or a `static inline`
from a header cannot be named in Cicili at all: it goes behind a one-line
raw C helper, `(code "static T ccl_ll_x(...) { ... }")`, itself declared with
`(decl)` -- the numpy module's way. `(cof p)` is `*p`, `(? c a b)` the
conditional, `(cond ((test) ...) ...)` a chain; a `let` initializer that is
not a call is written `(T x . nil)` then `(set x ...)`. A parameter may not
be named `asm`. **What `coco_m_error/3` returns is the predicate's answer,
not a status** -- a helper that raises must hand that back in an out
parameter and return 0 itself, or its caller walks on into LLVM with a null
module (a segfault that looked like the error path's). The build mirrors `module/build.sh` plus `llvm-config
--cflags/--ldflags`, `-lLLVM-C` and an rpath to LLVM's lib.

## Findings about the neighbours, worked around here

* **cocolog HAS NO GARBAGE COLLECTOR: the heap is reclaimed on backtracking
  and by nothing else** (its own DESIGN-compiling.md says so; measured
  2026-09-10 on 1.2.12: a list of a million integers is 44 MB, thirty of
  them built in a deterministic recursion 521 MB, thirty `nb_setval`s of
  one 992 MB, thirty `assertz`+`retract` 2.2 GB -- and thirty inside
  `\+ \+ (...)` or a failure-driven loop 42 MB). A deterministic run keeps
  every term it ever built: the flatten of `<vector>`'s closure peaked at
  3.1 GB, the parse of the flattened text at 1.5 GB, a `cicili++` run of
  `std::vector<int>` at 4.5 GB, on the owner's 16 GB machine. So: (1) the
  preprocessor runs EACH FILE inside `\+ \+`, keeping only its output
  under a key, spliced in by `pp_finish` (`pp_include_file`: 3.1 GB ->
  564 MB, the same text); (2) a gate's harness runs each check inside
  `\+ \+` (test/cpp.pl, test/reader.pl), so a process's peak is its
  biggest check's, not their sum; (3) a SET of names the parser asks at
  every identifier is BUCKETS, a global each (`ccl_set_has/2` and kin in
  ccl_syntax: the env's names `'$ccl_envs'`, the templates `'$ccl_tmpls'`,
  the function templates `'$ccl_ftmpls'`; the lists stay for the
  enumerations and the snapshots, every writer keeps both), where
  `ccl_known_typedef` and `ccl_known_template` copied six hundred and
  fifteen hundred names per call (1.47 -> 1.03 GB for the parse); a deep
  grammar rule passes the marker `genv` for the global env instead of a
  copy of it (`ccl_env_member/2` walks a threaded env to its tail, then
  asks the set); (4) a C++ class's tag is noted without its bodies
  (`ccl_slim_members`). What is left of the parse's gigabyte is the
  committed items' intermediates -- the item loop cuts, nothing above it
  backtracks -- a one-time cost per library header, cached afterwards.
  `ccl_global/3` runs `ccl_ensure_globals` FIRST: inside the
  initialization only a bare `catch(nb_getval(K, V), _, fail)` may read a
  global, or the initialization re-enters itself without end (that
  runaway restarted the machine). Raise with cocolog's owner: a collector,
  or `garbage_collect/0`. SINCE cocolog 1.2.13 (2026-09-14) THE STORE RECLAIMS
  ITSELF (the finding on the counters below): dead rows of `assertz`,
  `retract` and `nb_setval` overwrites are compacted away at safe points,
  `garbage_collect/0` forces it and `statistics(store_used, B)` reads it; the
  HEAP still reclaims on backtracking only, so the `\+ \+` discipline stays.
* **cocolog's integers are 61-bit, so a C `long' cannot be spelled through this compiler past 2^60**
  (2026-09-24, the C23 step): the native lexer computes a literal in u64 and hands it to `coco_m_new_int',
  which truncates alike (the finding on the lexer's own entry), and `number_codes' of 2^63-1 is not
  2^63-1 -- so `printf("%ld", LONG_MAX)' prints a wrong number and `LONG_MIN + 1' another. Every fixture
  keeps to `INT_MAX' and `INT_MIN'; a program that names `LONG_MAX' gets a wrong answer and no
  diagnostic, which is the worst kind, and is named here until cocolog's owner has a wider integer or
  this compiler refuses the literal by name.
* **cocolog CANNOT REPORT A FAILED ALLOCATION: a refused request is a WRONG ANSWER,
  not an error** (2026-09-15, measured by cocolog's owner's session with an interposer
  that refuses any request at or above 16 MB, after this repository's libc++ gate died
  on it). The `oom' flag is set in eleven places -- every array that grows sets it when
  realloc says no -- and read in ONE, a check inside the compaction; nowhere else. So
  `coco_push' answers index 0 without writing, every term built afterwards IS the cell at
  index 0, and the proof walks on over garbage: `numlist(1, 400000, L), length(L, N),
  last(L, La)' answers `false.' and prints `ERROR: ?-: Unknown message: _G0', the ball
  being that same cell read as an error term. Nothing stops after the flag is set, so the
  engine asked for the same 16 MB 551,514 times before the query ended. WHAT IT LOOKS
  LIKE HERE: a gate that dies with exit 1 and NOTHING in its log. The libc++ gate did
  exactly that once at 0.84, 155 s into a 900 s run, straight after the C++ gate's 2157 s
  on a 16 GB machine, peaking at 1018 MB against a 2800 MB cap -- the MACHINE was out,
  not the process, which is why it ran clean alone afterwards and why it cannot be
  reproduced on an idle box. A gate now prints its query's EXIT STATUS and the raw tail
  when no GREEN or RED line comes back (`test/libcxx.sh`, `test/cpp.sh`): `false.' and an
  Unknown message about a `_G' variable is this, and is worth telling apart from a goal
  that really failed. AND THE ONE PLACE THE FLAG IS READ PROTECTS THE STORE AND TELLS
  NOBODY (read from the source by that session, 2026-09-15): the compaction copies into a
  SEPARATE array and tests `oom' after the walk and before a single pointer is swapped, so
  every failure path leaves the store byte for byte as it was and answers 0 -- and every
  caller (assert, retract, nb_setval, the end of a findall) ignores that answer. So a
  compaction that meets a refused allocation is a no-op, and a gate death of this kind is
  NEVER the store corrupted and never a compaction crashing: it is always one of the other
  ten sites having turned the machine to garbage earlier, with the compaction, if it runs
  at all, quietly declining. The symptom to watch for is therefore the only one: exit 1, a
  `false.' that should have been an answer, and a message about an unbound `_G' variable.
  To raise with cocolog's owner: an `oom' check in the step loop answering
  `resource_error(memory)'; it is their engine's call, and they have it.
* **A build that writes to one tree and is audited against another cannot report
  honestly** (2026-09-15, cocolog's `install/install-linux.sh` on a fresh Ubuntu 24.04).
  `common.sh` takes `ZIGURATIP_HOME=${ZIGURATIP_HOME:-$ZIGURATIP/home}`, so an INHERITED
  value beats the `ZIGURATIP=` the caller passes; the Colab runtime exports
  `ZIGURATIP_HOME=/content/ZiguratIP/home` from earlier work, and every project then
  staged its headers and objects there while `MVCCS-cicili/mvccs.cpp` looked for
  `../home/include/zexception.hpp` -- a CHECKOUT-RELATIVE path -- in the tree actually
  being built, found it empty, and died. Nothing linked: 0 libraries, 0 objects. What
  made it cost an afternoon is that the installer's completeness check reads
  `$ZIGURATIP_HOME/lib`, so it audited the OTHER tree and reported "thirteen present,
  one missing" for a build that had produced nothing at all -- a plausible partial
  result that sent two of us after MVCCS and the staging pass. Setting both variables
  to the same tree fixes it outright: `home/include` 2 -> 104 files, `home/lib` 0 -> 14
  with `libMVCCS.so`, all four binaries, and cocolog builds. Raised with cocolog's owner
  through the cocolog session, which wrote the guard (refuse and name both paths, never
  derive silently, since an inherited home may be somebody's deliberate arrangement) and
  a `make EMBED=0` for a store-less cocolog -- `--local`, tier-2 libraries and consulted
  programs all working with 21 weak `ce_*` symbols left null and `--embed` refusing by
  name -- both landing in 1.2.16. AND THE LESSON FOR THIS REPOSITORY, which is the same
  shape as the two below: an instrument that answers without measuring the thing you
  asked about will answer confidently and wrongly.
* **On macOS the memory counters READ LOW, and the store's dead rows were the
  weight** (2026-09-14, with cocolog's owner's session). One identical C++
  build measured four times with `/usr/bin/time -l` gave 3252, 1821, 1728 and
  3506 MB, and ps's RSS spread 1.6 to 3.0 GB over fifteen runs of the same
  work: Darwin's realloc extends a large block in place when the address space
  after it is free and otherwise MOVES it by copy-on-write remap, and the moved
  pages drop out of `maximum resident set size`, `peak memory footprint` and
  ps's RSS until they are touched again (1024 MB written, 808 reported, all
  1024 back once every page was read); whether a block moves depends on what
  landed after it, so identical runs differ, and the HIGH reading is the honest
  one (Linux's glibc mremaps and has neither effect). The honest cost of the
  combined string-map fixture was about 2.9 GB: heap 1540 MB plus STORE 1323 MB,
  of which 20 MB was live -- 105,049 `nb_setval` calls, 103,192 of them
  overwrites, had left 1073 MB of old global values in the store and nothing
  took them out, plus 236 MB of findall solutions. cocolog 1.2.13 COMPACTS THE
  STORE (every reachable term copied into a fresh cell array at safe points,
  once 32 MB of cells are dead and outnumber the live ones, or once the store
  has grown by as much again as it held at the last compaction;
  `garbage_collect/0` forces one; `statistics/2` answers cputime, inferences,
  globalused, trailused, atoms, functors and store_used), and the fixture ends
  at heap 1616 + store 53 + trail 29 MB. The HEAP is ours to shape: a
  `nb_getval` copies the whole global onto the heap, and a read made at top
  level stays until the query ends -- the driver's top-level loop putting each
  declaration's work inside `\+ \+` with its results in the store would drop
  the high-water to the biggest single region; a heap collector stays
  cocolog's "not started" item. A watchdog on ps's RSS under-protects on macOS
  (the number reads low); the cap stays, and `statistics/2` is the honest
  question to ask from inside. The string map stays two fixtures.
* **A GATE'S ELAPSED TIME IS NOT A MEASUREMENT ON A LAPTOP THAT SLEEPS** (2026-09-15, the
  C++ gate at 0.88). The gates time themselves with `date +%s`, which counts the hours a
  closed lid spends asleep: one run read 16655 s where the work was at most 6254, the machine
  having slept 173 of 278 minutes (`pmset -g log`, a `Clamshell Sleep' on battery and five
  maintenance sleeps). Nothing warns you -- the log is complete, every check passed, and the
  number is simply eight times too big. So: a timing is compared only against a run whose
  window is known to have been awake, `pmset -g log | awk '$4=="Sleep"||$4=="DarkWake"'` is
  the check, and where a number has to mean something it is CPU time (`time`'s user + system),
  which a sleep cannot inflate. The shape is the other tell: a real slowdown is evenly slow,
  while a sleeping machine leaves the progress in bursts. This is the third instrument in
  these findings that answers confidently without measuring what was asked -- macOS's memory
  counters, the installer's completeness check, and now the clock.
* **AN INSTRUMENT THAT RE-RUNS THE LAST BUILD'S BINARY REPORTS THE LAST BUILD** (2026-09-16,
  chasing `stdstringops' at 0.89). My own `ipfull.sh' ran the fixture `if [ -x $BIN ]' -- and when
  a build FAILED the binary from the PREVIOUS build was still lying there, so it ran that one and
  printed its output under this build's heading. The screen showed the compiler refusing with a
  named error AND a run with a plausible diff, side by side, for two different programs; I read the
  diff as this build's answer and spent a turn on it. It removes the binary before building now.
  This is the fourth instrument in these findings that answers without measuring what was asked --
  macOS's memory counters, the installer's completeness check, the gate's clock, and now a stale
  binary -- and the tell is always the same: the answer arrived too cheaply, or arrived at all when
  the thing that would produce it had just failed. AND THE SAME AFTERNOON, THE OTHER HALF OF THE
  LESSON: a number that looks right is not a measurement either. With the `[[no_unique_address]]'
  rule stubbed off, `a + ", "' printed size 7 -- the right answer -- and I took it as proof that the
  road worked; it was right because 5 + 2 is 7 whatever bytes the views held, and the probe I then
  wrote to check it (`std::string_view v = s;') exercised a DIFFERENT road, so its garbage sent me
  to correct a conclusion that had been correct. The fix is the one this repository already has: one
  variable, and the baseline measured -- the same fixture built against the COMMITTED library
  (`GUARD_LIB' with `git show HEAD:library/X.pl' in a scratch directory, under its own HOME so the
  reader's summaries are not disturbed) answered in 79 s and told me in one line that the regression
  was mine.
* **A DEBUG `write/1' FROM INSIDE THE LIBRARY DOES NOT REACH THE SCREEN THROUGH `bin/cicili'**
  (2026-09-17, chasing the reference conversion at 0.90). The command's output filter keeps only
  `: error: ', `: note: ', `cicili: ' and `unit(' lines (`bin/cicili', the one `awk' pass), so a
  `write(dbg(...))' put in a clause to see whether it is reached prints NOTHING -- and silence there
  reads exactly like a predicate that never ran. I instrumented `cpp_ref_args_', saw nothing, moved
  the instrument one predicate out, saw nothing again, and concluded the whole road was dead; it was
  running all along. Prefix the term with `cicili: ' (`write('cicili: '), write(dbg(...)), nl') and
  it comes through, or run the query under `scratchpad/guard.sh', which has no filter. This is the
  fifth instrument in these findings that answers without measuring what was asked, and the first
  whose answer is silence -- the tell is that ABSENCE is not evidence unless the channel is known to
  carry a presence.
* **AND 0.58's LESSON IS A SHELL LESSON TOO**: `scratchpad/ipfull.sh' had its watchdog appended to a
  line that already carried a `#' comment, so `sh $S/watch.sh 2800 $secs ... &' was inside the
  comment and every fixture built with NO memory cap at all -- the runs that produced this step's
  numbers before it was found were unguarded, which is the one rule this repository does not bend. A
  comment ends the LINE in `sh' as it does in a cocolog clause, and a line is never rewritten with
  one in the middle.
* **A MISSING RUNNER READS EXACTLY LIKE A PASSING ONE WHEN ITS OLD LOG SURVIVES** (2026-09-19, the
  gates after cocolog's binary went to 1.2.18). The session scratchpad had been reaped of some of its
  files -- `gate.sh' and `watch.sh' among them, `guard.sh' and 560 others left -- so my five-gate loop
  printed `gate.sh: No such file or directory' to stderr and then, for each gate, GREEN and a timing
  read by `grep' out of the log file from TWO DAYS BEFORE. Five GREEN lines, nothing run. The tell was
  that the numbers were yesterday's TO THE SECOND (reader 44 s and 393 MB, compile 39 s and 365 MB),
  and the structural one is better: `gate.sh' truncates its log before it starts, so a log holding old
  content is proof the runner never ran. Two rules out of it, both in the scripts now: a runner
  REFUSES when its watchdog is not beside it (`gate.sh' exits 2 rather than run a gate with no memory
  cap -- the same hole 0.90 found in `ipfull.sh', arrived at from the other side), and a loop over
  gates takes the runner's EXIT STATUS and stops, never reading a log it did not just see written.
  This is the sixth instrument in these findings that answers without measuring what was asked, and
  the second whose answer comes from ABSENCE -- the debug `write' whose silence read as a dead
  predicate, and now a tool whose disappearance read as a pass.
* **A WAITER WHOSE PATTERN MATCHES ITS OWN SHELL WAITS FOR EVER** (2026-09-19, the `<algorithm>`
  fixtures). `while pgrep -f "cocolog --local query"; do sleep 3; done` never ends: the pattern is
  in the command line of the shell RUNNING the loop, so `pgrep` finds itself. Three such waiters,
  each gating a build, sat spinning while nothing ran -- and the builds they gated never started,
  so the empty task outputs read exactly like "still building". The tell was three result files at
  precisely 0 bytes with NO cocolog process anywhere, which is not what work in progress looks
  like. The bracket trick is the fix (`pgrep -f "[c]ocolog --local query"`, which cannot match the
  pattern's own text), or watch the RESULT (a line count in the output file) rather than a process.
  This is the seventh instrument in these findings that answers without measuring what was asked,
  and the third whose answer is ABSENCE -- the debug `write' whose silence read as a dead
  predicate, the missing `gate.sh' whose stale log read as a pass, and now a waiter whose
  self-match reads as a busy machine.
* **`> CAP' IS NOT A MEASUREMENT, AND A PROBE WITH NO TIME CAP IS NOT A PROBE** (2026-09-19, the
  same afternoon). Every run of mine has had a MEMORY cap since 0.46, because the rules demand one;
  none had a TIME cap, and I carried a 27-minute fixture and then a 22-minute one without asking
  why a probe -- whose whole virtue is being cheap -- was running unbounded. The owner asked for the
  cap. Worse, the cap then produced a number I misused: with a 180 s cap `std::equal' read
  `TIMEOUT', I changed one clause, it read 239 s, and I reported an improvement. It had always been
  about 250 s; 180 was simply below it. A bound is not a value, and the only honest comparison is
  against the same fixture built on the COMMITTED library with one clause stubbed off (0.89's
  `GUARD_LIB'), which said 255 s against 239 -- noise, and the change was reverted. Measure the
  thing BEFORE changing it, or the first number you own is worthless.
* **No cocolog run of mine is unguarded, not even a small fixture:**
  `scratchpad/guard.sh SECS MB LOG QUERY [HOME]` runs one query under
  `perl -e 'alarm N; exec @ARGV'` (SIGALRM survives exec, so the alarm
  kills cocolog itself) and a watchdog that sums every `cocolog ... query`
  process's RSS and kills them all past MB, reporting the peak;
  `scratchpad/watch.sh MB SECS LOG` is that watchdog beside a whole gate.
  ONE GUARDED RUN AT A TIME: the watchdog sums every cocolog process. A
  background run gets `< /dev/null`, or the query loop waits on a stdin
  that never closes. `ulimit -v` is not enforced on macOS. A watchdog that
  kills only the direct child (a shell) leaves cocolog, its grandchild,
  running: that is what took the machine down. AND A PATH IN A GOAL IS
  QUOTED: the scratchpad's name holds a segment that starts with a digit
  (`38dd5e5b-...`), which no reader takes as an atom -- `cocolog: could not
  read the goal`, and nothing else said why. AND A BUMP OF
  `ccl_reader_version/1` invalidates every summary, so the FIRST gate
  run after one re-flattens the library headers and peaks far higher
  than the steady state (the C++ gate: 2512 MB cold against 1847 warm,
  which tripped a 2500 MB watchdog and read as a failure). Re-run before
  believing a RED that arrives with a version bump.
* **After a cocolog update, REBUILD the module** (`module/build.sh`): the
  engine went 1.2.5 -> 1.2.12 mid-work (and 1.2.13 on 2026-09-14, the store's
  compaction), and 1.2.8 moved the globals table
  into the `coco_store` struct; the `.so` reads the SDK's structs by
  their layout at build time.
* **A `catch/3` whose goal succeeds leaves a live frame: a later `throw/1`
  runs that catch's recovery and then continues after the catch** (in
  cocolog; `catch((catch(nb_getval(k, X), _, X = none), throw(x(X))), x(G),
  true)` gives `G = none`). A cut after the catch, `once(catch(...))`, or
  the catch as an if-then-else condition pops the frame. So NO BARE
  `catch/3` anywhere in this repository: every one is `once/1`-wrapped or a
  condition. The older finding that a `throw/1` inside `forall/2` escapes
  the `catch/3` around it is probably the same defect seen from the other
  side; loops that can raise stay plain recursion, and `new/3` checks its
  initial values BEFORE the instance exists. FIXED in cocolog 1.1.0
  (640f86e, 2026-09-05; the minimal case gives 7, and a throw inside
  `findall/forall/aggregate_all` reaches the catch around it). The wrappers
  stay: harmless, and a cocolog before the fix still runs this library.
* **Consulting a file of about 70 facts whose arguments carry goals into
  an embedded store segfaults cocolog**, so the gate's checks are clauses
  (`k1 :- check(Name, Goal).`), not facts driven by `findall/3`.
* **`atomic_list_concat/2` with an unbound element segfaults cocolog**
  (exit 139, no message) instead of raising an instantiation error; the
  gate's `k17` did that before its scratch directory was bound. FIXED in
  cocolog 1.1.0 (an instantiation error).
* **`atomic_list_concat/2` dies silently once its result passes about
  8 KB** (no error term; a later message may show garbage), while
  `atom_codes/2` takes hundreds of KB: anything long is joined as codes
  (`ir_join/3`) and made an atom once. FIXED in cocolog 1.1.0 (up to
  16 MB); `ir_join/3` stays.
* **`cocolog run FILE goal` under `--embed` consults FILE INTO the store**:
  its clauses persist, and a second program's `main` meets the first's. A
  gate program is loaded with `ensure_loaded/1` from a `query`, whose
  clauses are not stored, and its entry point has a name of its own
  (`reader_main`, `compile_main`).
* **`catch/3` costs in proportion to the terms bound inside it**: a read of
  the symbol table through `once(catch(nb_getval(...)))` took 37 ms, bare
  0.3 ms, and the checker and the lowering read it at every name. So the
  globals are all set once per process (`ccl_ensure_globals/0`) and read
  bare; a catch stays only where a call can really throw (`time_file/2`,
  `proc_run/4`, the macro call) and never on a hot path.
* **Under `--embed`, the first call of EVERY predicate probes the store, at
  a cost that follows the store's size in bytes** (a consulted 3-clause
  file: first call 39 µs on an empty store, 0.06-0.16 s on a 119 MB one,
  0.4-1.1 s on a 1 GB one; a second call microseconds; `use_module/1`
  itself instant; the same under `--local`: microseconds). A parse touches
  ~500 predicates, so every `cicili` command pays a floor: 13 s over the
  119 MB store, 83 s over the 1 GB one, 2 s with no store (6-11 s over the
  24-30 MB store the per-file layout leaves; 2.8 s under cocolog 1.2.2,
  against 2.2 s with no store). And **the store
  never reclaims a retracted row**: each reader version bump re-reads the
  headers into ~120 MB of new rows beside the dead ones (eight generations
  made the 1 GB). So the store is stamped with the reader version
  (`KB.version` beside it) and started afresh when it changes (`kb_prepare`
  in `bin/cicili`, `ccl_kb_prepare` in `test/config.sh`), and the gates run
  their checks in one process. (An earlier note here read this as lazy
  compilation at ~1 s per predicate; it had been measured only under the
  fat store.) The probe is FIXED in cocolog 1.2.2 (7f6a1ac, 2026-09-05:
  the store's string keys indexed): a first call is 52 µs over the 119 MB
  store. The stamp and the one-process gates stay, for the dead rows below.
* **A process that writes a predicate grows the store by about 500 bytes
  per row THAT predicate holds, whatever it writes** (one `assertz` of a
  five-byte fact into the 39k-row item predicate: +19.5 MB; three writes in
  one process the same; into a 158-row predicate +90 KB; into a fresh one
  +0; a read-only process +0). Forty writing gate processes turned a fresh
  123 MB store into 870 MB in one run. So a file's items are a predicate of
  their own (`ccl_kb_items/2`), and a routine compile writes only the
  source's small one and the 158-row index. Still so under cocolog 1.2.2
  (a 20,000-row predicate: +7.8 MB per writing process). To raise with
  cocolog's owner, with compaction.
* **cocolog's store cannot hold C++ headers as the AST cache holds C's.**
  A flattened `<cstdio>` is 2700 items, `<sstream>` tens of thousands, and
  a writing process pays by the written predicate's row count, dead rows
  never reclaimed: one `objects.cpp` read over a fresh `KB++` ran past five
  minutes and left a 187 MB store, and even without the writes the probes
  of hundreds of new per-file predicates were minutes. So `cicili++` and
  `test/cpp.sh` run `--local`, a run reads its headers again (about two
  seconds each, flattened), and the C++ cache is a summary cache still to
  design. To raise with cocolog's owner beside compaction.
* **cocolog WRITES a float infinity as `inf.0`, and its own reader refuses
  to read that back** (`ensure_loaded/1` says only `its clauses would not
  consult`, no line): one such float in a header's AST file cost the whole
  file, so every run flattened and read the header again, fifty seconds
  against three. A literal past a double (`__LDBL_MAX__`, and the `1e999`
  the preprocessor spells an infinite token back as) is the largest finite
  double at the parser's one float-literal door, `ccl_finite_float/2`.
  cocolog's `write/1` keeps 14 significant digits of a float besides
  (`1.0842021724855e-19` for LDBL_EPSILON), so a double does not round-trip
  through a written term exactly; nothing here depends on that yet.
* **cocolog's `term_to_atom(-T, +A)` fails past some tens of KB of atom**
  (`type_error(atom, …)` on a 37 KB line): a summary file keeps a term per
  LINE, its dependencies one each, never a list of hundreds in one term.
* **`term_to_atom(+T, +A)` with T bound, even partially, writes T and
  compares the texts; it does not parse A and unify** (`term_to_atom(mnames(Ns),
  'mnames([a])')` fails; `term_to_atom(T, A), T = mnames(Ns)` gives `[a]`).
  Every parse in this repository goes into a FRESH variable first; the
  summary's validity check passed its pattern in and read every summary as
  invalid, rewriting it at every run (14 s a read) before this was found.
* **cocolog's reader refuses a clause with `is` as a plain atom argument**
  (`var(is, …)`: an operator where an atom is meant), and a check name with
  `"` inside a quoted atom did not read either; `ensure_loaded/1` then says
  only `its clauses would not consult`, no line. Bisect by splitting the
  file into clauses (`test/cpp.pl` needed that twice).
* **Attribute time with stubs, ten runs deep**: a scratch copy of the
  library first on `COCOLOG_LIBRARY` with one clause prepended --
  `ck_anchor_addrs(_, St, St) :- !.` -- and the pass run ten times in one
  process (`q_check_n`), so a 5 ms piece shows as 50. The check of the
  B-tree (2026-09-06): 86 ms, of which the symbol table's rebuild was 17
  -- `ccl_add_envs/1` and `ccl_note_templates/1` added a summary's 190
  names one at a time, each addition a copy of the 500-name Env (one
  read, one write now: 5 ms), and `ccl_sum_load/7` re-split a summary's
  terms at every rebuild (kept per file, `'$ccl_sumload:'`) -- the anchor
  walk 7 (5 with `'$ck_arrlocals'`, the names declared as arrays, asked
  before the scope is), the type rules 9 (1 once the own-array test was
  per tag), the field ties, the escape and the leak checks nothing
  measurable; what is left, 60 ms, is the expression walk itself,
  `ck_expr` over 1000 nodes with a state lookup each, at the interpreter's
  5 µs a call. **A stub must be seen to succeed**: `ck_scope_end(St, St)
  :- !.` read as "the scope end is the whole check" (ten checks in 0.36 s,
  the read alone) until the harness printed its marker -- the stub left
  the frame unpopped, the function's end did not match, and the check
  failed fast. The walk restructured by shape (2026-09-06): `ck_expr`'s
  clauses ordered by what a node most often is, counted on the B-tree --
  a name, an operator or number (taken by one clause, `\+ compound`,
  where every head was tried before the last clause took it), a literal,
  a member or arrow that is no owner's key (its child walked directly:
  before, its path was built and looked up and the generic clause walked
  its field name as a child), an index, a binary operator, a unary wrapper
  (`ck_unary_shape/2`) -- and `ck_anchor_addrs` walking those shapes
  without a univ: 70 -> 65 ms. The 65 are 20,000 calls at 3 µs; a real
  cut needs the state no longer threaded as a frame list through every
  node (a table per function, or the lookups in C), a redesign, not a
  round.
* **A cache in a global copies its whole content at every read**, so a
  cache of pairs is for SMALL values only; a value that may be large (a
  struct's members) goes in a global of its own keyed by name, with an
  index of names (`ccl_cached_named/4`). Sped up this way, the inference
  round (2026-09-06) took `ccl_resolve_type` from 10,500 calls to 6,300,
  `ck_own_array_type` from 3,200 to 1,200 and `ck_has_own_array` from 800
  to 400 on the B-tree, and moved the clock little: those calls were
  one-clause answers already, 5 µs each. The inference is at its floor;
  what remains is the check's walk (`ck_anchor_addrs` over every
  statement, `ck_in` per state lookup) and the lowering's emission.
* **Rank every predicate's calls before touching a pass**: an
  instrumented copy of the library first on `COCOLOG_LIBRARY`, every rule
  head renamed and wrapped with a counter (heads only), a query that
  prints the counts sorted. The lowering of 170 lines was 46,000 calls:
  12,000 `ccl_resolve_type`, 4,000 of `ir_join`'s code walk (0.1 s by
  itself: a builtin does it in none), 2,300 `ir_type`. A `nb_setval` of a
  200-line function body per emitted line costs nothing measurable; of one
  2000-line body, 0.13 s -- the per-function reset keeps it small.
* **`nb_getval/2` copies the term it answers** (0.63 ms for a list of
  5000 pairs, 2 µs for a small one; `b_getval/2` exists and copies too),
  and `nb_setval/2` copies alike; a `memberchk/2` step is 0.15 µs; an
  asserted fact is found in 3 µs among 5000 (first-argument indexing) --
  but under `--embed` a clause is a row in the store (the finding above),
  so the tables stay globals: split so the big one is rarely read
  (`'$ccl_gscope'`), and answered through small caches (`ccl_cached/4`).
  The check and the lowering of 170 lines read the symbol table 4000
  times before that, 0.3 s of copying.
* **A DCG that tries its alternatives in clause order pays a token match
  per alternative**: the expression grammar made 62,000 token matches for
  2040 tokens (a cascade of ten levels, unary and primary rules of a
  dozen clauses each); one `ccl_peek` and a clause chosen by the token's
  value make it 17,000, and the parse three times faster. The instrument
  is a copy of the library first on `COCOLOG_LIBRARY` whose rule heads
  are renamed and wrapped with a counter (heads only: renaming the calls
  too bypasses the wrapper).
* **A summary's terms are parsed once per process** (`ccl_sum_terms/2`
  caches them in `'$ccl_sum:<File>'`, `ccl_sum_write/4` forgets its own):
  every consumer of an include asked for them again -- the validity check,
  the Env, the symbol table, the bulk rebuild, the driver's deps. And the
  parse itself is 20 ms for 622 lines: `term_to_atom/2` is the engine's
  reader in C. What made it 0.5 s was the line-end test, `sub_atom(L, _, 1,
  0, '.')` with a free position, 0.7 ms a line (the finding below); with
  `atom_length/2` and every position bound, 30 ms. The B-tree's read: 3.0 s
  when the terms were parsed five times, 2.0 s parsed once, 0.8 s parsed
  right.
* **A process spawn costs 0.14 s** (`proc_run/4` through the shell), and
  `uname -m` was spawned once by the preprocessor for the predefined
  macros and once by the lowering for the ABI -- 0.28 s of every build.
  `ccl_host_arch/1` in the module answers the arch it was COMPILED on
  (`@ifdef __aarch64__`), and both ask it first, `uname` only without the
  module. The one spawn left in a build is the link.
* **The command's shell is a floor of its own: a fork per `$(...)` and per
  pipe, 10 ms each on macOS (50 ms under this session's sandbox, where
  `sh -c true` alone takes 0.11 s).** `bin/cicili` forked twenty times --
  `dirname`, `cd`, `sed | head` twice for the store's stamp, `cat` twice,
  `printf | sed` per argument, four `printf | grep` passes over the answer
  -- and forks six now: one `cd`, one `awk` for both versions, `read` for
  the stamp, `case` for the exit, one `awk` pass that splits diagnostics
  from the `cicili:` lines. An empty file's syntax check: 0.62 -> 0.39 s in
  C++ mode, 1.05 -> 0.1 s in C mode over the store; the B-tree's read
  1.89 -> 0.82 s, its build 3.45 -> 2.32 s. What is left of the C++ floor
  is cocolog's start (0.06 s), the libraries' consult (0.03 s), the
  driver's own work (0.12 s for an empty file) and the shell.
* **A lexer in cocolog's DCG costs 0.15 ms a token, whatever is done to
  its clauses** (per-code recursion, a clause try per token kind, an atom
  per word); the way out is a cocolog module in Cicili -- the language
  any native piece here is written in -- which the design allows where a
  pass needs C speed. `coco_make/4` (lib/term.cicili, behind
  `coco_m_machine`) builds a compound from an array of argument terms; the
  module SDK has `coco_m_list`, `coco_m_cons` and the atoms and numbers,
  no compound. cocolog's integers are 61-bit (`number_codes` of 2^61-1 is
  -1, of 2^62 is 0): the native lexer computes a literal in u64 and hands
  it to `coco_m_new_int`, which truncates alike. What it bought, measured
  (`bench/compile/run.sh`, 2026-09-06): the B-tree's build 3.64 -> 3.45 s,
  its read 1.99 -> 1.89 s -- the lexer was 0.3 s of it; the read is now
  0.6 s of process floor (the library's clauses loaded: the engine alone
  starts in 0.06 s), 0.2-0.5 s per header's summary (`term_to_atom/2` a
  line, 622 lines for stdlib.h), 0.3 s of parser DCG for 2000 tokens.
  Those three, then the check and the lowering (1.4 s), are the order to
  take them in.
* **`sub_atom/5` with a free position costs about 150 µs a call** (it
  enumerates), and a plain walk over a code list about a microsecond a
  code: the preprocessor tests a line with `atom_codes/2` + `memberchk/2`
  (builtins, 8 µs), splits a file with `atomic_list_concat/3` (0.12 s for
  700,000 codes) and walks only the lines that need it. `sub_atom/5` with
  every position bound is fine. There is no clock predicate
  (`statistics/2`, `get_time/1` absent): a piece is timed from the shell.
* **A gate check with two clauses of one name runs both, by backtracking
  from a later failure, in odd counts** (k73 and k74 each had two: the
  `defer` ones and the tie/`#cocolog` ones; the gate printed one 3 times,
  another 7). Every check name is unique: the tie is `k81`, `#cocolog`
  `k82`, the preprocessor `k83`.
* **An unset global throws** (`nb_getval/2`: existence_error), so a global
  is read through `ccl_global/3` or a `once(catch(...))`.
* cocolog has `abolish/1`, `clause/2` on consulted clauses and `retract/1`
  of them, `nb_setval/2`, `dynamic/1`, `read_file_to_codes/2`, `phrase/2,3`,
  `number_codes/2`; it has no `predicate_property/2`, `flag/3`, `recorda/2`,
  `prolog_load_context/2`, `term_expansion`, and no `consult/1` as a goal.
* `0'"` and `0''` read badly in cocolog; the lexer writes 34, 39, 92 as
  numbers. `( A -> B ; C )` inside a DCG body is avoided in favour of
  `( A, ! ; C )`.
* **Since cocolog 1.2.0 (601e85b) a clause over the store's budget raises
  `error(resource_error(clause_length), _)` and stores nothing** -- the
  budget is the page less its header, about 7997 characters of the clause's
  text; `ccl_kb_remember/3` catches it, drops the file's rows and leaves the
  file uncached (read again next time). The silent loss below is what the
  budget replaced.
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

Commit and push only when the owner asks. **Every commit raises the
version** (owner's rule): the one string in `ccl_p_version` in
`module/cicili.cicili`, `0.N` with N one more than the last commit's; then
rebuild, since the `.so` carries it, and `bin/cicili --version` shows it.
Every commit ends with

    Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01FUuQ3oBiKs3XpXAEHLCL1F

and the push is `git push git@github.com:saman-pasha/cicili-lang.git main:main`.
Never commit `library/*.so`, `module/*.c`, `module/sdk.cicili` or `proof/forty2`.
