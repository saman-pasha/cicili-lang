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
  GREEN: the owners programs run, twenty-eight programs are refused each
  with its error.
* **M2 -- the lowering.** `cicili_ir/2`, `cicili_compile/3`, `cicili_link/3`:
  C11's core -- every type, bitfields, unions and static locals included,
  every statement and
  operator, calls and variadic calls, structs by pointer and by value --
  across a call as the platform ABI has it, the same pieces, `byval` and
  `sret` clang uses, proven against clang-built code both ways --
  `defer` -- lowered to LLVM IR and run. `test/compile.sh`: eighteen
  programs built, run and checked, GREEN.
* **M6 -- the check and the lowering of the C++ forms, in steps. The
  first step DONE: C++ that is C with names.** A namespace flattens to
  its bare names, `extern "C"` is what every name has, `using` is
  nothing, `bool` is a byte and `nullptr` C's null, `static_cast` and a
  functional cast are casts, `enum class` an enum with scoped
  enumerators, a range-for over an array the `for` it stands for; a
  reference is a pointer bound once -- the check sees a borrow (a
  parameter's, an element's, a local's address), the lowering loads
  through it and passes and returns the address; `new` is malloc and
  `delete` free, an owner to the check. **The second step DONE:
  classes**, desugared to that C by `library/ccl_cpp.pl` before the
  check: a class is a struct of its data members with its base first,
  a method a function over `this`, a constructor called at the
  declaration, a destructor a defer of the scope (the exits run it,
  last declared first), a static member a global, `new` and `delete`
  construct and destroy, operators and default arguments resolve by
  name and arity. **The third step DONE: `virtual`**, a table of
  function pointers per class, its pointer the object's first member,
  set by every constructor; a call through a pointer or a reference
  goes by the object's own table, a call on a value straight, a virtual
  destructor runs the right one at `delete` and the base's after it.
  **The fourth step DONE: templates**, instantiated on use as a copy
  of the item with the parameters substituted, named by its arguments
  (`Buf.int.4`, `max2.double`): a class template at every template-id
  the walk meets, a function template at a call with its arguments
  explicit or deduced from the arguments' types, the instances joining
  the unit's items. **The fifth step DONE: lambdas**, a class of the
  captures (by value a copy, by reference a reference member) with
  `operator()` its body, the expression a compound literal of the
  captures' values, `auto f = ...` taking its type, a call of it going
  to the operator; a default capture takes every enclosing local the
  body names, the result type is deduced from the first `return`.
  **The sixth step DONE: a real program under the safe part** -- the
  B-tree of `bench/btree` written the C++ way, a class over Cicili's
  `own` pointers with a constructor, a destructor and const methods,
  the node helpers file-static, `new` and `delete` of the tree; the
  ownership check reads a constructor's `this` as fresh storage (its
  own fields unset, and live or null when it returns) and a
  destructor's as dying (its fields may be consumed, and whoever ran
  the destructor takes them as gone), so the class holds what C's
  struct held. **The seventh to tenth steps DONE, over classes of the
  program's own** (the standard library is libc++'s and never the
  compiler's, the owner's rule; libc++'s containers await the forms
  their bodies use): a class template over an `own` block and a
  range-for over an object by `size()` and `[]`, the classes and
  templates of a header the program wrote reaching every unit that
  includes it, linked once; methods overloaded by type (a name carries
  its parameters' types, a call picks the overload the arguments fit)
  and the rule a destructor brings, that a class with one is never
  copied -- by initialization, assignment, a parameter or a return by
  value -- but moved: `std::move` is Cicili's `move`, a struct moved
  whole empties its owners behind it so its destructor frees nothing,
  a struct handed by value hands its owners to the callee, an element
  leaves a container by an explicit destructor call `x.~T()`; and a
  member of class type constructed with its holder (an implicit
  constructor, an initializer list, an aggregate initializer) and
  destroyed with it, the members in reverse order. **The eleventh
  step DONE: C++20.** `-std=c++17|20|23|26` is the language level,
  C++17 the baseline: the level's predefined macros (`__cplusplus`,
  the `__cpp_*` feature tests, from the reference compiler's `-dM -E`
  once) are what libc++'s headers key on, and every summary is one
  level's. Read: `concept` and `requires` (the clause on a template's
  head, the expression with its requirements), `<=>`, `consteval` and
  `constinit`, `char8_t`, coroutines, `using enum`, a range-for with
  an initializer, an abbreviated function template, a template lambda,
  `if constexpr`, `[[likely]]`. Compiled: a concept is checked where a
  template is instantiated (its requirements type-check under its
  parameters, or the instantiation is refused by the concept's name),
  an abbreviated template is a template of invented parameters, `auto`
  results are deduced, `if constexpr` is decided at compile time, `<=>`
  on scalars is an int, `using enum` nothing (the enumerators are in
  scope); coroutines and template lambdas are refused by name.
  `test/cpp.sh`: ten programs built through `cicili++`, run and
  checked, plus the reader's `classes.cpp` and `templates.cpp`; `try`,
  a coroutine and an unsatisfied constraint are refused by name. GREEN.
  **The twelfth step DONE: C++23.** Read: `if consteval`, an explicit
  object parameter (`int f(this const C &self)`), the multidimensional
  subscript `a[i, j]`, `auto(x)`, a lambda's specifiers without the
  parentheses and a static lambda, an alias declaration in an
  init-statement (and `using T = type;` in a block, `if (init; c)`,
  `switch (init; e)`, which were missing), a label ending a block, the
  `z` suffix, the delimited escapes `\x{…}`, `\o{…}`, `\u{…}` and the
  universal character names (as UTF-8), `#elifdef` and `#elifndef`.
  Compiled: an explicit object parameter is the function's first, a
  reference or a copy, where an implicit `this` is an address, the
  object passed as declared at every call, no implicit member access
  in the body; a lambda's `this auto self` is the closure itself, its
  captures reached through it, so a lambda recurses; `if consteval`
  keeps the run-time branch; `auto(x)` copies the decayed value;
  `a[i, j]` goes to the class's `operator[]`. A typedef inside a block
  reaches the passes now (it did not, in C either). `cxx23.cpp` built
  at `-std=c++23`; `this auto` on a class's method refused by name.
  GREEN.
  **The thirteenth step DONE: the road to libc++, its first
  stretch.** THE READER READS libc++ WHOLE: `<vector>` (441 items) and
  `<string>` (434), flattened by cocolog's preprocessor -- before this
  step it stopped at their first item, a conversion operator, and every
  library header had been an empty summary. What that took: conversion
  operators, class-scope typedefs and aliases (known to the members
  after them), `static inline` members, parameter packs (`class...
  Ts`, `Ts... args`, `sizeof...`, `args...` in every list, fold
  expressions), partial and explicit specializations (`struct X<T *>`,
  `template <> struct X<int>`, `v<int> = true`), member templates and
  `friend` definitions, `typename T::x` and `X<T>::template f<U>`,
  `decltype` everywhere (a name's segment, `decltype(auto)`), the
  compiler's type traits as types and as tests (`__remove_cv(T)`,
  `__is_same(T, U)`), `noexcept(e)`, `alignof`, `operator""sv`, deduction
  guides, explicit instantiations, `::operator new`, `if (T x = e)`,
  `static_assert` at every level, and the vexing parse decided by
  whether a qualified name is known as a type. **clang's `-E`** is
  accepted: the flattened text, cocolog's preprocessor's, to `-o` or
  the terminal (the loop that found the forms: flatten once, read in
  seconds). `test/census.sh` counts a flattened header's constructs
  and shows where the reader stops; `test/libcxx.sh` is the gate.
  THE DESUGARING, on the program's own classes (`generic.cpp`):
  parameter packs bound, expanded in every list, folded (`(args + ...
  + 0)`), `sizeof...(Ts)`; a variadic `Tuple<H, T...>` by partial
  specialization, the most specialized picked; `enable_if` over a
  trait as SFINAE (every candidate of an overloaded function template
  is tried, one whose signature does not hold is no candidate);
  `typename C::value_type`; member templates and template
  constructors deduced at the call, `b.as<int>()` given; a static
  method through `X<T>::f(...)`; `auto` results deduced through the
  desugaring; `__is_same` decided at compile time; a static const
  member's constant folded. COPIES (`copies.cpp`): a copy constructor
  copies, a move constructor moves, chosen by the value category
  (`std::move(x)` to `C &&`); `operator=` by copy and by move; a
  by-value parameter of a class with a destructor is a copy the callee
  destroys; a local returned by value moves out. STRUCTURED BINDINGS
  (`bindings.cpp`): `auto [a, b] = p`, by reference, of an array, of
  a call's result. AND THE LIBRARY ITSELF: a flattened library header
  is indexed by name, each item registered when a name is first asked
  for, a class's members emitted as they are first used (the
  standard's rule); `std::vector<int>` gets through `vector`,
  `allocator`, `allocator_traits`, `numeric_limits`, `initializer_list`
  and the exception guard before it runs into the next forms -- under
  a budget now, since one unbounded run took the machine's memory.
  GREEN.
  **The fourteenth step DONE: libc++'s first function compiled from
  its own body.** `std::swap` of `<utility>`, over two pointers and
  over two ints, builds through `cicili++` and prints what clang++
  prints (`test/cpp/run/stdswap.cpp`) -- its result type through
  `__enable_if_t`, `is_move_constructible` and `is_move_assignable`,
  its body as libc++ wrote it. What that took: THE TEMPLATE TEMPLATE
  PARAMETER (`template <class, class, class> class _Layout`), bound to
  a template's name, passed on, used as a base -- the CRTP libc++'s
  split buffer makes of its layout (`ttp.cpp`); FUNCTION TEMPLATES
  CHOSEN AS C++ CHOOSES (`overloads.cpp`): every definition of the
  name is a candidate, one whose arity, deduction, defaults,
  constraints or class-typed parameters do not fit is none (a
  template-id parameter whose argument is no instance of that template
  fails to deduce, an alias template's is a non-deduced context), an
  exact match beats a conversion, the most specialized wins among what
  is left; the compiler's traits over two types decided
  (`__is_constructible`, `__is_assignable`, `__is_convertible`,
  `__is_base_of`) and the trait names a fixed list, since libc++ has
  functions spelled like them; a class's members typed under its own
  typedefs, a static inherited from a base folded, a static with its
  initializer in the class defined once; anonymous struct and union
  members (`anon.cpp`: libc++'s compressed pair is one); a function
  template's name told from a type's, so `_Tp __t(std::move(__x))`
  declares no function. THE AST BESIDE THE SUMMARY: a flattened
  library header's items are kept as a clause file next to its
  summary and consulted when the summary is served, so a program that
  instantiates a library template reads the header once ever (0.8 s
  where the first run took 8). AND THE LIBRARY'S FUNCTIONS ARE NOT
  CHECKED: libc++'s bodies keep raw pointers by their own discipline,
  which the safe part would refuse at every line, so what comes from a
  library header is compiled as C++ has it, and the program's own
  functions -- its own templates' instances included -- are checked
  as always. `std::vector<int>` reaches 43 loads
  and instances, up from 26, and stops inside libc++'s compressed pair,
  where a layout class's own `pointer` has to come through
  `allocator_traits`'s meta: the allocator machinery is the next
  stretch. GREEN.
  **The fifteenth step DONE: the allocator machinery's first forms, and
  the memory that had to come first.** cocolog reclaims memory on
  backtracking only, so a run kept everything it built: reading
  `<vector>` peaked at 4.5 GB. Now each file is preprocessed and each
  item is parsed inside a scope that backtracks, a name the parser asks
  at every identifier is answered from a bucket rather than a copy of
  the whole table, and a gate runs each check in such a scope: the
  flatten 3.1 GB -> 564 MB, the parse 1.5 GB -> 440 MB. The forms: the
  DETECTION IDIOM libc++ builds its allocator traits on -- a detector's
  partial specialization chosen by `__void_t<_Op<_Args...>>` matching
  `void`, `_Op` a template template parameter bound to an alias, the
  pattern a non-deduced context evaluated after the other elements bind,
  a member absent meaning no match (`detect.cpp`); a typedef resolved in
  the class that defines it, so `allocator_traits`'s `pointer`, written
  as its own base's `__pointer<value_type, allocator_type>`, resolves
  from any class that asks; a plain struct as a scope, an enum's name
  not. And the defects the allocator's own classes turned up: a class
  declared and not defined was registered as if it were the class, so
  the real definition never was; a constructor declared and not defined
  had no case, where a method and a destructor did; a class whose only
  constructors are a defaulted one and a converting template is
  default-initialized with nothing to call and copied by the implicit
  copy; the traits that ask whether a type is constructible or
  assignable now count a constructor template and look through a
  reference, so `std::allocator` is move-constructible as C++ says;
  `auto` deduces a pointer, which silently failed before. Behind all of
  them one habit: a registration that merely failed left a class
  half-registered and every later lookup lied. Each is a refusal now,
  with the steps traceable. `std::vector<int>` reaches 67 loads and
  instances, up from 43, through the exception classes, the compressed
  pair, the allocator's traits and `std::swap`'s result type, and stops
  in libc++'s `__to_address`. GREEN.
  **The sixteenth step DONE: `__to_address` and the uninitialized-memory
  algorithms.** One defect paid for most of it: the wrapper that sets
  the symbol table aside while a template is instantiated restored it on
  success and on failure, but not when the goal threw, and SFINAE throws
  by design. So after a rejected candidate, the calling function's own
  locals had no types: the first argument of a call deduced and the
  second did not. The forms that followed: a unary operator on a class
  goes to the class's operator, as a binary one already did, which
  libc++'s iterators are built on; a temporary of a class template's
  instance written with explicit arguments; a qualified path of several
  class segments walked one inside the next; a member alias template,
  registered and resolved through its class; a member initialized from a
  move choosing its constructor through it. And the detection that
  `iterator_traits` is built on: an ellipsis takes any number of
  arguments and is C++'s worst match, so a variadic overload wins only
  where nothing else fits; a member template named with explicit
  arguments resolves inside its own class; a `decltype` is a scope, so
  `decltype(test<T>(...))::value` names the class the expression has; a
  static constant's initializer is worked out in its class's own words
  before it is folded; and asking a class for a member it does not have
  refuses, which is what rejects the losing candidate. It had quietly
  become a value named after the class, so the wrong overload won.
  `std::vector<int>` reaches 156 loads and instances, up from 67,
  through the relocation algorithms, the exception guard, the wrap
  iterator and the iterator traits. GREEN.
* **The seventeenth step DONE: nested classes.** A class declared inside
  another is a type of the class that holds it and a class of its own,
  reachable as `Plain::Nested` outside, as `Nested` within, and named
  bare inside its own class, which is how libc++'s vector destroys
  itself. A class with no constructors takes braced aggregate
  initialization rather than a constructor call. Three older defects
  came out with it: a specialization's pattern qualifiers were ignored,
  so `numeric_limits<const T>` matched everything and the class derived
  from itself; a variable template used as a template argument was
  instantiated as a class; and an operator member template could not be
  named at all. `std::vector<int>` reaches 177 loads and instances.
  GREEN.
* **The eighteenth step DONE: a name that resolved to the wrong thing.**
  Two instances of one template existed side by side, one of them keyed
  by names that never resolved. The cause was in the reader: `auto` was
  deduced at read time from a function template's raw, unsubstituted
  signature, so the deduced type still named a template parameter that
  nothing had bound, and the desugaring then flattened that parameter
  away as though it were a namespace. A type that still carries a
  dependent name is not deduced yet, so `auto` stays and the desugaring
  deduces it once the call is instantiated. `std::vector<int>` reaches
  182 loads and instances and now stops in the exception classes, which
  pull in the string. GREEN.
* **The nineteenth step DONE: exceptions, by not having them.** libc++
  asks the compiler whether the language has exceptions, so the macro a
  compiler defines when it supports them is simply not predefined here.
  The library then compiles its own no-exceptions configuration, as it
  ships and as `-fno-exceptions` gives it: `<vector>`'s flattened text
  went from nine `throw` statements and three `try` blocks to none, and
  its throwers abort with a message. That is the honest configuration
  for a compiler whose safe part has no unwinding to offer, and a
  program that writes `throw` or `try` of its own is still refused by
  name. Four defects came out with it: a value bound to a `const`
  reference had no address, where C++ materialises a temporary; the
  compiler builtins libc++ calls are answered as this compiler can,
  `__builtin_is_constant_evaluated` being false since nothing here is
  evaluated at compile time; a variable template written as a type
  inside an expression was never evaluated, so a negated trait came out
  false; and a bool template argument keyed by its spelling, so `true`
  and `1` named two instances of one thing. `std::vector<int> v;
  v.push_back(1);` now reaches `allocator_traits::max_size`. GREEN.
* **The twentieth step DONE: the detection trait, and the allocator
  through.** The trait that decides which `max_size` libc++ uses is a
  variable template of two parameters whose specialization is matched by
  a `decltype` of a member call. It asked four things, each a defect: a
  function template that is declared and never defined must still
  instantiate, because its type is all a `decltype` wants; a member call
  on a type that has members but not that one must refuse, which is the
  rejection a detection needs, and without it the trait was true for
  everything; a member of a reference is a member of what it refers to;
  and a member template's signature is checked in its own class, since
  its parameters are written in that class's words. With the allocation
  operators written out, an empty scoped enum taken as a cast, and a
  functional cast to a class-scope typedef, `allocator<int>` now compiles
  whole. GREEN.
* **The twenty-first step DONE: a library template's instance is lazy.**
  An instance emitted every member function it had, so
  `std::vector<int> v; v.push_back(1);` compiled vector's hundred members
  and stopped at the first one this compiler could not take, reached
  through a `swap` the program never calls. A library header's plain
  class already emitted members only as they were named, and an instance
  of a library template does the same now, which is what the standard
  says a template instantiates. Your own templates stay eager, since
  their instances are your code and the safe part must see all of it. The
  vector program went from 177 instantiations to 83, and the C++ gate's
  peak memory from 855 MB to 615. With it, a nested class sees the
  enclosing class's types including the inherited ones. GREEN.
* **The twenty-second step DONE: an anonymous struct in C++'s own
  shape.** One whose members carry default initializers reaches the
  desugaring as a class and not the plain struct an earlier fixture
  covers, so its members were never flattened into the holder and the
  vector layout's accessor could not find the allocator it returns. Both
  shapes are taken now. With it, each phase of the compile names itself
  when it fails: the desugaring, the check and the lowering ran as one
  conjunction, so any of them merely failing left nothing to report but
  that something had. `std::vector<int> v; v.push_back(1);` now passes
  the desugaring and the safe part whole, and stops in the lowering.
  GREEN.
* **The twenty-third step DONE: what libc++ declares but never defines,
  and the empty class.** A function item with no body is a prototype:
  nothing to define, its declare line coming from the call that names it.
  And `std::declval` is not bodyless after all, since libc++ gives it one
  static assert and no return, so it falls off the end of a function
  returning `allocator<int>` -- an empty class, which had no leaves and
  so classified as a value with no type at all. C++ gives an empty class
  size one and one byte crosses a call, which matters far beyond this
  case: allocators, comparators and tag types are all empty. With them,
  the lowering names the item it cannot take and attaches that item to
  any error raised inside it, which turned an unlocated type error into
  the exact function that raised it. GREEN.
* **The twenty-fourth step DONE: the members libc++ defines out of their
  class.** A class template's member written `template <class T, class A>
  void X<T, A>::f(...) { ... }` after the class -- half of a container's
  members -- was dropped where templates are registered, so the instance
  kept the declaration, the lowering made a prototype of it and the
  linker named four undefined symbols. Every such definition is now kept
  by its class's name, a member template and a constructor and a
  destructor among them, and an instance takes the one whose arguments
  and parameters agree. With it: a temporary called, `__destroy_vector(
  *this)()`, which is how vector destroys itself, the call going inside
  the block that builds the object so it has an address; a scoped enum's
  underlying type, since `enum class C : size_t { }` is libc++'s strong
  typedef for a count and, having no enumerators, had been taken for an
  empty struct; a result type as part of a signature, so the overload
  written to fail for a type that is no enum is no candidate; a
  qualified name inside a nested class, which the reader had read as a
  declaration (the vexing parse, one scope deeper); and a float literal
  past a double, which cocolog writes as an infinity it cannot read back,
  so the AST beside every summary went unread and each run flattened the
  header again. `std::vector<int> v; v.push_back(1); return (int)
  v.size();` reached an object file for the first time on the way through
  this step, and now that the members defined out of their class carry
  their bodies the walk enters them and stops at a free function whose
  overloads must be chosen by their arguments. GREEN.
* **The twenty-fifth step DONE: free function overloads.** C++ tells
  `int f(int)` from `double f(double)` by the arguments and gives each its
  own symbol, where C has one name one function: of libc++'s ten
  `__convert_to_integral` overloads only the first got a body and every
  call went to it, whatever it passed. Each definition of an overloaded
  name now carries its parameters' types in its symbol, as a method
  already did, and every call picks the overload its arguments fit; a name
  with one definition keeps it, so C functions, `main` and everything a
  linker must find by name are untouched. An overload that takes the
  arguments exactly beats any template, as C++ has it, and where no
  template holds the plain overloads are candidates beside them. GREEN.
* **The twenty-sixth step DONE: six defects between the overload set and
  the lambda.** An alias of a class template's instance carries the
  instance, not the name; a library header's free function is emitted
  where it is called, as its classes and templates already were; a tag's
  or a class's name called with more arguments than it can take is no
  temporary, which is what told libc++'s empty `__fill_n` tag from its
  function of the same name once namespaces flatten; a class template
  declared and never defined is an incomplete type a template argument may
  name; a nested class is registered on the first ask, since the enclosing
  class's own registration can reach it; and a static member's type is
  resolved in its class. With them, a call's value bound to a const
  reference gets the temporary C++ materializes for it. GREEN.
* **The twenty-seventh step DONE: a lambda capturing `this`.** Refused by
  name since lambdas were added, and libc++'s `vector::emplace_back` writes
  one. The closure keeps the enclosing object as a reference member, which
  is what a `[&x]` capture already is, and inside its call operator the
  enclosing class is reached through it: a member named bare, a method
  called, a static, and `this` written out. A default capture takes it
  where the body names anything of the class, a member template included.
  The result type is deduced from the first return desugared where the
  lambda stands, since a member has a type only once it is the access the
  desugaring makes of it. GREEN.
* **The twenty-eighth step DONE: `std::vector<int>` compiles.** Eleven
  forms between a free name and the object file: a type the reader cannot
  settle stays `auto`, a typedef in a block is substituted into the lines
  below it, an initializer is walked once, the memory builtins are the C
  library's functions, the bit count and the C++ casts fold, a static const
  named bare folds to its value, a type's name called is one rule for the
  three names a type has, and a prvalue used as a place gets the temporary
  C++ materializes for it. `std::vector<int> v; v.push_back(1); return
  (int) v.size();` now compiles to an object file whose only unresolved
  symbols are malloc, free, memcpy and libc++'s own verbose-abort hook --
  which is C++-mangled in the shipped library, where this compiler emits
  every name unmangled. That mangling is the next step. GREEN.
* **The twenty-ninth step DONE: `std::vector<int>` RUNS.** Four things
  between the object file and a binary that gives C++'s answers.
  **Itanium name mangling** for what a library header only DECLARES: a
  function whose body libc++ ships in its own binary is called by the name
  that binary exports (`_ZNSt3__122__libcpp_verbose_abortEPKcz`) -- the
  namespace path, the length-prefixed name and the parameter codes, with a
  signature whose substitutable components repeat refused rather than
  guessed at. **A reference member is BOUND, never assigned**: `vector`
  destroys itself through a nested class that holds a `vector &`, and
  taken as a member of a class with constructors that became
  `operator=` into an uninitialized reference. **Placement new**, which is
  what `std::__construct_at` is and every container's way of making an
  element: the reader threw the placement arguments away and the
  allocating new it looked like malloc'd a block and dropped it, so a
  vector's size grew and its elements were never stored. And **a cast to a
  reference type is a bind, not a conversion** -- `static_cast<_Tp &&>(__t)`
  is `std::forward`'s whole body, and as a value conversion it loaded the
  int and made a pointer of it. `std::vector<int>` and `std::vector<double>`
  now push, grow, subscript, iterate and destroy, with libc++'s numbers and
  no leaks; `test/cpp/run/stdvector.cpp`. GREEN.
* **The thirtieth step DONE: a vector of the program's own class.** 0.61's
  vector held ints -- scalars, nothing constructed in place and nothing
  destroyed. `std::vector<Name>`, over a class with an `own` pointer, a
  destructor and a move constructor, is where libc++'s container holds
  objects the safe part owns. It asked three things: a **temporary must die
  at the end of its full expression** (on the not-done list since classes
  were added -- a local got the scope's defer and a temporary got nothing,
  so every `v.push_back(Name("a"))` leaked a buffer), while a temporary
  whose value initializes another object is **elided**, as C++17 guarantees,
  since the object it builds is the parameter or the result; a parameter's
  type must be read **through an alias** to see its value category, libc++
  writing `push_back(const_reference)` beside `push_back(value_type &&)`;
  and a **statement expression is a place**, so a reference binds to the
  temporary rather than to a copy of it. With them a vector of the
  program's own objects pushes by move, grows and relocates, subscripts,
  is walked by a range-for and destroys them all -- clang++'s numbers, and
  no leaks. GREEN.
* **The thirty-first step DONE: `std::string` compiles and runs.** The
  short-string optimization is what the type is built on, and what it asked
  for first: **a union with constructors is a class whose members share
  storage** -- it goes a class's whole road while its layout stays a
  union's. Twelve more forms came with it: a nested union as a type, a
  layout over data members alone, a nested type registered on the first
  ask, a class-scope enumerator as a constant of its class, a nested class
  reading its enclosing class's statics, a scoped alias re-entering the
  type hook (`std::string` is `basic_string<char>`), `= default` keeping a
  class default-constructible, a candidate that fits nothing losing to a
  constructor template, a default argument desugared where it is filled in,
  a `const` local standing as a template argument, an explicit template
  argument evaluated where it binds, and libc++'s own forward declaration
  of `char_traits<char>` losing to its definition. A short string in the
  object's own bytes and a long one in a buffer the destructor frees, with
  `size`, `c_str`, `operator[]` and `empty` -- clang++'s numbers, no leaks.
  The mutating operations (`+=`, `push_back`, comparison, copying) do not
  fit in this machine's memory yet: not a runaway, but the accumulation of
  a hundred library instantiations in a host without a collector. GREEN.
* **The thirty-second step DONE: the compile's memory.** The last step read
  `s += "def"` at 2.8 GB as accumulation. Measured, it was a loop: the read
  phase is 48 MB, the desugaring is all of the rest, and the trace at a low
  cap named what was in flight -- an instance keyed by a free name, whose
  substitution turned libc++'s `typedef _Ep value_type` into `typedef
  value_type value_type`, a typedef that is its own definition and was
  followed for ever. Such a typedef is left alone now, and whatever needs
  it refuses by name. With it, an instance asked for again answers its name
  without fetching the template's whole body again -- a retrieval copies
  what it answers, and `allocator_traits` was asked 267 times for one
  program. The desugaring of that line: 2936 MB and 16 s become 495 MB and
  4 s; the string fixture's build 557 -> 422 MB; the C++ gate 1581 -> 752
  MB. GREEN.
* **The thirty-third step DONE: a parameter is read in its own class's
  words.** The last step stopped the loop and left its question: why was
  `initializer_list<value_type>` asked for at all? Because overloads were
  scored at the CALL SITE, where the class context is the caller's or none
  -- and a parameter type is written in its own class's words. libc++ gives
  `basic_string` an `operator+=(initializer_list<value_type>)`, and read in
  `main` that `value_type` resolved to nothing. Scoring now runs inside the
  class, the rule member templates have had since the twentieth step. Not
  one instance keyed by a free name remains. GREEN.
* **The thirty-fourth step DONE: a callable member, and a string that
  grows.** A local of a class with `operator()` has been callable since
  lambdas were added; a member was not, and libc++'s scope guard holds the
  closure it was made with and calls `__func_()` in its destructor -- which
  is how `basic_string` unwinds an append. Five more came with it: a prvalue
  of the class IS the object (C++17's elision), a converting constructor at
  a call, a parameter resolved in its class before it is scored, the same
  type fitting itself, a member initialized from a call taking its class
  from the desugared form, and a default argument kept from the declaration
  where the out-of-class definition may not repeat it. `std::string` now
  appends, pushes back, grows out of its own bytes into a heap buffer and is
  copied -- clang++'s numbers, no leaks. GREEN.
* **The thirty-fifth step DONE: a free operator template of a library
  header.** `s == "abc"` is how a string compares, and libc++ writes it as a
  free function template -- which reached nothing here, since the registry
  held only the operators a program writes out and a header indexes its
  items by a NAME that `operator('==')` did not have. It has one now, by its
  word and arity, so the header indexes and registers it; and at the call
  the operator falls through to the free-function road -- its lazy load, its
  candidates, its deduction -- taken only where the callee comes back
  declared, so a scalar `==` is untouched. With it, the probe this stretch
  began from -- a string constructed, appended to, pushed back on, grown
  into a heap buffer, copied and compared -- matches clang++ line for line.
  GREEN.
* **The thirty-sixth step DONE: an instantiation inside `\+ \+`.**
  `std::vector<std::string>` -- libc++ holding libc++ -- took 2.8 GB and 108
  seconds and was killed. Measured: the read is 102 MB, the desugaring is
  all the rest, and the trace shows 80 distinct instances with nothing asked
  twice -- breadth, not a loop. So an instantiation's whole body now runs
  inside a scope whose intermediates are reclaimed, its results being facts
  and globals that survive; the step before had tried exactly that and
  measured nothing, a conclusion drawn while a loop still dominated and
  corrected here. That program's desugaring: 2824 -> 1091 MB, 108 -> 9 s;
  the C++ gate 1057 -> 847 MB, the libc++ gate 2445 -> 1902. With it, three
  defects the probe turned up: the type an argument has is one rule now (a
  raw `std::move(...)` could not be typed, so every candidate scored alike
  and the first won), the arity-only last resort never picks a class-typed
  parameter for an argument of another class, and an unnamed template
  parameter -- libc++'s SFINAE guard -- no longer takes whatever binding is
  first and names one instance two ways. `vector<string>` still does not
  run: it reaches one named defect now instead of the memory. GREEN.
* **The thirty-seventh step DONE: a name is noted when it is emitted, not
  before.** The last step left `vector<string>` calling a member template
  that was noted as an instance and never emitted. The reason: such an
  instance is made wherever its call is met, and that can be inside another
  candidate's signature check, whose catch rejects the candidate -- SFINAE,
  by design -- while the note taken before the emission survived the
  abandonment. A name is in progress while it is made, which is all a
  recursive ask needs, and noted only once it is done. The same shape sat in
  the lazy emission of a library class's member, which is how
  `basic_string`'s own move constructor was lost. `vector<string>` now
  compiles through the desugaring and the safe part whole and stops in the
  LLVM it emits, two defects further on. GREEN.
* **The fortieth step DONE: the constexpr function, and the road to a
  running `std::cout`.** A constexpr function of one `return` folds where a
  constant is wanted -- its body read back from the emitted instance, its
  parameters bound to the call's, the traits in it constants already -- which
  is how libc++'s `pair` chooses every constructor
  (`__enable_if_t<_CheckArgsDep::template __is_pair_constructible<_U1,
  _U2>(), int>`), and `std::pair<char *, char *> q(p, p)` runs. Followed to
  the link, twenty-three forms of the stream and locale machinery, each
  gated: a lazy polymorphic class emits only what its table names (the hello
  went from 363 instances to 113), the virtual destructor's two slots and
  VIRTUAL INHERITANCE laid out as the ABI lays a complete object (`cout`'s own
  shape), a dispatch through the object's own class's table, a declared-only
  destructor by its Itanium name, a free operator that fits exactly over a
  member's conversion, a class value in a boolean context through its
  `operator bool`, a nested class defined out of its class template, and
  more. `std::cout << "hello"` compiles, passes the safe part, lowers and
  reaches the link FIVE SYMBOLS SHORT -- two members of the nested `sentry`
  defined out of its class template, and three Itanium names the mangler's
  second half must spell (a static member with substitutions, a member of a
  template specialization, an instance noted and not emitted): the next
  stretch, named. GREEN.
* **The thirty-ninth step DONE: the road to `<iostream>`.** The whole
  stream and locale machinery -- 662 items -- read whole after eleven reader
  gaps closed by the census loop (`extern "C++"` transparent where `extern
  "C"` keeps its block, a nested class defined out of its enclosing class,
  the GNU spellings of the keywords, `_BitInt`, and a type template argument
  that names no declarator, which had cost libc++'s `pair` half its
  condition); `std::cout` found in the header and named by the symbol
  libc++ exports, `_ZNSt3__14coutE`; and seven forms of the library's
  locale and iterator machinery desugared, each gated on the program's own
  classes: a nested enum as a type of its class, a nested class declared in
  its holder and defined out of it, multiple inheritance where the extra
  bases are empty (a scope, no sub-object), a pure virtual slot's null in
  the table, a base constructor's default argument from a derived class's
  initializer list, the implicit default constructor C++ deletes, an alias
  named as a base. `std::cout << "hello"` goes 236 loads and instances deep
  -- `basic_ostream`, `basic_ios`, `basic_streambuf`, `locale::facet`,
  `ctype<char>`, `std::copy` -- and stops at `std::pair`'s constructors,
  which ask a constexpr static member function template to be evaluated at
  compile time: the next stretch, named. GREEN.
* **The thirty-eighth step DONE: a vector of strings.** libc++ holding
  libc++ -- each element owning a heap buffer of its own, constructed in the
  container's raw memory, relocated when it grows and destroyed with it. Two
  rules, both about reading a parameter for what it is: a member
  initializer's overload choice reads its parameter in its own class's words
  (libc++'s union-class names its holder's nested types, so a clash went
  unseen and a union was stored into a byte), and a converting constructor
  serves a parameter that binds a temporary -- a const reference or an
  rvalue one -- template constructors included, which is the whole of how
  `v.push_back("alpha")` makes a string out of a `const char *`. Four
  strings, one past the short-string bytes, the buffer grown twice and the
  strings relocated, walked by a range-for: clang++'s numbers, no leaks.
  GREEN.
* **C23 DONE (`-std=c23`).** C's own level, which is not C++'s: the
  preprocessor answers `__STDC_VERSION__` 202311L there, and the forms the
  level added are read -- `bool`, `true`, `false` and `nullptr` as the
  language's own, `constexpr` objects whose value folds where an array's
  bound or a static assertion needs it, `enum E : unsigned char`,
  `[[attributes]]`, `typeof` (resolved at last, by any pass), `auto`
  deducing, and `static_assert` with or without a message, checked in C
  where it folds. Both lexers read `0b1011` and the digit separator
  `1'000'000`, the preprocessor's pp-number included. GREEN.
* **M5 -- the preprocessor, in cocolog.** No clang, no LLVM binary
  anywhere (owner's rule): a header the raw reader cannot take goes
  through `library(ccl_pp)` -- directives, conditional groups, macro
  expansion with `#`, `##` and `__VA_ARGS__`, `#include_next`, the
  built-ins, the target's predefined macros as data -- and the inclusion
  path comes from the SDK's and LLVM's conventional places. `<stdio.h>`'s
  closure of 38 files in two seconds, the declarations the same as
  clang's; GREEN in every gate, `test/c/run/pp.c` the proof. The user's
  own file goes through it as well: its conditional groups decided, its
  macros and the headers' expanded, a header's macro table kept beside
  its unit in the store; `test/c/run/macros.c` the proof.
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
the lowering of the C++ forms are M6, in steps: the first, the forms that
are C with names (namespaces, `extern "C"`, references, `bool`, `nullptr`,
the casts, `enum class`, range-for, `new` and `delete`), the second,
classes, the third, `virtual`, the fourth, templates, the fifth,
lambdas, and, over classes of the program's own, overloads, moves and
members of class type, build and run; `try` is refused by its name, and
so is a template of libc++'s, whose body a summary does not carry: the
standard library is libc++'s, C++17 the baseline and the next majors
after, and compiling it as it is is the road ahead. What is read, each
with its AST node:

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
| `x.~T()`, `p->~T()` | `call(member(x, dtor(T)), [])`, `call(arrow(p, dtor(T)), [])` |
| `template <typename T> concept C = E;`, `template <typename T> requires C<T> ...` | `template(L, Ps, concept(L, C, E))`, `template(L, [tparam(...), requires(tmpl(C, [T]))], Item)` |
| `requires (T a) { a + a; { a < a } -> Boolean; typename T::x; requires C<T>; }` | `requires_expr(Params, [expr(E), compound(E, C), type(T), nested(E)])` |
| `a <=> b`, `co_return e`, `co_await e`, `co_yield e` | `bin('<=>', a, b)`, `co_return(L, E)`, `co_await(E)`, `co_yield(E)` |
| `using enum E;`, `for (init; x : xs)`, `if constexpr (c) a else b`, `auto f(auto x)`, `[]<typename T>(T x) {}` | `using(L, enum(E))`, `block([Init, for_each(...)])`, `if_constexpr(L, C, T, E)`, `param(base([], [auto]), x)`, `lambda([tparams(Ps)|Caps], ...)` |
| `if consteval { } else { }`, `int f(this const C &self)`, `a[i, j]` (at `-std=c++23`), `auto(x)`, `[] mutable -> int { }`, `if (using T = long; c)`, `{ s; done: }`, `4uz`, `"\x{41}\u{43}"` | `if_consteval(L, no, T, E)`, `param(this(T), self)` first, `index(a, args([i, j]))`, `decay_copy(x)`, `lambda([], [], T, B)`, `block([typedef(L, [var('T', long, none)]), if(...)])`, `label(L, done, empty)`, `ulong(4)`, `str("AC")` -- C++23 |
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

## C++17, C++20 and C++23

`cicili++` compiles C++ against libc++ as the system ships it, never
against a standard library of its own: the compiler's own headers are the
C freestanding ones (`stddef.h` and kin), and nothing of `std` is written
here. **C++17 is the baseline** -- what a program gets without a flag --
and `-std=c++20` (and `-std=c++23`, `-std=c++26`) selects the level:
the preprocessor answers that level's predefined macros first,
`__cplusplus` and the `__cpp_*` feature tests, taken once from the
reference compiler at each level, and these are what libc++'s headers key
on, so `<vector>` flattens as clang would flatten it for the level asked;
a header's summary is one level's. Older standards are refused as
unsupported.

What is read and what compiles, by level. **C++17**: the forms of the
M5 table and the M6 steps above -- classes with `virtual`, templates
instantiated on use, lambdas, `if constexpr`, `auto`, range-for,
`nullptr`, references, `enum class`, `new` and `delete` (the constructor
after the allocation, the destructor before the free) under the
ownership check. **C++20**: `concept` and `requires`
read, a concept checked where a template is instantiated (its
requirements type-check under its parameters, or the instantiation is
refused by the concept's name); `<=>` (an int on scalars); abbreviated
function templates (`auto` parameters as invented template parameters);
`consteval` and `constinit` (read; `consteval` runs at run time like
`constexpr`); `char8_t`; `using enum`; a range-for with an initializer;
designated initializers; `[[likely]]`; template lambdas and coroutines
read and refused by name; modules not read. **C++23**: `if consteval`
(the run-time branch runs); an explicit object parameter, `this Self
&self`, on a method and on a lambda (a recursive lambda through `this
auto self`; `this auto` on a class's method, a member template, is
refused by name); the multidimensional subscript `a[i, j]` to the
class's `operator[]`; `auto(x)` and `auto{x}`; a lambda's specifiers
without parentheses, a static lambda; an alias in an init-statement; a
label ending a block; the size suffix `4uz`; the escapes `\x{…}`,
`\o{…}`, `\u{…}` and the universal character names, into a string as
UTF-8; `#elifdef`, `#elifndef`; `static operator()`. Not yet: `\N{…}`,
the extended floating-point suffixes, `[[assume]]` told to LLVM.
**C++26**: its macros, so libc++ takes its paths, its forms still to
come. The library itself: the reader reads `<vector>`, `<string>` and `<iostream>`
whole, the desugaring registers a flattened header's items by name
as a program asks for them, and `std::vector<int>` gets several
classes deep before the next forms stop it -- under an instantiation
budget, since one unbounded run took a machine's memory. `cicili++
-E f.cpp -o flat.cpp` is clang's flag, the flattened text from
cocolog's preprocessor; `sh test/census.sh flat.cpp` says where the
reader stops in it and counts its constructs; `sh test/libcxx.sh` is
the gate. libc++'s containers themselves await the forms their bodies
use -- allocators,
`enable_if` and partial specializations, `constexpr` and `noexcept`
everywhere, rvalue-reference overloads by value category, exceptions --
which is the road the C++ side is on.

**Where cocolog's macros go past C++'s templates.** A template computes
with types by substitution and nothing else; a macro file
(`#include "m.pl"`, `#cocolog … #end`, below) is a Prolog program that
runs at parse time over the program's syntax tree. **A macro sees and
rewrites the AST itself** -- any expression, statement or declaration,
not a type -- where a template sees only the types and constants it is
given. **A
macro reads the symbol table as it stands**: `ccl_type_of/2`, the
typedefs, the tags, `ccl_size_of/2`, the LP64 layout of a struct, at the
point of the call. **A macro produces statements and declarations**, a
whole block spliced in place, a function at file scope, where a template
produces one entity of one kind. **A macro is variadic by grammar** (a
DCG rule takes the list it parses) with no parameter packs to fold. **A
macro fails with a message naming both places**, the call and the macro,
where a template's failure is a page of instantiation context. **A macro
is ordinary code in a logic language** -- pattern matching on any
construct, backtracking search over the program, the same language the
compiler is written in -- where template metaprogramming is a functional
language by accident, without loops, mutable state or strings. **And a
macro runs before the check**, so what it generates is checked by the
same ownership rules as what the programmer wrote. `format`, `print`,
`println` and `clone` are such macros, in the library.

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
**The user's own file goes through the same preprocessor first:** its
conditional groups are decided, its macros and the headers' (`NULL`,
`EOF`, `INT_MAX`, `stdin`, `__LP64__`, `__LINE__` ...) expanded, while its
`#define`, `#undef` and `#include` lines still come out as items, so a
macro file and a `#cocolog` block are read as before. A header's macro
table is kept in the store beside its unit (beside its summary, in C++),
made once by one run of the preprocessor over the header, and asked by
name: `<stdio.h>` brings 1200 macros and a file uses a dozen, so none is
parsed before it is named. `_FORTIFY_SOURCE` is 0: `strcpy` stays a
function.
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

A `#define` or `#undef` line is done and kept whole as `directive(Line,
Text)`, and a typedef name from a header the reader has not seen is
recognised from the tokens around it (`name x;`, `name *p;` where an
expression cannot stand, `(name *)`, `(name){`). What it reads is C11 plus
the GNU and Apple forms system headers and Cicili's emitted C carry
(`__attribute__`, `__asm`, `typeof`, `({ ... })`, `_Nonnull`, `(^block)`),
and the C++ forms in `cicili++`'s mode (below); `cicili_ast/3` says where
a file stopped.

## Macros: `#include "m.pl"`

A Prolog file is included the way a header is, and **every predicate it
defines is a macro function over ASTs** (what that gives beyond C++'s
templates is set out under C++17, C++20 and C++23, above): a call `name(a, b)`
in the C source, with `name/3` among them, runs at parse time as
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
| `cicili++`, the first run (init phase) | 3.1 | | 8.3 | | | |
| `cicili++`, after it | 0.73 | 0.74 | 1.40 | 1.50 | 1.11 | 0.76 |
| `clang++` | 0.96 | 1.01 | 1.04 | 1.14 | 0.39 | 0.37 |
| `rustc` | 0.45 | 0.46 | 0.54 | 0.71 | 0.29 | |

`rustc` is the fastest on both programs; `cicili++` after its init phase
builds the hello faster than `clang++` and takes 1.35 times `clang++` on
the B-tree (the run of 2026-09-06 night, `cicili-lang` 0.31, the user's
file through the preprocessor: 0.09 s of the read). For scale, a compiler written in another interpreted
language: the script also runs the Python ones this Mac can, when `PY`
names a python3 with them installed. `pycparser`, the C parser in Python
(a parser only, `clang -E` over its fake headers inside), reads the hello
in 0.29 s and the B-tree in 0.31 s where `cicili++ -fsyntax-only` takes
0.53 s and 0.76 s -- with the check, the C++ headers' summaries, the
preprocessing and cocolog's start in those. ShivyC, a C compiler in Python to x86-64
assembly, refuses macOS and takes a small subset of C (no `enum`, no
`?:`, no `sizeof` of a type, no variadic prototype: the B-tree does not
compile); its front end driven to assembly past the check turns the
hello in 3 ms, plus 0.08 s to start Python, where `cicili++ -S` takes
0.58 s. Where `cicili++`'s time goes, measured piece by piece: cocolog
starts in 0.06 s and the library's clauses load in 0.03 s; the command's
shell is a floor of its own, a fork per `$(...)` and per pipe, so
`bin/cicili` forks six times where it forked twenty; a header's summary
is parsed in 30 ms; the raw parse of the 170 lines takes 0.1 s (the
lexer, since it went native, 20 ms; the parser one look per token); the
check 0.07 s and the lowering 0.17 s (the walk of every statement and
the emission, at cocolog's 5 µs a call), the embedded LLVM
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
within its noise) and the check's walk (its rebuild of the symbol table
added a summary's names one at a time, each a copy of the environment:
17 ms to 5; the anchor walk asks the scope only of the names declared
as arrays; the walk's clauses ordered by what a node most often is, a
name, an operator, a member, an index, a wrapper, none of them through a
univ; 86 ms to 65, the rest twenty thousand small calls) -- and the
B-tree's build went from 3.64 to 1.35 s, `test/compile.sh`'s eighteen
programs and forty refusals from 37 to 25 s. Then the user's file went
through the preprocessor too, which cost 0.27 s a read done the plain
way -- every header's 1200 macros defined into the run, the 580
predefined ones with them -- and 0.09 s done by name: a table asked on
a name's first use, a miss remembered, the predefined ones facts looked
up by name, a plain decimal taken without the lexer. What is left is the
two walks, the check's and the lowering's, at cocolog's 5 µs a call.

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
                         files, the knowledge-base cache, the headers' macro tables by name
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
