%% cicili-lang -- the C++ reader's gate (M5, cicili++), as a cocolog program:
%% one process over the C++ knowledge base, every check a goal over the AST of
%% a sample in test/cpp/. Run by test/cpp.sh, which adds the command's checks.
%%
%%   CCL_TEST_ROOT=<this repo> cocolog --embed <the store> query "ensure_loaded('test/cpp.pl'), cpp_main"

:- use_module(library(cicili)).
:- use_module(library(os)).
:- use_module(library(process)).

cpp_main :-
    setup,
    c_checks, c_real,
    nb_getval('$t_fails', N),
    ( N =:= 0 -> write('GREEN: cicili++ (one process)') ; write('RED: '), write(N), write(' failure(s)') ), nl.

setup :-
    nb_setval('$t_fails', 0), nb_setval('$t_err', none),
    os_env('CCL_TEST_ROOT', Root), atom_concat(Root, '/test/cpp/', C), nb_setval('$t_cdir', C).

section(S) :- write('-- '), write(S), nl.
check(Name, Goal) :-
    nb_setval('$t_err', none),
    (   catch(Goal, E, (nb_setval('$t_err', E), fail))
    ->  write('ok   '), write(Name), nl
    ;   nb_getval('$t_fails', N), N1 is N + 1, nb_setval('$t_fails', N1),
        write('FAIL '), write(Name), nl,
        ( nb_getval('$t_err', E), E \== none -> write('     error '), write(E), nl ; true ) ).
c(Name, Path) :- nb_getval('$t_cdir', C), atom_concat(C, Name, Path).
unit(Name, U) :-
    c(Name, P), atom_concat('$t_unit:', P, K),
    (   once(catch(nb_getval(K, U0), _, fail)) -> U = U0
    ;   cicili_ast(P, U0), nb_setval(K, U0), U = U0 ).
fn_body(Name, F, B) :- unit(Name, unit(Is)), member(function(_, _, _, F, _, _, block(B)), Is).
%% a term anywhere inside another (a class's members, a block's items)
in(T, T).
in(T, X) :- compound(X), X =.. [_|As], member(A, As), in(T, A).

%% ---- the checks: each its own clause ---------------------------------------------------
c_checks :-
    section('names: namespaces, using, qualified names, extern C, bool, nullptr, references, auto'),
    c1, c2, c3, c4, c5, c6,
    section('classes: access, members, constructors, destructors, inheritance, this, new, operators, defaults'),
    c7, c8, c9, c10, c11,
    section('templates: functions, classes, template-id types, explicit arguments, aliases'),
    c12, c13, c14, c15, c16,
    section('statements and expressions: range-for, try/catch/throw, lambdas, enum class, casts'),
    c17, c18, c19, c20, c21,
    section('C++20: concepts and requires, <=>, consteval and constinit, char8_t, coroutines read, using enum, for with an initializer, designated initializers, an abbreviated template, a template lambda, if constexpr'),
    c22, c23, c24, c25, c26, c27, c28.

c1 :- check('namespace N { ... } is namespace(L, N, Items), nested, and anonymous',
    ( unit('names.cpp', unit(Is)), member(namespace(2, geo, Gs), Is), member(function(_, _, _, twice, _, _, _), Gs), member(namespace(_, inner, _), Gs), member(namespace(_, anon, _), Is) )).
c2 :- check('using namespace, using a name, using T = type (an alias is a typedef)',
    ( unit('names.cpp', unit(Is)), member(using(_, namespace(geo)), Is), member(using(_, name(scoped([geo], twice))), Is), member(typedef(_, [var(count_t, base([], [unsigned, long]), none)]), Is) )).
c3 :- check('extern C { ... } and extern C decl are extern_c(L, Items)',
    ( unit('names.cpp', unit(Is)), member(extern_c(_, [declaration(_, _, _, [var(c_add, fn(_, _, _), none)]), declaration(_, _, _, [var(c_hook, _, none)])]), Is), member(extern_c(_, [function(_, _, _, c_one, _, _, _)]), Is) )).
c4 :- check('bool, true, false and nullptr',
    ( unit('names.cpp', unit(Is)), member(declaration(_, _, _, [var(flag, base([], [bool]), bool(true))]), Is), member(declaration(_, _, _, [var(none, ptr([], base([], [int])), nullptr)]), Is) )).
c5 :- check('references: T &x is ref(Q, T), T &&x is rref(Q, T), a qualified type name is scoped(Path, N), a template-id in it tmpl(N, Args)',
    ( unit('names.cpp', unit(Is)), member(function(_, _, ref([], base([], [int])), alias, [param(ref([], base([], [int])), x)], false, _), Is),
      member(declaration(_, _, _, [var(take, fn(_, [param(ref([], base([const], [typedef(scoped([geo, inner], what))])), w), param(rref([], base([], [int])), r)], false), none)]), Is) )).
c6 :- check('geo::twice(3) + ::g + inner::one, !false, auto z = y + 1 inferred, int &r = y',
    ( fn_body('names.cpp', main, B),
      member(declaration(_, _, _, [var(y, _, bin('+', bin('+', call(scoped([geo], twice), [int(3)]), scoped([global], g)), scoped([inner], one)))]), B),
      member(declaration(_, _, _, [var(ok, base([], [bool]), not(bool(false)))]), B),
      member(declaration(_, _, _, [var(z, base([], [int]), bin('+', id(y), int(1)))]), B),
      member(declaration(_, _, _, [var(r, ref([], base([], [int])), id(y))]), B) )).
c7 :- check('struct Shape: fields, a constructor with its initializers, a virtual const method, a prototype, a virtual destructor, this->w',
    ( unit('classes.cpp', unit(Is)), member(declare(_, base([], [class(struct, 'Shape', [], Ms)])), Is),
      member(member(base([], [double]), w, none), Ms), member(member(base([], [double]), h, none), Ms),
      member(ctor(_, [], [param(_, w0), param(_, h0)], [init(w, [id(w0)]), init(h, [id(h0)])], block([])), Ms),
      member(method(_, [virtual, const], base([], [double]), area, [], false, block([return(_, bin('*', arrow(this, w), arrow(this, h)))])), Ms),
      member(method(_, [virtual], base([], [void]), scale, [param(base([], [double]), by)], false, none), Ms),
      member(dtor(_, [virtual], block([])), Ms) )).
c8 :- check('struct Square : public Shape, a base initializer, override',
    ( unit('classes.cpp', unit(Is)), member(declare(_, base([], [class(struct, 'Square', [base(public, 'Shape')], Ms)])), Is),
      member(ctor(_, [], [param(_, side)], [init('Shape', [id(side), id(side)])], block([])), Ms), member(method(_, [const, override], _, area, [], false, _), Ms) )).
c9 :- check('class Counter: access labels, explicit, a default argument, a static member, operator+= and operator[], a default member initializer',
    ( unit('classes.cpp', unit(Is)), member(declare(_, base([], [class(class, 'Counter', [], Ms)])), Is),
      member(access(public), Ms), member(access(private), Ms),
      member(ctor(_, [], [], [init(n, [int(0)])], _), Ms), member(ctor(_, [explicit], [param(_, start)], _, _), Ms), member(dtor(_, [], none), Ms),
      member(method(_, [const], base([], [int]), get, [], false, _), Ms), member(method(_, [], _, add, [param(base([], [int]), k, int(1))], false, _), Ms),
      member(member(base([static], [int]), made, none), Ms),
      member(method(_, [], ref([], base([], [typedef('Counter')])), operator('+='), [param(_, k)], false, _), Ms), member(method(_, [const], _, operator('[]'), [param(_, i)], false, _), Ms),
      member(member(_, limit, none), Ms), member(default_init(limit, int(100)), Ms) )).
c10 :- check('out of the class: Counter::made, Counter::~Counter, Shape::scale, and a free operator+',
    ( unit('classes.cpp', unit(Is)), member(declaration(_, _, _, [var(scoped(['Counter'], made), base([], [int]), int(0))]), Is),
      member(dtor_def(_, 'Counter', [], block(_)), Is), member(function(_, _, base([], [void]), scoped(['Shape'], scale), [param(_, by)], false, _), Is),
      member(function(_, _, base([], [typedef('Counter')]), operator('+'), [param(ref([], base([const], [typedef('Counter')])), a), param(_, b)], false, _), Is) )).
c11 :- check('Shape s(2, 3), Square q{4}, new Square(5), new int[8], delete p, delete[] xs',
    ( fn_body('classes.cpp', main, B),
      member(declaration(_, _, _, [var(s, base([], [typedef('Shape')]), ctor([int(2), int(3)]))]), B),
      member(declaration(_, _, _, [var(q, base([], [typedef('Square')]), init([item([], int(4))]))]), B),
      member(declaration(_, _, _, [var(p, ptr([], base([], [typedef('Shape')])), new(base([], [typedef('Square')]), [int(5)]))]), B),
      member(declaration(_, _, _, [var(xs, ptr([], base([], [int])), new_array(base([], [int]), int(8)))]), B),
      member(expr(_, delete(id(p))), B), member(expr(_, delete_array(id(xs))), B) )).
c12 :- check('template <typename T> T max2(T a, T b): template(L, [tparam(type, T, none)], function), T a type inside',
    ( unit('templates.cpp', unit(Is)), member(template(_, [tparam(type, 'T', none)], function(_, _, base([], [typedef('T')]), max2, [param(base([], [typedef('T')]), a), param(_, b)], false, _)), Is) )).
c13 :- check('template <typename T, int N> struct Buf { T d[N]; ... }: a non-type parameter, the class in the template',
    ( unit('templates.cpp', unit(Is)), member(template(_, [tparam(type, 'T', none), tparam(base([], [int]), 'N', none)], declare(_, base([], [class(struct, 'Buf', [], Ms)]))), Is),
      member(member(arr(id('N'), base([], [typedef('T')])), d, none), Ms), member(method(_, [const], base([], [int]), size, [], false, _), Ms) )).
c14 :- check('a defaulted type parameter, and using Ints = Buf<int, 8> is a typedef of a template-id',
    ( unit('templates.cpp', unit(Is)), member(template(_, [tparam(type, 'K', none), tparam(type, 'V', base([], [int]))], declare(_, base([], [class(class, 'Map', [], _)]))), Is),
      member(typedef(_, [var('Ints', base([], [typedef(tmpl('Buf', [base([], [int]), int(8)]))]), none)]), Is) )).
c15 :- check('a template inside a namespace (a struct of fields alone stays C''s struct)',
    ( unit('templates.cpp', unit(Is)), member(namespace(_, std, Ss), Is), member(template(_, _, declare(_, base([], [struct(vector, [member(_, p, none), member(_, n, none)])]))), Ss) )).
c16 :- check('Buf<int, 4> b, Map<char> m, std::vector<int> v, std::vector<std::vector<int>> vv, Ints buf8, max2<int>(1, 2)',
    ( fn_body('templates.cpp', main, B),
      member(declaration(_, _, _, [var(b, base([], [typedef(tmpl('Buf', [base([], [int]), int(4)]))]), none)]), B),
      member(declaration(_, _, _, [var(m, base([], [typedef(tmpl('Map', [base([], [char])]))]), none)]), B),
      member(declaration(_, _, _, [var(v, base([], [typedef(scoped([std], tmpl(vector, [base([], [int])])))]), none)]), B),
      member(declaration(_, _, _, [var(vv, base([], [typedef(VV)]), none)]), B), VV = scoped([std], tmpl(vector, [Inner])),
      Inner = base([], [typedef(scoped([std], tmpl(vector, [base([], [int])])))]),
      member(declaration(_, _, _, [var(buf8, base([], [typedef('Ints')]), none)]), B),
      member(declaration(_, _, _, [var(x, _, call(tmpl(max2, [base([], [int])]), [int(1), int(2)]))]), B),
      member(declaration(_, _, _, [var(y, _, call(id(max2), [int(3), int(4)]))]), B) )).
c17 :- check('enum class Color : int { Red, Green = 3 }',
    ( unit('control.cpp', unit(Is)), member(declare(_, base([], [enum_class('Color', [enumerator('Red', none), enumerator('Green', int(3))])])), Is) )).
c18 :- check('for (int x : xs) and for (auto &x : xs) are for_each(L, Decl, Range, S)',
    ( fn_body('control.cpp', main, B), member(for_each(_, var(x, base([], [int]), none), id(xs), expr(_, assign('+=', id(t), id(x)))), B),
      member(for_each(_, var(x, ref([], base([], [auto])), none), id(xs), _), B) )).
c19 :- check('lambdas: [](int a, int b) { ... }, [k, &t](int a) mutable -> int, [=], [&]',
    ( fn_body('control.cpp', main, B),
      member(declaration(_, _, _, [var(add, base([], [auto]), lambda([], [param(base([], [int]), a), param(_, b)], none, block([return(_, bin('+', id(a), id(b)))])))]), B),
      member(declaration(_, _, _, [var(addk, _, lambda([cap(val, k), cap(ref, t)], [param(_, a)], base([], [int]), _))]), B),
      member(declaration(_, _, _, [var(all, _, lambda([cap(default, '=')], [], none, _))]), B),
      member(declaration(_, _, _, [var(refs, _, lambda([cap(default, '&')], [], none, _))]), B) )).
c20 :- check('try { ... } catch (Err e) { ... } catch (...) { ... }, throw Err{t}, throw 3',
    ( fn_body('control.cpp', main, B), member(try(_, block(Ts), [catch(param(base([], [typedef('Err')]), e), block(_)), catch(any, block(_))]), B),
      member(if(_, _, expr(_, throw(call(id('Err'), [id(t)]))), none), Ts), member(expr(_, throw(int(3))), Ts) )).
c21 :- check('Color::Green, static_cast<long>(t), unsigned(k)',
    ( fn_body('control.cpp', main, B), member(declaration(_, _, _, [var(c, base([], [typedef('Color')]), scoped(['Color'], 'Green'))]), B),
      member(declaration(_, _, _, [var(big, base([], [long]), ccast(static, base([], [long]), id(t)))]), B),
      member(declaration(_, _, _, [var(u, base([], [unsigned]), ccast(functional, base([], [unsigned]), id(k)))]), B) )).

c22 :- check('template <typename T> concept Number = requires (T a, T b) { a + b; { a < b } -> Boolean; }: a concept item under its template, its requires-expression',
    ( unit('cxx20.cpp', unit(Is)), member(template(_, [tparam(type, 'T', none)], concept(_, 'Number', requires_expr([param(_, a), param(_, b)], Rs))), Is),
      member(expr(bin('+', id(a), id(b))), Rs), member(compound(bin('<', id(a), id(b)), id('Boolean')), Rs),
      member(template(_, _, concept(_, 'Boolean', requires_expr([param(_, x)], [expr(not(id(x)))]))), Is) )).
c23 :- check('template <typename T> requires Number<T> T twice(T x): the requires-clause kept with the parameters',
    ( unit('cxx20.cpp', unit(Is)), member(template(_, [tparam(type, 'T', none), requires(tmpl('Number', [id('T')]))], function(_, _, _, twice, _, _, _)), Is) )).
c24 :- check('(a <=> b) < 0: the three-way comparison, below the relational; consteval, constinit and char8_t are specifiers',
    ( fn_body('cxx20.cpp', order, [return(_, cond(bin('<', bin('<=>', id(a), id(b)), int(0)), _, _))]),
      unit('cxx20.cpp', unit(Is)), member(function(_, _, base([consteval], [int]), cube, _, _, _), Is),
      member(declaration(_, _, base([constinit], [int]), [var(limit, _, int(100))]), Is), member(declaration(_, _, base([], [char8_t]), [var(glyph, _, _)]), Is) )).
c25 :- check('co_return is read as co_return(L, E), to be refused by name',
    ( fn_body('cxx20.cpp', count, [co_return(_, none)]) )).
c26 :- check('using enum Mode; for (int k = 2; int x : xs) is a block of the initializer and the range-for; Point p = { .x = 3, .y = 4 }',
    ( fn_body('cxx20.cpp', main, B), member(using(_, enum('Mode')), B),
      member(block([declaration(_, _, _, [var(k, _, int(2))]), for_each(_, var(x, base([], [int]), none), id(xs), _)]), B),
      member(declaration(_, _, _, [var(p, _, init([item([field(x)], int(3)), item([field(y)], int(4))]))]), B) )).
c27 :- check('auto add(auto a, auto b) is a function with auto parameters (an abbreviated template); []<typename T>(T a, T b) a lambda with its parameters among the captures',
    ( unit('cxx20.cpp', unit(Is)), member(function(_, _, base([], [auto]), add, [param(base([], [auto]), a), param(base([], [auto]), b)], _, _), Is),
      fn_body('cxx20.cpp', main, B), member(declaration(_, _, _, [var(pick, _, lambda([tparams([tparam(type, 'T', none)])], [param(_, a), param(_, b)], none, _))]), B) )).
c28 :- check('if constexpr (sizeof(int) == 4) is if_constexpr(L, C, T, E); [[likely]] before a statement is dropped',
    ( fn_body('cxx20.cpp', main, B), member(if_constexpr(_, bin('==', sizeof_type(base([], [int])), int(4)), _, _), B), member(if(_, bin('>', id(t), int(0)), _, none), B) )).

%% ---- real C++ from the neighbours: Cicili's emitted C++, read entirely ----------------------
c_real :-
    section('real C++ from the neighbours, read entirely'),
    os_env('CICILI', Cicili),
    real_file(Cicili, 'test/cpp/objects.cpp'), real_file(Cicili, 'test/cpp/emit_report.cpp'),
    real_file(Cicili, 'test/cpp/specialise.cpp'), real_file(Cicili, 'test/cpp/syntax.cpp'),
    real_file(Cicili, 'test/cpp/torch.cpp'), real_file(Cicili, 'test/cpp/torch-fragment.cpp').
real_file(Cicili, Rel) :-
    atomic_list_concat([Cicili, '/', Rel], P),
    (   exists_file(P)
    ->  check(Rel, ( cicili_ast(P, unit(_), Rest), ( Rest == [] -> true ; Rest = [tok(_, _, L)|_], ccl_farthest(F), write('     stopped at '), write(L), write(' near '), write(F), nl, fail ) ))
    ;   write('SKIP '), write(Rel), write(' (not here)'), nl ).
