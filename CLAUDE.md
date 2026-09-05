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
module/cicili.cicili     the module: the C side (registration, ccl_version/1, and
                         ccl_cocolog_version/1 over the engine's coco_version_text) and the Prolog
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
bin/cicili               the command: clang's arguments, one cocolog run over ./KB (ccl_drive/2)
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
test/reader.pl           the reader's gate: a cocolog program, one clause per check (72),
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
sh test/driver.sh
sh proof/run.sh
```

**`bin/cicili` takes clang's arguments** (owner's rule: no new flags to
learn): `-c -S -emit-llvm -fsyntax-only -o -O0..-Oz -I -l -L -shared -v
--version -ast-dump`; `-g -D -W -f -std` are accepted and ignored for now.
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

## How the reader is implemented, and why that way

`cicili_ast(+File, -AST)` mirrors `phrase/2`: the whole file or an error;
`cicili_ast/3` mirrors `phrase/3`, answering the tokens left. Two DCGs in
`library(ccl_syntax)`: `ccl_lex//2` over character codes -> tokens
`tok(Kind, Value, Line)`; `ccl_externals//2` over tokens -> the AST (its
vocabulary is the file's header; every statement carries its line as its
first argument, `expr(L, E)`, `if(L, C, T, E)`, `return(L, E)` ...).
Precedence is a level per operator
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
An anonymous struct's name lives in `'$ir_anons'`, not in `'$ir_structs'`
where a name means "defined". Not lowered yet: VLAs, `_Complex`, `long double` (as double) -- each
`error(not_lowered(What), where(F))`.
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
are keys. `btree.c` is the ownership test case: a B-tree with linked
children (an array of own pointers has no rule yet: which element is
consumed cannot be told statically), `statics.c` ties its static results,
`untied.c` and `unconsumed.c` are refused; `tie.c` and `clone.c` run, eight `safe/tie_*.c`
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
