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
                         stdbool.h, float.h, iso646.h, stdalign.h, stdnoreturn.h
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
test/cpp.pl, cpp.sh      the C++ reader's gate: 33 checks over test/cpp/*.cpp, the six C++ files of Cicili's
                         test suite read whole, hello.cpp built through cicili++, and again from the summaries
test/libcxx.pl, libcxx.sh  the road to libc++: <vector> and <string> flattened and read WHOLE, under a fresh HOME
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
is written (the noters, the summaries, `ccl_with_file`'s restore). **A
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
`k84`. Not done: `#embed`, `_BitInt(N)`, `__VA_OPT__`, `#warning` printed,
`__has_c_attribute`, `unreachable()`, `nullptr_t` as a type name, `%b`,
the decimal floating types.

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
Not done: `#elifdef`, `__has_embed`, `#embed`, trigraphs, a `//` comment
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
  or `garbage_collect/0`.
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
  engine went 1.2.5 -> 1.2.12 mid-work and 1.2.8 moved the globals table
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
