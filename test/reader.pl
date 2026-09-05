%% cicili-lang -- the reader's gate, as a cocolog program: one process, every
%% header parsed once, every check a Prolog goal over the AST. Run by
%% test/reader.sh, which sets CCL_TEST_ROOT and CICILI and adds, in the
%% shell, the checks that need a second process (the knowledge base as the
%% cache). Each check prints `ok   Name' or `FAIL Name'; the last line is
%% GREEN or RED.
%%
%%   CCL_TEST_ROOT=<this repo> cocolog --embed <the store> query "ensure_loaded('test/reader.pl'), reader_main"
%% (never `run test/reader.pl main': under a store, `run' consults the program into it)

:- use_module(library(cicili)).
:- use_module(library(os)).
:- use_module(library(process)).

reader_main :-
    setup,
    t_checks, t_real,
    nb_getval('$t_fails', N),
    ( N =:= 0 -> write('GREEN: reader (one process)') ; write('RED: '), write(N), write(' failure(s)') ), nl.

%% setup/0 alone, then one check by name, runs it on its own:
%%   cocolog --local query "ensure_loaded('test/reader.pl'), setup, k72"
setup :-
    nb_setval('$t_fails', 0), nb_setval('$t_err', none),
    os_env('CCL_TEST_ROOT', Root), atom_concat(Root, '/test/c/', C), nb_setval('$t_cdir', C),
    ( once(catch(os_env('CCL_TEST_TMP', T), _, fail)), T \== '' -> true ; T = '/tmp/cicili-reader-scratch', sh(mkdir, ['-p', T]) ),
    nb_setval('$t_tmp', T).

%% ---- the harness ------------------------------------------------------------
section(S) :- write('-- '), write(S), nl.
check(Name, Goal) :-
    nb_setval('$t_err', none),
    (   catch(Goal, E, (nb_setval('$t_err', E), fail))
    ->  write('ok   '), write(Name), nl
    ;   nb_getval('$t_fails', N), N1 is N + 1, nb_setval('$t_fails', N1),
        write('FAIL '), write(Name), nl,
        ( nb_getval('$t_err', E), E \== none -> write('     error '), write(E), nl ; true ) ).
c(Name, Path) :- nb_getval('$t_cdir', C), atom_concat(C, Name, Path).
tmp(D) :- nb_getval('$t_tmp', D).                       % the wrapper's scratch directory, writable
%% a copy of a fixture, and a touch a second later (time_file/2 is whole seconds)
copy(From, To) :- sh(cp, [From, To]).
touch(F) :- proc_sleep(1100), sh(touch, [F]).
sh(Cmd, Args) :- sh_line([Cmd|Args], Line), once(catch(proc_run(Line, 20000, _, 0), _, fail)).
sh_line([], '').
sh_line([A|As], L) :- sh_line(As, L0), atomic_list_concat(['\'', A, '\' ', L0], L).
%% a sample's unit, read once per process
unit(Name, U) :-
    c(Name, P), atom_concat('$t_unit:', P, K),
    (   once(catch(nb_getval(K, U0), _, fail)) -> U = U0
    ;   cicili_ast(P, U0), nb_setval(K, U0), U = U0 ).
fn_body(Name, F, B) :- unit(Name, unit(Is)), member(function(_, _, _, F, _, _, block(B)), Is).
codes_atom(S, A) :- atom_codes(A, S).

%% ---- the checks --------------------------------------------------------------
%% EACH CHECK IS ITS OWN CLAUSE, so its variables are its own: two checks in
%% one clause would share a variable of the same name, and the second would
%% have to unify one file's AST with the first's. (Clauses, not facts driven
%% by findall/3: consulting 71 goal-carrying facts into an embedded store
%% segfaults cocolog.)

k1 :- check('cicili_ast/2 reads the file and answers a unit of 3 items',
    ( unit('hello.c', unit(Is)), length(Is, 3) )).

k2 :- check('a directive that is not an include is kept whole',
    ( unit('rich.c', unit(Is)), member(directive(5, '#define LIMIT 10'), Is) )).

k3 :- check('main is a function at its line, returning int, taking void',
    ( unit('hello.c', unit(Is)), member(function(5, none, base([], [int]), main, [], false, _), Is) )).

k4 :- check('its body: a call with a string (10 codes, ending in newline), then return 0',
    ( fn_body('hello.c', main, [expr(6, call(id(printf), [str(S), _])), return(7, int(0))]), length(S, 10), last(S, 10) )).

k5 :- check('cicili_ast/3 leaves nothing when the whole file parses',
    ( c('hello.c', P), cicili_ast(P, _, []) )).

k6 :- check('<stdio.h> resolves to a file on the toolchain\'s path and is read',
    ( unit('hello.c', unit([include(2, system('stdio.h'), file(P, How, unit(_)))|_])), sub_atom(P, _, _, 0, '/stdio.h'), memberchk(How, [raw, preprocessed]) )).

k7 :- check('and printf is declared somewhere under it',
    ( unit('hello.c', U), ccl_declares(U, printf, I), functor(I, declaration, _) )).

k8 :- check('and malloc under <stdlib.h>, as a function returning a pointer',
    ( unit('hello.c', U), ccl_declares(U, malloc, declaration(_, _, _, [var(malloc, fn(ptr(_, _), _, _), _)])) )).

k9 :- check('a quoted include is found beside the file and read raw',
    ( c('local.h', LH), unit('uses.c', unit([include(1, local('local.h'), file(LH, raw, unit([typedef(1, _)])))|_])) )).

k10 :- check('and its typedef makes \'Parcel * p = 0;\' a declaration in the includer',
    ( fn_body('uses.c', f, [I|_]), functor(I, declaration, _) )).

k11 :- check('a header that is nowhere is missing, and the file still reads',
    unit('missing.c', unit([include(1, local('nope.h'), missing), declaration(2, _, _, _)]))).

k12 :- check('a cycle of headers is cut, not followed',
    ( c('a.h', AH), unit('cyc.c', unit([include(1, _, file(_, raw, unit([include(1, _, file(_, raw, unit([include(1, _, cyclic(AH))|_])))|_])))])) )).

k13 :- check('the toolchain\'s inclusion path is asked of clang, once',
    ( ccl_include_path(Ds), length(Ds, N), N > 1 )).

k14 :- check('after hello.c, its headers are in the store, one clause per item',
    ( unit('hello.c', _), ccl_kb_ready, '$ccl_ast'(P, _, meta(included(_), N, _)), sub_atom(P, _, _, 0, '/stdio.h'), N > 0 )).

k15 :- check('and hello.c itself, read whole, keyed by its time and the reader\'s version',
    ( c('hello.c', P), '$ccl_ast'(P, key(T, V), meta(top, 3, [_, _])), number(T), ccl_reader_version(V) )).

k16 :- check('a cached read is the same AST as a fresh one',
    ( c('rich.c', P), cicili_ast(P, A), ccl_kb_forget_file(P), cicili_ast(P, B), A == B )).

k17 :- check('a touched file is read again, not served stale',
    ( tmp(D), c('uses.c', U), c('local.h', H), atomic_list_concat([D, '/uses.c'], U2), copy(U, U2), copy(H, D),
            cicili_ast(U2, _), '$ccl_ast'(U2, key(T0, _), _), touch(U2), cicili_ast(U2, _), '$ccl_ast'(U2, key(T1, _), _), T1 > T0 )).

k18 :- check('a changed macro file makes its includer\'s cached read a miss',
    ( tmp(D), c('macros.pl', M), c('uses_macros.c', UM), atomic_list_concat([D, '/uses_macros.c'], UM2), copy(M, D), copy(UM, UM2),
            cicili_ast(UM2, _), ccl_kb_cached(UM2, top, _), atomic_list_concat([D, '/macros.pl'], M2), touch(M2), \+ ccl_kb_cached(UM2, top, _) )).

k19 :- check('the include node names the macro file and its predicates, DCG ones too',
    ( c('macros.pl', MP), unit('uses_macros.c', unit([include(1, local('macros.pl'), macros(MP, Ps))|_])),
            memberchk(macro(square, square, 2), Ps), memberchk(macro(swap, swap, 3), Ps), memberchk(macro(sum, sum, dcg), Ps) )).

k20 :- check('a macro at file scope: counter(hits); is a static int declaration',
    ( unit('uses_macros.c', unit(Is)), member(declaration(_, static, _, [var(hits, _, int(0))]), Is) )).

k21 :- check('a list result is spliced: pair(lo, hi); is two declarations',
    ( unit('uses_macros.c', unit(Is)), append(_, [declaration(_, _, _, [var(lo, _, int(1))]), declaration(_, _, _, [var(hi, _, int(2))])|_], Is) )).

k22 :- check('in an expression: square(a) is a * a',
    ( fn_body('uses_macros.c', f, B), member(return(_, bin('+', bin('*', id(a), id(a)), _)), B) )).

k23 :- check('a DCG macro parses its arguments: sum(a, 2, 3) folds to (a + 2) + 3',
    ( fn_body('uses_macros.c', f, B), member(return(_, bin('+', _, bin('+', bin('+', id(a), int(2)), int(3)))), B) )).

k24 :- check('as a statement: swap(a, b); is a block with a fresh temporary',
    ( fn_body('uses_macros.c', f, B), member(block([declaration(_, _, _, [var(T, _, id(a))]), expr(_, assign('=', id(a), id(b))), expr(_, assign('=', id(b), id(T)))]), B), sub_atom(T, 0, 4, _, tmp_) )).

k25 :- check('type inference: a parameter, the usual conversions, a member through a pointer and a typedef',
    ( fn_body('uses_macros.c', f, B),
            member(declaration(_, _, _, [var(t1, _, str(S1))]), B), codes_atom(S1, 'base([],[int])'),
            member(declaration(_, _, _, [var(t2, _, str(S2))]), B), codes_atom(S2, 'base([],[double])'),
            member(declaration(_, _, _, [var(t4, _, str(S4))]), B), codes_atom(S4, 'base([],[int])') )).

k26 :- check('and a call\'s return type combined with a long',
    ( fn_body('uses_macros.c', f, B), member(declaration(_, _, _, [var(t6, _, str(S))]), B), codes_atom(S, 'base([],[long])') )).

k27 :- check('the size of a struct, LP64: int + double = 16',
    ( fn_body('uses_macros.c', f, B), member(declaration(_, _, _, [var(sz, _, int(16))]), B) )).

k28 :- check('a macro that fails stops the read with its name and arguments',
    ( c('bad_macro.c', P), catch(cicili_ast(P, _), error(E, _), true), E == macro_failed(boom, [int(1)]) )).

k29 :- check('a macro that throws reports the macro, its arguments and the ball',
    ( c('throwing_macro.c', P), catch(cicili_ast(P, _), error(E, _), true), E == macro_error(bang, [int(1)], oops) )).

k79 :- check('a unit that expanded macros ends with what expanded where: swap(a, b) at line 12',
    ( unit('uses_macros.c', unit(Is)), append(_, ['$expansions'(Es)], Is), memberchk(expansion(12, swap, [id(a), id(b)]), Es) )).

k80 :- check('an error inside a macro names the call site and the macro: file, line 2, bang in throws.pl',
    ( c('throwing_macro.c', P), c('throws.pl', M), catch(cicili_ast(P, _), error(macro_error(bang, [int(1)], oops), here(P, 2, in_macro(bang, M))), true) )).

k30 :- check('n := 42; is an int declaration with that initializer',
    ( fn_body('walrus.c', f, B), member(declaration(4, none, base([], [int]), [var(n, base([], [int]), int(42))]), B) )).

k31 :- check('d := n + 1.5; is a double, by the usual conversions',
    ( fn_body('walrus.c', f, B), member(declaration(_, _, _, [var(d, base([], [double]), _)]), B) )).

k32 :- check('q := &p; is a pointer to the typedef, and y := q->y; a double through it',
    ( fn_body('walrus.c', f, B), member(declaration(_, _, _, [var(q, ptr([], base([], [typedef(point_t)])), _)]), B), member(declaration(_, _, _, [var(y, base([], [double]), _)]), B) )).

k33 :- check('t := s; keeps the pointer type; c := k; drops the const: the new variable is its own',
    ( fn_body('walrus.c', f, B), member(declaration(_, _, _, [var(t, ptr([], base([], [char])), _)]), B), member(declaration(_, _, _, [var(c, base([], [int]), _)]), B) )).

k34 :- check('for (i := 0; ...) declares i in the for',
    ( fn_body('walrus.c', f, B), member(for(_, decl(base([], [int]), [var(i, base([], [int]), int(0))]), _, postinc(id(i)), _), B) )).

k35 :- check('g := 7; at file scope is a global int',
    ( unit('walrus.c', unit(Is)), member(declaration(2, none, base([], [int]), [var(g, _, int(7))]), Is) )).

k36 :- check('a right-hand side whose type is unknown is an error naming the variable, the file and the line',
    ( c('no_infer.c', P), catch(cicili_ast(P, _), error(E, here(F, L)), true), E == cannot_infer(z, id(nothing)), F == P, L =:= 2 )).

k37 :- check('{ a, b } := p; binds the members by position, each a declaration by inference',
    ( fn_body('pattern.c', f, B), member(declaration(5, none, _, [var(a, base([], [int]), member(id(p), x))]), B), member(declaration(5, none, _, [var(b, base([], [double]), member(id(p), y))]), B) )).

k38 :- check('_ skips, field: name binds by name, a nested { } destructures a member, all through a pointer',
    ( fn_body('pattern.c', f, B), member(declaration(_, _, _, [var(x, base([], [int]), member(arrow(id(n), at), x))]), B),
            member(declaration(_, _, _, [var(nm, ptr([], base([const], [char])), arrow(id(n), name))]), B), \+ member(declaration(_, _, _, [var(next, _, _)]), B) )).

k39 :- check('a right-hand side that is not a variable is evaluated once, into a temporary',
    ( fn_body('pattern.c', f, B), append(_, [declaration(_, _, _, [var(T, base([], [typedef(point_t)]), call(id(make), []))]), declaration(_, _, _, [var(u, _, member(id(T), x))]), declaration(_, _, _, [var(v, _, member(id(T), y))])|_], B), sub_atom(T, 0, 4, _, tmp_) )).

k40 :- check('a pattern longer than the struct is an error naming the position',
    ( c('pattern_bad.c', P), catch(cicili_ast(P, _), error(E, here(_, L)), true), E == no_member(position(3), base([], [typedef(point_t)])), L =:= 2 )).

k41 :- check('a field the struct has not is an error naming it',
    ( c('pattern_bad2.c', P), catch(cicili_ast(P, _), error(E, _), true), E == no_member(zz, base([], [typedef(point_t)])) )).

k42 :- check('println: {} next, {name} by name, {0} by index, {p} a struct by its members, % kept, newline added',
    ( fn_body('fmt.c', main, B), member(expr(_, call(id(printf), [str(S), id(n), id(name), id(n), member(id(p), x), member(id(p), y)])), B),
            codes_atom(S, 'n = %d name = %s again %d p = point_t { x: %d, y: %g } 100%%\n') )).

k43 :- check('format is an expression of type char *: asprintf into a fresh buffer, in a statement expression',
    ( fn_body('fmt.c', main, B), member(declaration(_, _, _, [var(s, ptr([], base([], [char])), stmt_expr(block([declaration(_, _, _, [var(Buf, _, none)]), expr(_, call(id(asprintf), [addr(id(Buf)), str(S), int(1), int(2), int(3)])), expr(_, id(Buf))])))]), B),
            codes_atom(S, '%d + %d = %d') )).

k44 :- check('a struct inside a struct nests; unsigned long is %lu; {{ }} are braces',
    ( fn_body('fmt.c', main, B), member(expr(_, call(id(printf), [str(S), member(member(id(nd), at), x), member(member(id(nd), at), y), member(id(nd), name), member(id(nd), id)])), B),
            codes_atom(S, 'node { at: point_t { x: %d, y: %g }, name: %s, id: %lu } {braces}\n') )).

k45 :- check('a hole with no argument is an error with its place',
    ( c('fmt_bad.c', P), catch(cicili_ast(P, _), error(macro_error(M, here(_, L)), _), true), M == no_argument(1), L =:= 1 )).

k46 :- check('a name not in scope cannot be formatted',
    ( c('fmt_bad2.c', P), catch(cicili_ast(P, _), error(macro_error(M, here(F, _)), _), true), M == cannot_format(id(nope)), F == P )).

k47 :- check('point { int x; double y; } is the typedef of a struct with that tag and those members',
    unit('shorthand.c', unit([typedef(1, [var(point, base([], [struct(point, [member(base([], [int]), x, none), member(base([], [double]), y, none)])]), none)])|_]))).

k48 :- check('the name is a type inside its own members (node *next) and afterwards (point at); a trailing ; is fine',
    unit('shorthand.c', unit([_, typedef(2, [var(node, base([], [struct(node, [member(ptr([], base([], [typedef(node)])), next, none), member(base([], [typedef(point)]), at, none)])]), none)])|_]))).

k49 :- check('and the types serve a block: a declaration, and a pattern through them',
    ( fn_body('shorthand.c', f, B), member(declaration(_, _, base([], [typedef(point)]), [var(p, _, init(_))]), B), member(declaration(_, _, _, [var(a, base([], [int]), member(id(p), x))]), B) )).

k72 :- check('defer(f) { fclose(f); } is a statement over its named variables, with its block, where it stands',
    ( fn_body('defer.c', count_lines, B), member(defer(8, [id(f)], block([expr(8, call(id(fclose), [id(f)]))])), B),
            member(defer(12, [id(buf)], block([expr(12, call(id(free), [id(buf)]))])), B) )).

k73 :- check('and a call named defer without a block is still a call',
    ( fn_body('defer.c', g, [return(_, call(id(defer), [int(1), int(2)]))]) )).

k74 :- check('buf := malloc(max); is a void * -- malloc\'s prototype came from <stdlib.h>',
    ( fn_body('defer.c', count_lines, B), member(declaration(10, none, _, [var(buf, ptr([], base([], [void])), call(id(malloc), _))]), B) )).

k75 :- check('own char *b = move(a); -- own is a qualifier, move a node, in the reader',
    ( fn_body('run/owners.c', main, B), member(declaration(_, _, base([own], [char]), [var(b, ptr([], base([own], [char])), move(id(a)))]), B) )).

k76 :- check('an own parameter and an own return type',
    ( unit('run/owners.c', unit(Is)), member(function(_, static, _, take, [param(ptr([], base([own], [char])), s)], _, _), Is),
            member(function(_, static, ptr([], base([own], [char])), make, _, _, _), Is) )).

k77 :- check('every statement carries its line: the if, the while, the return in rich.c',
    ( fn_body('rich.c', main, B), member(while(32, _, _), B), member(if(Li, _, goto(Lg, done), none), B), Li =:= Lg, Li > 40, member(label(45, done, return(46, _)), B) )).

k78 :- check('a macro written in the short form gets the line of the call: swap(a, b); at line 12',
    ( fn_body('uses_macros.c', f, B), member(block([declaration(12, _, _, _), expr(12, assign('=', id(a), id(b))), _]), B) )).

k50 :- check('a typedef of a basic type',
    ( unit('rich.c', unit(Is)), member(typedef(_, [var(ulong, base([], [unsigned, long]), none)]), Is) )).

k51 :- check('a typedef of a struct with members',
    ( unit('rich.c', unit(Is)), member(typedef(_, [var(point_t, base([], [struct(point, Ms)]), none)]), Is), length(Ms, 2), Ms = [member(_, x, _)|_] )).

k52 :- check('an enum with a value',
    ( unit('rich.c', unit(Is)), member(declare(_, base([], [enum(color, Es)])), Is), member(enumerator('GREEN', int(5)), Es) )).

k53 :- check('a bitfield member and a self-pointer',
    ( unit('rich.c', unit(Is)), member(declare(_, base([], [struct(node, Ms)])), Is), member(member(ptr([], base([], [struct(node, none)])), next, none), Ms), member(member(_, flags, int(3)), Ms) )).

k54 :- check('a static function',
    ( unit('rich.c', unit(Is)), member(function(_, static, base([], [int]), square, [param(base([], [int]), n)], false, _), Is) )).

k55 :- check('a function-pointer parameter, inside out',
    ( unit('rich.c', unit(Is)), member(function(_, _, _, apply, [param(ptr([], fn(base([], [int]), [param(base([], [int]), anon)], false)), f), _], _, _), Is) )).

k56 :- check('a prototype is a declaration of a function type',
    ( unit('rich.c', unit(Is)), member(declaration(_, none, _, [var(apply, fn(_, _, _), none)]), Is) )).

k57 :- check('an array of pointers with a designated initializer',
    ( unit('rich.c', unit(Is)), member(declaration(_, none, base([const], [char]), [var(names, arr(none, ptr([], _)), init(L))]), Is), length(L, 3), last(L, item([at(int(3))], _)) )).

k58 :- check('designators by field',
    ( unit('rich.c', unit(Is)), member(declaration(_, _, _, [var(origin, _, init([item([field(x)], int(0))|_]))]), Is) )).

k59 :- check('a float with an exponent, a hex integer, a char escape',
    ( unit('rich.c', unit(Is)), member(declaration(_, _, _, [var(ratio, _, float(1500.0))]), Is), member(declaration(_, _, _, [var(big, _, int(255))]), Is), member(declaration(_, _, _, [var(sep, _, chr(10))]), Is) )).

k60 :- check('the typedef name is a type from then on',
    ( fn_body('rich.c', main, B), member(declaration(_, none, base([], [typedef(point_t)]), _), B) )).

k61 :- check('for, if/else-if, continue, break, compound assignment',
    ( fn_body('rich.c', main, B), member(for(_, assign('=', id(i), int(0)), bin('<', id(i), id('LIMIT')), postinc(id(i)), block([if(_, _, continue(_), if(_, _, break(_), none)), expr(_, assign('+=', id(total), call(id(square), [id(i)])))])), B) )).

k62 :- check('while, do-while',
    ( fn_body('rich.c', main, B), member(while(_, bin('>', id(total), int(100)), expr(_, _)), B), member(do(_, block([expr(_, postinc(id(total)))]), bin('<', id(total), int(5))), B) )).

k63 :- check('switch with cases, a fallthrough and a default',
    ( fn_body('rich.c', main, B), member(switch(_, id(argc), block([case(_, int(1), expr(_, _)), break(_), case(_, int(2), default(_, expr(_, assign('=', id(total), neg(id(total))))))])), B) )).

k64 :- check('the conditional, casts, sizeof of a type and of an expression',
    ( fn_body('rich.c', main, B), member(expr(_, assign('=', id(total), cond(bin('>', id(argc), int(1)), cast(base([], [int]), id(ratio)), bin('+', cast(_, sizeof_type(base([], [typedef(point_t)]))), sizeof(member(id(p), x)))))), B) )).

k65 :- check('the operator levels: shift, or, and, unary not, xor',
    ( fn_body('rich.c', main, B), member(expr(_, assign('=', id(mask), bin('^', bin('&', bin('|', bin('<<', id(mask), int(2)), int(3)), bitnot(bin('<<', int(1), int(4)))), int(15)))), B) )).

k66 :- check('member, address-of, arrow',
    ( fn_body('rich.c', main, B), member(expr(_, assign('=', arrow(member(id(n), next), flags), int(5))), B), member(expr(_, assign('=', member(id(n), next), addr(id(n)))), B) )).

k67 :- check('the comma operator, logical operators, goto and a label',
    ( fn_body('rich.c', main, B), member(expr(_, assign('=', id(i), comma(id(total), comma(id(mask), int(3))))), B), member(if(_, not(bin('||', bin('&&', id(i), id(total)), not(id(mask)))), goto(_, done), none), B), member(label(_, done, return(_, _)), B) )).

k68 :- check('adjacent string literals are one string',
    ( fn_body('rich.c', main, B), member(expr(_, call(id(printf), [_, _, str(S)])), B), codes_atom(S, ab) )).

k69 :- check('cicili_ast/3 answers the tokens from the first thing it could not read',
    ( c('bad.c', P), cicili_ast(P, unit(Is), [tok(_, _, 3)|_]), length(Is, 2) )).

k70 :- check('cicili_ast/2 makes that a syntax error naming the line, and where it gave up',
    ( c('bad.c', P), catch(cicili_ast(P, _), error(E, _), true), E == syntax_error(cicili_ast(P, line(3), near(3))) )).

k71 :- check('a lexical error names its line too',
    ( c('lex.c', P), catch(cicili_ast(P, _), error(syntax_error(cicili_ast(_, lexical, line(L))), _), true), L =:= 2 )).

k72 :- check('the tie operator <*>: on a member, a result, a parameter, a local, and after :=',
    ( unit('tie.c', unit(Is)),
      member(declare(_, base(_, [struct(list, Ms)])), Is), member(member(ptr([tie(head)|_], _), cur, none), Ms),
      member(declaration(_, _, _, [var(find, fn(ptr([tie(head)|_], _), _, _), none)]), Is),
      member(function(_, _, _, f, [param(_, head), param(ptr([tie(head)|_], _), cur)], _, block(B)), Is),
      member(declaration(_, _, _, [var(b, base([tie(a)|_], [double]), float(_))]), B),
      member(declaration(_, _, _, [var(c, base([tie(b)|_], [int]), id(a))]), B) )).

t_checks :-
    section('hello.c, whole'),
    k1,
    k2,
    k3,
    k4,
    k5,
    section('includes: found on the inclusion path, read, and their typedefs known'),
    k6,
    k7,
    k8,
    k9,
    k10,
    k11,
    k12,
    k13,
    section('the knowledge base remembers what was read, by modification time'),
    k14,
    k15,
    k16,
    k17,
    k18,
    section('macros: a .pl included is a set of macro functions over ASTs'),
    k19,
    k20,
    k21,
    k22,
    k23,
    k24,
    k25,
    k26,
    k27,
    k28,
    k29,
    k79,
    k80,
    section(':= declares by inference'),
    k30,
    k31,
    k32,
    k33,
    k34,
    k35,
    k36,
    section('the left of := may be a pattern over a struct'),
    k37,
    k38,
    k39,
    k40,
    k41,
    section('format, print, println: global macros, Rust\'s holes, the symbol table\'s types'),
    k42,
    k43,
    k44,
    k45,
    k46,
    section('name { ... } at file scope is typedef struct name { ... } name;'),
    k47,
    k48,
    k49,
    section('defer(a, b) { ... }: scope-bound, like cleanup'),
    k72,
    k73,
    k74,
    section('the safe part, as read: own and move'),
    k75,
    k76,
    section('statement lines'),
    k77,
    k78,
    section('rich.c: the grammar, one construct at a time'),
    k50,
    k51,
    k52,
    k53,
    k54,
    k55,
    k56,
    k57,
    k58,
    k59,
    k60,
    k61,
    k62,
    k63,
    k64,
    k65,
    k66,
    k67,
    k68,
    section('the tie operator'),
    k72,
    section('where it stops'),
    k69,
    k70,
    k71.

%% ---- real C from the neighbours ----------------------------------------------
%% not chk/3 facts: each file is checked only if the neighbour checkout has it
t_real :-
    section('real C from the neighbours, read entirely'),
    os_env('CICILI', Cicili),
    real_file(Cicili, 'test/c/main.c'), real_file(Cicili, 'test/c/shared.c'), real_file(Cicili, 'test/c/macro.c'),
    real_file(Cicili, 'example/cimath.c'), real_file(Cicili, 'example/numpy_example.c').
real_file(Cicili, Rel) :-
    atomic_list_concat([Cicili, '/', Rel], P),
    (   exists_file(P)
    ->  check(Rel, ( cicili_ast(P, unit(_), Rest), ( Rest == [] -> true ; Rest = [tok(_, _, L)|_], ccl_farthest(F), write('     stopped at '), write(L), write(' near '), write(F), nl, fail ) ))
    ;   write('SKIP '), write(Rel), write(' (not here)'), nl ).
