%% cicili-lang -- library(ccl_syntax): C source, read as a DCG, into an AST.
%%
%% Two grammars over two lists. `ccl_lex//2' is a DCG over CHARACTER CODES:
%% it reads a whole C file into a list of tokens, each carrying the line it
%% started on. `ccl_externals//2' is a DCG over those TOKENS: it parses a
%% translation unit into an AST of terms. Neither expands the preprocessor:
%% a `#' line is kept whole as a directive node, so what the parser sees is
%% the file as written, and `size_t' and friends are known as typedef names
%% by a seed list rather than by reading <stddef.h>.
%%
%% This is C (C11 without _Generic, _Alignas, K&R parameter lists), plus the
%% GNU forms Cicili's own emitted C carries: __attribute__((...)), which is
%% read and dropped, and the statement expression ({ ... }). The C++ forms --
%% classes, templates, namespaces, `::' -- are not read yet; a file that
%% uses them parses up to the first of them, and cicili_ast/3 answers where.
%%
%% Every predicate here is ccl_-prefixed: cocolog has one namespace, and a
%% grammar full of `expr' and `id' would collide with any program's. Only the
%% AST's functors are bare, since they are data, not predicates.
%%
%% THE TOKENS:   tok(Kind, Value, Line)
%%   kw    a keyword, as an atom          id    an identifier, as an atom
%%   int   an integer (suffixes dropped)  float a float (suffix dropped)
%%   str   a string, as a code list       chr   a character constant, as a code
%%   p     a punctuator, as an atom       pp    a preprocessor line, as an atom
%%
%% THE AST (Line is where the item starts):
%%   unit(Items)
%%   include(Line, Spec, Resolved)             an #include, found and read: library(ccl_include);
%%                                             a .pl included is macros(Path, [macro(CName, Pred, Arity|dcg) ...]), and
%%                                             a call name(a, b) with name/3 among them is replaced,
%%                                             at parse time, by R of name(ASTa, ASTb, R)
%%   directive(Line, Text)                     any other # line, whole
%%   static_assert(Line, Expr, Message)
%%   function(Line, Storage, Type, Name, Params, Variadic, Body)
%%   declaration(Line, Storage, Base, [var(Name, Type, Init) ...])
%%   typedef(Line, [var(Name, Type, none) ...])   also from `name { members }' at file scope,
%%                                             which is typedef struct name { members } name;
%%   declare(Line, Base)                       `struct s { ... };' and the like
%%   empty                                     a stray `;'
%% Types:  base(Quals, Specs) where Specs is the specifier list as written
%%           ([int], [unsigned, long], [struct(Name, Members)], [enum(N, Es)],
%%            [typedef(Name)], [typeof(ExprOrType)] ...); Quals from const volatile restrict _Atomic
%%         ptr(Quals, Type)   block(Quals, Type)   arr(Size, Type)   fn(Ret, Params, Variadic)
%%         Members: [member(Type, Name, Bits) ...]; Params: [param(Type, Name) ...]
%%         Enumerators: [enumerator(Name, Value) ...]
%% Statements:  block(Items)  if(C, Then, Else)  while(C, S)  do(S, C)
%%   for(Init, Cond, Step, S)  return(E)  return  break  continue  goto(L)
%%   switch(E, S)  case(E, S)  default(S)  label(L, S)  expr(E)  empty
%%   defer(Line, [id(V) ...], Body)   runs Body at every exit of the scope, LIFO
%%   and a declaration/4 or typedef/2 or declare/2 as a block item;
%%   `name := expr;' is a declaration/4 with the type inferred from expr, and
%%   `{ a, _, f: b } := expr;' one declaration/4 per binding, from the struct's members
%% Expressions: int(N) float(F) str(Codes) chr(C) id(N) call(F, Args)
%%   index(A, I) member(E, N) arrow(E, N) postinc(E) postdec(E) preinc(E)
%%   predec(E) neg(E) pos(E) not(E) bitnot(E) addr(E) deref(E) sizeof(E)
%%   sizeof_type(T) cast(T, E) bin(Op, A, B) assign(Op, L, R) cond(C, A, B)
%%   comma(A, B) init([item(Designators, Value) ...]) stmt_expr(Block)
%%   compound_lit(Type, init(Items))            C99's (T){ ... }
%%
%% THE SURFACE:
%%   ccl_tokens(+Codes, -Tokens, -RestCodes)     the lexer, as phrase/3
%%   ccl_unit(+Tokens, -AST, -RestTokens)        the parser, as phrase/3
%%   ccl_line_of(+Codes, +RestCodes, -Line)      the line a lexical error is on
%%   ccl_farthest(-Line)                          after ccl_unit: the last line the grammar reached
%%
%% library(cicili) wraps these as cicili_ast/2 and cicili_ast/3.

%% the reader's version, part of the knowledge base's cache key: bump it when
%% the grammar changes, so what an older grammar left partial is read again
ccl_reader_version(15).

%% ---- the lexer: a DCG over codes ------------------------------------------

ccl_tokens(Codes, Tokens, Rest) :- phrase(ccl_lex(1, Tokens), Codes, Rest).

ccl_line_of(Codes, Rest, Line) :-
    append(Consumed, Rest, Codes), !,
    ccl_count_newlines(Consumed, 0, N), Line is N + 1.
ccl_count_newlines([], N, N).
ccl_count_newlines([C|Cs], N0, N) :- ( C =:= 10 -> N1 is N0 + 1 ; N1 = N0 ), ccl_count_newlines(Cs, N1, N).

ccl_lex(L0, Ts) --> ccl_layout(L0, L1), ccl_lex_(L1, Ts).
ccl_lex_(L0, [T|Ts]) --> ccl_token(L0, L1, T), !, ccl_layout(L1, L2), ccl_lex_(L2, Ts).
ccl_lex_(_, []) --> [].

%% layout: blanks, newlines (counted), and both kinds of comment
ccl_layout(L0, L) --> [C], { C =:= 10 }, !, { L1 is L0 + 1 }, ccl_layout(L1, L).
ccl_layout(L0, L) --> [C], { ccl_blank(C) }, !, ccl_layout(L0, L).
ccl_layout(L0, L) --> [0'/, 0'/], !, ccl_to_eol, ccl_layout(L0, L).
ccl_layout(L0, L) --> [0'/, 0'*], !, ccl_block_comment(L0, L1), ccl_layout(L1, L).
ccl_layout(L, L) --> [].
ccl_blank(C) :- ( C =:= 32 ; C =:= 9 ; C =:= 13 ; C =:= 12 ; C =:= 11 ).
ccl_to_eol --> [C], { C =\= 10 }, !, ccl_to_eol.
ccl_to_eol --> [].
ccl_block_comment(L, L) --> [0'*, 0'/], !.
ccl_block_comment(L0, L) --> [C], !, { ( C =:= 10 -> L1 is L0 + 1 ; L1 = L0 ) }, ccl_block_comment(L1, L).
ccl_block_comment(L, L) --> [].                    % an unterminated comment ends the file

%% a token, and the line after it
%% 35 is #, 34 is ", 39 is ', 92 is \ -- numbers, because 0'" and 0'' read badly
ccl_token(L0, L, tok(pp, Text, L0)) --> [35], !, ccl_pp_line(L0, L, Cs), { atom_codes(Text, [35|Cs]) }.
ccl_token(L, L, tok(str, S, L))     --> [34], !, ccl_str_body(S).
ccl_token(L, L, tok(chr, C, L))     --> [39], !, ccl_chr_body(C), [39].
ccl_token(L, L, T)                  --> ccl_number(L, T), !.
ccl_token(L, L, T)                  --> ccl_word(L, T), !.
ccl_token(L, L, tok(p, P, L))       --> ccl_punct(P).

%% a preprocessor line runs to the end of the line, a backslash continuing it
ccl_pp_line(L0, L, [])     --> [C], { C =:= 10 }, !, { L is L0 + 1 }.
ccl_pp_line(L0, L, Cs)     --> [92, C], { C =:= 10 }, !, { L1 is L0 + 1 }, ccl_pp_line(L1, L, Cs).
ccl_pp_line(L0, L, [C|Cs]) --> [C], !, ccl_pp_line(L0, L, Cs).
ccl_pp_line(L, L, [])      --> [].

ccl_str_body([])     --> [34], !.
ccl_str_body([C|Cs]) --> [92], !, ccl_escape(C), ccl_str_body(Cs).
ccl_str_body([C|Cs]) --> [C], ccl_str_body(Cs).
ccl_chr_body(C) --> [92], !, ccl_escape(C).
ccl_chr_body(C) --> [C].
ccl_escape(10) --> [0'n], !.     ccl_escape(9)  --> [0't], !.     ccl_escape(13) --> [0'r], !.
ccl_escape(0)  --> [0'0], !.     ccl_escape(7)  --> [0'a], !.     ccl_escape(8)  --> [0'b], !.
ccl_escape(12) --> [0'f], !.     ccl_escape(11) --> [0'v], !.     ccl_escape(27) --> [0'e], !.
ccl_escape(C)  --> [0'x], !, ccl_hex_digits(Ds), { Ds \== [], ccl_hex_value(Ds, 0, C) }.
ccl_escape(C)  --> [C].

ccl_number(L, T) --> [0'0, X], { X =:= 0'x ; X =:= 0'X }, !, ccl_hex_digits(Ds), { Ds \== [], ccl_hex_value(Ds, 0, N) }, ccl_int_suffix, { T = tok(int, N, L) }.
ccl_number(L, T) --> ccl_digits(Is), { Is \== [] }, ccl_number_rest(Is, L, T).
ccl_number_rest(Is, L, tok(float, F, L)) --> [0'.], ccl_digits(Fs), ccl_exponent(Es), !, ccl_float_suffix,
    { ( Fs == [] -> Fs1 = [0'0] ; Fs1 = Fs ), append(Is, [0'.|Fs1], A), append(A, Es, B), number_codes(F, B) }.
ccl_number_rest(Is, L, tok(float, F, L)) --> ccl_exponent(Es), { Es \== [] }, !, ccl_float_suffix,
    { append(Is, [0'., 0'0|Es], B), number_codes(F, B) }.
ccl_number_rest([0'0|Os], L, tok(int, N, L)) --> { Os \== [], ccl_octal_digits(Os) }, !, ccl_int_suffix, { ccl_octal_value(Os, 0, N) }.
ccl_number_rest(Is, L, tok(int, N, L)) --> ccl_int_suffix, { number_codes(N, Is) }.
ccl_digits([D|Ds]) --> [D], { ccl_digit(D) }, !, ccl_digits(Ds).
ccl_digits([]) --> [].
ccl_hex_digits([D|Ds]) --> [D], { ccl_hexdigit(D) }, !, ccl_hex_digits(Ds).
ccl_hex_digits([]) --> [].
ccl_exponent([0'e|Es]) --> [E], { E =:= 0'e ; E =:= 0'E }, !, ccl_sign(S), ccl_digits(Ds), { Ds \== [], append(S, Ds, Es) }.
ccl_exponent([]) --> [].
ccl_sign([0'-]) --> [0'-], !.
ccl_sign([0'+]) --> [0'+], !.
ccl_sign([]) --> [].
ccl_int_suffix --> [C], { C =:= 0'u ; C =:= 0'U ; C =:= 0'l ; C =:= 0'L }, !, ccl_int_suffix.
ccl_int_suffix --> [].
ccl_float_suffix --> [C], { C =:= 0'f ; C =:= 0'F ; C =:= 0'l ; C =:= 0'L }, !.
ccl_float_suffix --> [].
ccl_digit(D) :- D >= 0'0, D =< 0'9.
ccl_hexdigit(D) :- ( ccl_digit(D) ; D >= 0'a, D =< 0'f ; D >= 0'A, D =< 0'F ).
ccl_hex_value([], N, N).
ccl_hex_value([D|Ds], N0, N) :- ( ccl_digit(D) -> V is D - 0'0 ; D >= 0'a -> V is D - 0'a + 10 ; V is D - 0'A + 10 ), N1 is N0 * 16 + V, ccl_hex_value(Ds, N1, N).
ccl_octal_digits([]).
ccl_octal_digits([D|Ds]) :- D >= 0'0, D =< 0'7, ccl_octal_digits(Ds).
ccl_octal_value([], N, N).
ccl_octal_value([D|Ds], N0, N) :- N1 is N0 * 8 + D - 0'0, ccl_octal_value(Ds, N1, N).

ccl_word(L, T) --> [C], { ccl_alpha(C) }, ccl_alnums(Cs), { atom_codes(A, [C|Cs]), ( ccl_keyword(A) -> T = tok(kw, A, L) ; T = tok(id, A, L) ) }.
ccl_alnums([C|Cs]) --> [C], { ccl_alnum(C) }, !, ccl_alnums(Cs).
ccl_alnums([]) --> [].
ccl_alpha(C) :- ( C >= 0'a, C =< 0'z ; C >= 0'A, C =< 0'Z ; C =:= 0'_ ).
ccl_alnum(C) :- ( ccl_alpha(C) ; ccl_digit(C) ).

ccl_keyword(K) :- memberchk(K, [auto, break, case, char, const, continue, default, do, double, else,
    enum, extern, float, for, goto, if, inline, int, long, register, restrict, return, short,
    signed, sizeof, static, struct, switch, typedef, union, unsigned, void, volatile, while,
    '_Bool', '_Complex', '_Noreturn', '_Atomic', '_Static_assert', '_Thread_local']).

%% punctuators, longest first
ccl_punct(P) --> "...", !, { P = '...' }.
ccl_punct(P) --> ">>=", !, { P = '>>=' }.
ccl_punct(P) --> ":=", !, { P = ':=' }.
ccl_punct(P) --> "<<=", !, { P = '<<=' }.
ccl_punct(P) --> ccl_two_char(P), !.
ccl_punct(P) --> [C], { ccl_one_char(C, P) }.
ccl_two_char('->') --> "->".     ccl_two_char('++') --> "++".     ccl_two_char('--') --> "--".
ccl_two_char('<<') --> "<<".     ccl_two_char('>>') --> ">>".     ccl_two_char('<=') --> "<=".
ccl_two_char('>=') --> ">=".     ccl_two_char('==') --> "==".     ccl_two_char('!=') --> "!=".
ccl_two_char('&&') --> "&&".     ccl_two_char('||') --> "||".     ccl_two_char('*=') --> "*=".
ccl_two_char('/=') --> "/=".     ccl_two_char('%=') --> "%=".     ccl_two_char('+=') --> "+=".
ccl_two_char('-=') --> "-=".     ccl_two_char('&=') --> "&=".     ccl_two_char('^=') --> "^=".
ccl_two_char('|=') --> "|=".
ccl_one_char(0'[, '[').  ccl_one_char(0'], ']').  ccl_one_char(0'(, '(').  ccl_one_char(0'), ')').
ccl_one_char(0'{, '{').  ccl_one_char(0'}, '}').  ccl_one_char(0'., '.').  ccl_one_char(0'&, '&').
ccl_one_char(0'*, '*').  ccl_one_char(0'+, '+').  ccl_one_char(0'-, '-').  ccl_one_char(0'~, '~').
ccl_one_char(0'!, '!').  ccl_one_char(0'/, '/').  ccl_one_char(0'%, '%').  ccl_one_char(0'<, '<').
ccl_one_char(0'>, '>').  ccl_one_char(0'^, '^').  ccl_one_char(0'|, '|').  ccl_one_char(0'?, '?').
ccl_one_char(0':, ':').  ccl_one_char(0';, ';').  ccl_one_char(0'=, '=').  ccl_one_char(0',, ',').

%% ---- the parser: a DCG over tokens -----------------------------------------

ccl_unit(Tokens, unit(Items), Rest) :- ccl_seed_typedefs(Env), nb_setval('$ccl_env', Env), nb_setval('$ccl_far', 0), nb_setval('$ccl_macros', []), ccl_standard_macros, ccl_scope_init, phrase(ccl_externals(Env, Items), Tokens, Rest).

%% ---- name := expr ---------------------------------------------------------------
%% The type is ccl_type_of/2's (library(ccl_infer)) over the scope as it stands:
%% arrays and functions decay to pointers, top-level qualifiers are dropped
%% (the new variable is its own), and a type that cannot be inferred is an
%% error naming the variable, the expression and the place.
ccl_infer_decl(L, N, E, declaration(L, none, Base, [var(N, T, E)])) :-
    ccl_type_of(E, T0),
    ( T0 == unknown -> ccl_here(F, _), throw(error(cannot_infer(N, E), here(F, L))) ; true ),
    ccl_decay(T0, T1), ccl_strip_quals(T1, T), ccl_base_of(T, Base).
ccl_strip_quals(base(_, S), base([], S)) :- !.
ccl_strip_quals(ptr(_, T), ptr([], T)) :- !.
ccl_strip_quals(T, T).
ccl_base_of(base(Q, S), base(Q, S)) :- !.
ccl_base_of(ptr(_, T), B) :- !, ccl_base_of(T, B).
ccl_base_of(block(_, T), B) :- !, ccl_base_of(T, B).
ccl_base_of(arr(_, T), B) :- !, ccl_base_of(T, B).
ccl_base_of(fn(R, _, _), B) :- !, ccl_base_of(R, B).
ccl_base_of(T, T).

%% ---- { x, _, name: y } := expr ---------------------------------------------------
%% The left of := may be a pattern over a struct (or a pointer to one, read
%% through ->): a name binds the member at its position, `_' skips one,
%% `field: name' binds the member called field, `field: { ... }' or a bare
%% `{ ... }' destructures a member that is a struct itself. Each binding is
%% a declaration by inference; a right-hand side that is not a variable is
%% evaluated once into a temporary (ccl_gensym). The items are spliced in.
ccl_pattern([P|Ps]) --> ccl_pattern_elem(P), ( ccl_p(','), !, ccl_pattern(Ps) ; { Ps = [] } ).
ccl_pattern([]) --> [].
ccl_pattern_elem(field(F, P)) --> ccl_id(F), ccl_p(':'), !, ccl_pattern_elem(P).
ccl_pattern_elem(sub(Ps)) --> ccl_p('{'), !, ccl_pattern(Ps), ccl_p('}').
ccl_pattern_elem(skip) --> ccl_id('_'), !.
ccl_pattern_elem(bind(N)) --> ccl_id(N).

ccl_destructure(L, Ps, E, Ds) :-
    ccl_type_of(E, T),
    ( T == unknown -> ccl_here(F, _), throw(error(cannot_infer(pattern, E), here(F, L))) ; true ),
    (   E = id(_) -> Src = E, Ds = Ds1
    ;   ccl_gensym(tmp, Tmp), ccl_infer_decl(L, Tmp, E, D0), ccl_note_item(D0), Src = id(Tmp), Ds = [D0|Ds1] ),
    ccl_destructure_(L, Ps, Src, T, 1, Ds1).
ccl_destructure_(_, [], _, _, _, []).
ccl_destructure_(L, [P|Ps], Src, T, I, Ds) :-
    ccl_pattern_decls(L, P, Src, T, I, D1), I1 is I + 1,
    ccl_destructure_(L, Ps, Src, T, I1, D2), append(D1, D2, Ds).
ccl_pattern_decls(_, skip, _, _, _, []) :- !.
ccl_pattern_decls(L, field(F, P), Src, T, _, Ds) :- !, ccl_member_access(L, Src, T, F, Access, MT), ccl_pattern_bind(L, P, Access, MT, Ds).
ccl_pattern_decls(L, P, Src, T, I, Ds) :- ccl_nth_member(L, T, I, F), ccl_member_access(L, Src, T, F, Access, MT), ccl_pattern_bind(L, P, Access, MT, Ds).
ccl_pattern_bind(_, skip, _, _, []) :- !.
ccl_pattern_bind(L, bind(N), Access, _, [D]) :- !, ccl_infer_decl(L, N, Access, D), ccl_note_item(D).
ccl_pattern_bind(L, sub(Ps), Access, MT, Ds) :- ccl_destructure_(L, Ps, Access, MT, 1, Ds).
ccl_member_access(L, Src, T, F, Access, MT) :-
    ccl_struct_behind(T, S, Arrow),
    ( Arrow == yes -> Access = arrow(Src, F) ; Access = member(Src, F) ),
    ( ccl_member_type(S, F, MT) -> true ; ccl_here(File, _), throw(error(no_member(F, T), here(File, L))) ).
ccl_nth_member(L, T, I, F) :-
    ccl_struct_behind(T, S, _),
    ( ccl_members_of(S, Ms), ccl_nth(I, Ms, member(_, F, _)) -> true ; ccl_here(File, _), throw(error(no_member(position(I), T), here(File, L))) ).
ccl_struct_behind(T, S, Arrow) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, S0) -> ccl_resolve_type(S0, S), Arrow = yes ; S = T1, Arrow = no ).
ccl_nth(1, [X|_], X) :- !.
ccl_nth(I, [_|T], X) :- I > 1, I1 is I - 1, ccl_nth(I1, T, X).

%% ---- the scope, as the parser goes: what a macro's type inference sees --------
%% '$ccl_scope' is a list of frames, innermost first, each [Name-Type ...];
%% '$ccl_typedefs' is [Name-Type ...]; '$ccl_tags' is [Tag-Members ...].
%% Enumerators are declared as int. Filled here, read by library(ccl_infer).
ccl_scope_init :- nb_setval('$ccl_scope', [[]]), nb_setval('$ccl_typedefs', []), nb_setval('$ccl_tags', []), nb_setval('$ccl_enums', []).
ccl_push_scope --> { ccl_scope_push }.
ccl_pop_scope --> { ccl_scope_pop }.
ccl_scope_push :- nb_getval('$ccl_scope', S), nb_setval('$ccl_scope', [[]|S]).
ccl_scope_pop :- nb_getval('$ccl_scope', S), ( S = [_|S1], S1 \== [] -> nb_setval('$ccl_scope', S1) ; true ).
ccl_note_items([]).
ccl_note_items([I|Is]) :- ccl_note_item(I), ccl_note_items(Is).
ccl_declare(N, T) :- nb_getval('$ccl_scope', [F|S]), nb_setval('$ccl_scope', [[N-T|F]|S]).
ccl_note_typedef(N, T) :- nb_getval('$ccl_typedefs', L), nb_setval('$ccl_typedefs', [N-T|L]).
ccl_note_tag(Tag, Ms) :- nb_getval('$ccl_tags', L), nb_setval('$ccl_tags', [Tag-Ms|L]).
ccl_note_item(declaration(_, _, Base, Ds)) :- !, ccl_note_tags(Base), ccl_declare_vars(Ds).
ccl_note_item(typedef(_, Ds)) :- !, ccl_note_typedefs(Ds).
ccl_note_item(declare(_, Base)) :- !, ccl_note_tags(Base).
ccl_note_item(function(_, _, Ret, Name, Ps, V, _)) :- !, ccl_note_tags(Ret), ccl_note_params(Ps), ccl_declare(Name, fn(Ret, Ps, V)).
ccl_note_item(_).
ccl_declare_vars([]).
ccl_declare_vars([var(N, T, _)|Ds]) :- ccl_note_tags(T), ccl_declare(N, T), ccl_declare_vars(Ds).
ccl_note_typedefs([]).
ccl_note_typedefs([var(N, T, _)|Ds]) :- ccl_note_tags(T), ccl_note_typedef(N, T), ccl_note_typedefs(Ds).
ccl_note_params([]).
ccl_note_params([param(T, _)|Ps]) :- ccl_note_tags(T), ccl_note_params(Ps).
ccl_declare_params([]).
ccl_declare_params([param(T, N)|Ps]) :- ( N == anon -> true ; ccl_declare(N, T) ), ccl_declare_params(Ps).
ccl_note_tags(base(_, Specs)) :- !, ccl_note_specs(Specs).
ccl_note_tags(ptr(_, T)) :- !, ccl_note_tags(T).
ccl_note_tags(block(_, T)) :- !, ccl_note_tags(T).
ccl_note_tags(arr(_, T)) :- !, ccl_note_tags(T).
ccl_note_tags(fn(R, Ps, _)) :- !, ccl_note_tags(R), ccl_note_params(Ps).
ccl_note_tags(_).
ccl_note_specs([]).
ccl_note_specs([S|Ss]) :- ccl_note_spec(S), ccl_note_specs(Ss).
ccl_note_spec(struct(Tag, Ms)) :- Ms \== none, !, ( Tag == anon -> true ; ccl_note_tag(Tag, Ms) ), ccl_note_members(Ms).
ccl_note_spec(union(Tag, Ms)) :- Ms \== none, !, ( Tag == anon -> true ; ccl_note_tag(Tag, Ms) ), ccl_note_members(Ms).
ccl_note_spec(enum(Tag, Es)) :- Es \== none, !, ( Tag == anon -> true ; ccl_note_tag(Tag, Es) ), ccl_declare_enumerators(Es).
ccl_note_spec(_).
ccl_note_members([]).
ccl_note_members([member(T, _, _)|Ms]) :- ccl_note_tags(T), ccl_note_members(Ms).
%% an enumerator is an int in scope, and its value is kept ('$ccl_enums',
%% Name-Value) for the lowering and for constant expressions
ccl_declare_enumerators(Es) :- ccl_declare_enumerators(Es, 0).
ccl_declare_enumerators([], _).
ccl_declare_enumerators([enumerator(N, E)|Es], Next) :-
    ( E == none -> V = Next ; ccl_const_eval(E, V0) -> V = V0 ; V = Next ),
    ccl_declare(N, base([], [int])),
    nb_getval('$ccl_enums', L), nb_setval('$ccl_enums', [N-V|L]),
    Next1 is V + 1, ccl_declare_enumerators(Es, Next1).

%% ---- macros: the predicates of an included .pl (library(ccl_include)) ---------
%% name(a, b) with name/3 registered runs name(ASTa, ASTb, R) now; R replaces
%% the call. A list R is spliced into the items around it ('$splice').
%% the registry holds macro(CName, Pred, Arity|dcg) entries (library(ccl_include))
ccl_is_macro(N, K) :- once(catch(nb_getval('$ccl_macros', Ms), _, fail)), ( K1 is K + 1, memberchk(macro(N, _, K1), Ms) -> true ; memberchk(macro(N, _, dcg), Ms) ).
ccl_macro_name(N) :- once(catch(nb_getval('$ccl_macros', Ms), _, fail)), memberchk(macro(N, _, _), Ms).
%% a plain macro name/K+1 is called pred(A1..AK, R); a DCG macro name//1 is
%% phrase(pred(R), [A1..AK]): the arguments are the list it parses
ccl_expand_macro(N, As, R) :-
    nb_getval('$ccl_macros', Ms), length(As, K), K1 is K + 1,
    ( memberchk(macro(N, P, K1), Ms) -> append(As, [R0], Args), G =.. [P|Args] ; memberchk(macro(N, P, dcg), Ms), G = phrase(N1, As), N1 =.. [P, R0] ),
    (   catch(G, E, ( E = error(macro_error(_, here(_, _)), _) -> throw(E) ; throw(error(macro_error(N, As, E), _)) ))
    ->  ( is_list(R0) -> R = '$splice'(R0) ; R = R0 )
    ;   throw(error(macro_failed(N, As), _)) ).
ccl_call_or_macro(id(N), As, R) :- length(As, K), ccl_is_macro(N, K), !, ccl_expand_macro(N, As, R).
ccl_call_or_macro(F, As, call(F, As)).
ccl_stmt_of(E, E) :- ccl_is_stmt(E), !.
ccl_stmt_of(E, expr(E)).
ccl_is_stmt('$splice'(_)).
ccl_is_stmt(T) :- functor(T, F, _), memberchk(F, [block, if, while, do, for, return, break, continue, goto, switch, case, default, label, empty, declaration, typedef, declare, defer]).
ccl_splice('$splice'(L), More, Items) :- !, append(L, More, Items).
ccl_splice(I, More, [I|More]).

%% typedef names the headers would have declared; the file may add its own
ccl_seed_typedefs([size_t, ssize_t, ptrdiff_t, intptr_t, uintptr_t, int8_t, int16_t, int32_t, int64_t,
    uint8_t, uint16_t, uint32_t, uint64_t, bool, 'FILE', va_list, time_t, clock_t, off_t, pid_t,
    uid_t, gid_t, mode_t, 'DIR', wchar_t, jmp_buf, sigset_t, socklen_t, pthread_t, pthread_mutex_t]).

%% the typedef names in force, kept globally too, for the casts and sizeofs
%% that sit deep in an expression where no Env is threaded
ccl_set_env(Env) --> { nb_setval('$ccl_env', Env) }.
ccl_known_typedef(Env, N) :- ( memberchk(N, Env) -> true ; nb_getval('$ccl_env', G), memberchk(N, G) ).

%% token helpers, usable as nonterminals. Each consumption notes the farthest
%% line reached, so a failure can say where the grammar gave up, not only
%% where the failed item began.
ccl_kw(K) --> [tok(kw, K, L)], { ccl_far(L) }.
ccl_p(P)  --> [tok(p, P, L)], { ccl_far(L) }.
ccl_id(N) --> [tok(id, N, L)], { ccl_far(L) }.
ccl_line(L, S, S) :- S = [tok(_, _, L)|_].
ccl_peek(K, V, S, S) :- S = [tok(K, V, _)|_].
ccl_far(L) :- nb_getval('$ccl_far', F), ( L > F -> nb_setval('$ccl_far', L) ; true ).
ccl_farthest(L) :- nb_getval('$ccl_far', L).

ccl_externals(Env, Is) --> [tok(pp, T, _)], { ccl_line_marker(T) }, !, ccl_externals(Env, Is).   % clang -E's `# 93 "file"', dropped
ccl_externals(Env0, Items) --> ccl_external(Env0, Env1, I), !, ccl_set_env(Env1), ccl_externals(Env1, More), { ccl_splice(I, More, Items) }.
ccl_externals(_, []) --> [].
ccl_line_marker(T) :- sub_atom(T, 0, 2, _, '# '), sub_atom(T, 2, 1, _, D), atom_codes(D, [C]), C >= 0'0, C =< 0'9.

%% an #include is resolved and READ as the file is parsed (library(ccl_include)),
%% so its typedef names are known to the rest of this file
ccl_external(Env0, Env, include(L, Spec, R)) --> [tok(pp, Text, L)], { ccl_include_spec(Text, Spec) }, !,
    { ccl_include(Spec, R), ccl_include_typedefs(R, Env0, Env), ccl_include_macros(R), ccl_include_scope(R) }.
%% name { members }  at file scope is  typedef struct name { members } name;  (owner's rule)
ccl_external(Env0, [N|Env0], T) --> ccl_line(L), ccl_id(N), ccl_peek(p, '{'), !,
    ccl_p('{'), ccl_members(Env0, Ms), ccl_p('}'), ( ccl_p(';'), ! ; [] ),
    { T = typedef(L, [var(N, base([], [struct(N, Ms)]), none)]), ccl_note_item(T) }.
%% name := expr;  declares name with the type inferred from expr (a cocolog operator, on the C surface)
ccl_external(Env, Env, '$splice'(Ds)) --> ccl_line(L), ccl_p('{'), ccl_pattern(P), ccl_p('}'), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_destructure(L, P, E, Ds) }.
ccl_external(Env, Env, D) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_infer_decl(L, N, E, D), ccl_note_item(D) }.
%% a macro call at file scope: name(args) with an optional `;', its result an item (or items)
ccl_external(Env, Env, Item) --> ccl_id(N), ccl_peek(p, '('), { ccl_macro_name(N) }, ccl_p('('), ccl_args(As), ccl_p(')'), { length(As, K), ccl_is_macro(N, K) }, !,
    ( ccl_p(';'), ! ; [] ), { ccl_expand_macro(N, As, Item) }.
ccl_external(Env, Env, directive(L, Text)) --> [tok(pp, Text, L)], !.
ccl_external(Env, Env, empty) --> ccl_p(';'), !.
ccl_external(Env, Env, static_assert(L, E, Msg)) --> ccl_line(L), ccl_kw('_Static_assert'), !, ccl_p('('), ccl_cond_expr(E), ( ccl_p(','), ccl_primary(Msg), ! ; { Msg = none } ), ccl_p(')'), ccl_p(';').
ccl_external(Env0, Env, Item) --> ccl_line(L), ccl_decl_specs(Env0, file, Sto, Base), ccl_external_rest(Env0, Env, L, Sto, Base, Item).

ccl_external_rest(Env, Env, L, Sto, Base, function(L, Sto, Ret, Name, Params, Var, Body)) -->
    ccl_declarator(Env, Base, Name, Type), { Type = fn(Ret, Params, Var) }, ccl_attrs, ccl_peek(p, '{'),
    { ccl_note_tags(Ret), ccl_note_params(Params), ccl_declare(Name, Type) },
    ccl_push_scope, { ccl_declare_params(Params) }, ccl_compound(Env, Body), ccl_pop_scope, !.
ccl_external_rest(Env0, Env, L, Sto, Base, Item) -->
    ccl_init_declarators(Env0, Base, Ds), ccl_attrs, ccl_p(';'), !,
    { Sto == typedef -> ccl_declared_names(Ds, Names), append(Names, Env0, Env), Item = typedef(L, Ds)
    ; Env = Env0, Item = declaration(L, Sto, Base, Ds) }, { ccl_note_item(Item) }.
ccl_external_rest(Env, Env, L, _, Base, declare(L, Base)) --> ccl_p(';'), { ccl_note_item(declare(L, Base)) }.
ccl_declared_names([], []).
ccl_declared_names([var(N, _, _)|Ds], [N|Ns]) :- ccl_declared_names(Ds, Ns).

%% ---- declaration specifiers -------------------------------------------------
%% Scope is file or block: at file scope `name * x;' is a declaration, so an
%% unknown name before `*' is taken as a type there; `name x;' is one anywhere.
ccl_decl_specs(Env, Scope, Sto, base(Quals, Specs)) -->
    ccl_specs(Env, Scope, [], [], [], Sto0, Quals, Specs),
    { Specs \== [], ( Sto0 = [S|_] -> Sto = S ; Sto = none ) }.

ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_storage(K) }, !, ccl_specs(Env, Sc, [K|St0], Q0, S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_qualifier(K) }, !, ccl_specs(Env, Sc, St0, [K|Q0], S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_basic_type(K) }, !, ccl_specs(Env, Sc, St0, Q0, [K|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_struct_spec(Env, T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_enum_spec(T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_gnu_attr, !, ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_typeof(T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, [], St, Q, S) --> ccl_typedef_name(Env, Sc, N), !, ccl_specs(Env, Sc, St0, Q0, [typedef(N)], St, Q, S).
ccl_specs(_, _, St, Q0, S0, St, Q, S) --> [], { reverse(Q0, Q), reverse(S0, S) }.

ccl_storage(K) :- memberchk(K, [typedef, extern, static, auto, register, inline, '_Noreturn', '_Thread_local']).
ccl_qualifier(K) :- memberchk(K, [const, volatile, restrict, '_Atomic']).
ccl_basic_type(K) :- memberchk(K, [void, char, short, int, long, float, double, signed, unsigned, '_Bool', '_Complex']).

%% Scope is file, block, param, member or typename. `name x' is a type
%% anywhere. `name *' is a type wherever an expression cannot stand: at file
%% scope, in a parameter list, in a struct, in a cast or sizeof -- everywhere
%% but a block, where `a * b;' is arithmetic.
ccl_typedef_name(Env, _, N) --> ccl_id(N), { ccl_known_typedef(Env, N) }, !.
ccl_typedef_name(_, _, N) --> ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_peek(id, M), { \+ ccl_gnu_word(M) }, !.   % name x
ccl_typedef_name(_, Sc, N) --> { memberchk(Sc, [file, param, member]) }, ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_peek(p, '*'), !.   % name * x
%% in a cast or sizeof, `(name *' is a type only when the star is the last
%% thing before `)' -- or another star, a qualifier or `[' -- because `(x * y)'
%% is a product, and so is `(x * y[0])'
ccl_typedef_name(_, typename, N) --> ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_stars_then_end, !.
ccl_stars_then_end(S, S) :- S = [tok(p, '*', _)|T], ccl_stars_end(T).
ccl_stars_end([tok(p, '*', _)|T]) :- !, ccl_stars_end(T).
ccl_stars_end([tok(kw, Q, _)|T]) :- ccl_qualifier(Q), !, ccl_stars_end(T).
ccl_stars_end([tok(p, V, _)|_]) :- memberchk(V, [')', '[', ',']).
%% `(name)' followed by `{' is a compound literal of that type, and `(name)'
%% followed by a name or a literal is a cast -- neither can be an expression
%% in parentheses, so the name is a type from a header the reader has not seen
ccl_typedef_name(_, typename, N) --> ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_cast_ahead, !.
ccl_cast_ahead(S, S) :- S = [tok(p, ')', _), tok(K, V, _)|_], ( K == p, V == '{' ; memberchk(K, [id, int, float, str, chr]) ).
%% `(name[' with an empty pair, or with the brackets closed and then `) {',
%% is an array type in a compound literal: an index would need an expression
ccl_typedef_name(_, typename, N) --> ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_array_type_ahead, !.
ccl_array_type_ahead(S, S) :- S = [tok(p, '[', _), tok(p, ']', _)|_], !.
ccl_array_type_ahead(S, S) :- S = [tok(p, '[', _)|T], ccl_skip_brackets(T, R), R = [tok(p, ')', _), tok(p, '{', _)|_].
ccl_skip_brackets([tok(p, ']', _)|T], T) :- !.
ccl_skip_brackets([tok(p, '[', _)|T], R) :- !, ccl_skip_brackets(T, T1), ccl_skip_brackets(T1, R).
ccl_skip_brackets([_|T], R) :- ccl_skip_brackets(T, R).
%% in a block, `name * name' followed by `=' `;' `,' `[' or an attribute is a
%% declaration of a pointer -- `a * b = c' is no expression -- so the name is
%% a type; `a * b;' alone stays a product, as a C compiler would read it too
ccl_typedef_name(_, block, N) --> ccl_id(N), { \+ ccl_gnu_word(N) }, ccl_ptr_decl_ahead, !.
ccl_ptr_decl_ahead(S, S) :- S = [tok(p, '*', _)|T], ccl_ptr_decl_rest(T).
ccl_ptr_decl_rest([tok(p, '*', _)|T]) :- !, ccl_ptr_decl_rest(T).
ccl_ptr_decl_rest([tok(kw, Q, _)|T]) :- ccl_qualifier(Q), !, ccl_ptr_decl_rest(T).
ccl_ptr_decl_rest([tok(id, _, _), tok(K, V, _)|_]) :- ( K == p, memberchk(V, ['=', ',', '[']) ; K == id, ccl_gnu_word(V) ).
%% the GNU words that are never a type name; other __names (__builtin_va_list,
%% __int128, __darwin_size_t) are typedefs and types like any other
ccl_gnu_word(W) :- memberchk(W, ['__attribute__', '__attribute', '__extension__', '__inline__', '__inline',
    '__restrict', '__restrict__', '__volatile__', '__const', '__asm', '__asm__', '__typeof__', '__typeof',
    typeof, '_Nonnull', '_Nullable', '_Null_unspecified', '__nonnull', '__nullable', '__null_unspecified']).

%% GNU's typeof(expr) or typeof(type), a type specifier; Cicili's `let' emits it
ccl_typeof(typeof(X)) --> ccl_id(T), { memberchk(T, [typeof, '__typeof__', '__typeof']) }, ccl_p('('),
    ( ccl_type_name([], X), ccl_peek(p, ')'), ! ; ccl_expr(X) ), ccl_p(')').

%% GNU's __attribute__((...)), __extension__ and friends: read and dropped,
%% because Cicili's own emitted C carries them (cleanup, unused, ...)
ccl_attrs --> ccl_gnu_attr, !, ccl_attrs.
ccl_attrs --> [].
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__attribute__', '__attribute']) }, !, ccl_p('('), ccl_p('('), ccl_balanced, ccl_p(')'), ccl_p(')').
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__asm', '__asm__']) }, !, ccl_p('('), ccl_balanced, ccl_p(')').   % int f(void) __asm("_f")
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__extension__', '__inline__', '__inline', '__restrict', '__restrict__', '__volatile__', '__const',
                                             '_Nonnull', '_Nullable', '_Null_unspecified', '__nonnull', '__nullable', '__null_unspecified']) }.
ccl_balanced --> ccl_p('('), !, ccl_balanced, ccl_p(')'), ccl_balanced.
ccl_balanced --> [tok(K, V, _)], { \+ ( K == p, ( V == '(' ; V == ')' ) ) }, !, ccl_balanced.
ccl_balanced --> [].

ccl_struct_spec(Env, T) --> ccl_kw(K), { K == struct ; K == union }, !, ccl_struct_body(Env, K, T).
ccl_struct_body(Env, K, T) --> ccl_attrs, ccl_id(N), !, ( ccl_p('{'), !, ccl_members(Env, Ms), ccl_p('}'), ccl_attrs, { T =.. [K, N, Ms] } ; { T =.. [K, N, none] } ).
ccl_struct_body(Env, K, T) --> ccl_attrs, ccl_p('{'), ccl_members(Env, Ms), ccl_p('}'), ccl_attrs, { T =.. [K, anon, Ms] }.
ccl_members(Env, Ms) --> [tok(pp, _, _)], !, ccl_members(Env, Ms).          % a #define inside a struct body (clang -E -dD keeps them)
ccl_members(Env, Ms) --> ccl_member_decl(Env, M), !, ccl_members(Env, Ms1), { append(M, Ms1, Ms) }.
ccl_members(_, []) --> [].
ccl_member_decl(Env, Ms) --> ccl_decl_specs(Env, member, _, Base), ccl_member_declarators(Env, Base, Ms), ccl_p(';').
ccl_member_declarators(Env, Base, Ms) --> [tok(pp, _, _)], !, ccl_member_declarators(Env, Base, Ms).   % a #define between two declarators
ccl_member_declarators(Env, Base, [M|Ms]) --> ccl_member_declarator(Env, Base, M), ( ccl_p(','), !, ccl_member_declarators(Env, Base, Ms) ; { Ms = [] } ).
ccl_member_declarators(_, _, []) --> [].
ccl_member_declarator(Env, Base, member(T, N, Bits)) --> ccl_declarator(Env, Base, N, T), ( ccl_p(':'), !, ccl_cond_expr(Bits) ; { Bits = none } ).
ccl_member_declarator(_, Base, member(Base, anon, Bits)) --> ccl_p(':'), ccl_cond_expr(Bits).

ccl_enum_spec(enum(N, Es)) --> ccl_kw(enum), ( ccl_id(N), ! ; { N = anon } ), ( ccl_p('{'), !, ccl_enumerators(Es), ccl_p('}') ; { Es = none } ).
ccl_enumerators(Es) --> [tok(pp, _, _)], !, ccl_enumerators(Es).             % a #define among the enumerators
ccl_enumerators([E|Es]) --> ccl_enumerator(E), ( ccl_p(','), !, ccl_enumerators(Es) ; { Es = [] } ).
ccl_enumerators([]) --> [].
ccl_enumerator(enumerator(N, V)) --> ccl_id(N), ( ccl_p('='), !, ccl_cond_expr(V) ; { V = none } ).

%% ---- declarators ------------------------------------------------------------
%% Parsed inside-out the way C means them: pointers, then the direct part,
%% then array and function suffixes; ccl_mk_type folds them onto the base.
ccl_init_declarators(Env, Base, Ds) --> [tok(pp, _, _)], !, ccl_init_declarators(Env, Base, Ds).
ccl_init_declarators(Env, Base, [D|Ds]) --> ccl_init_declarator(Env, Base, D), ( ccl_p(','), !, ccl_init_declarators(Env, Base, Ds) ; { Ds = [] } ).
ccl_init_declarator(Env, Base, var(N, T, Init)) --> ccl_declarator(Env, Base, N, T), ccl_attrs, ( ccl_p('='), !, ccl_initializer(Init) ; { Init = none } ).

ccl_declarator(Env, Base, Name, Type) --> ccl_decl_syntax(Env, D), { ccl_mk_type(D, Base, Name, Type) }.
ccl_abstract_or_declarator(Env, Base, Name, Type) --> ccl_decl_syntax(Env, D), !, { ccl_mk_type(D, Base, Name, Type) }.
ccl_abstract_or_declarator(_, Base, anon, Base) --> [].

ccl_decl_syntax(Env, decl(Ptrs, Direct, Sfx)) --> ccl_pointers(Ptrs), ccl_direct(Env, Direct), ccl_suffixes(Env, Sfx), { Direct \== none ; Ptrs \== [] ; Sfx \== [] }.
ccl_pointers([ptr(Qs)|Ps]) --> ccl_p('*'), !, ccl_quals(Qs), ccl_pointers(Ps).
ccl_pointers([block(Qs)|Ps]) --> ccl_p('^'), !, ccl_quals(Qs), ccl_pointers(Ps).   % Apple's block pointer, (^f)(int)
ccl_pointers([]) --> [].
ccl_quals([Q|Qs]) --> ccl_kw(Q), { ccl_qualifier(Q) }, !, ccl_quals(Qs).
ccl_quals(Qs) --> ccl_gnu_attr, !, ccl_quals(Qs).             % char * _Nonnull p, char * __restrict q
ccl_quals([]) --> [].
ccl_direct(_, name(N)) --> ccl_id(N), !.
ccl_direct(Env, paren(D)) --> ccl_p('('), ccl_decl_syntax(Env, D), ccl_p(')'), !.
ccl_direct(_, none) --> [].
ccl_suffixes(Env, [S|Ss]) --> ccl_suffix(Env, S), !, ccl_suffixes(Env, Ss).
ccl_suffixes(_, []) --> [].
ccl_suffix(_, arr(N)) --> ccl_p('['), ( ccl_p(']'), !, { N = none } ; ccl_quals(_), ( ccl_cond_expr(N), ! ; { N = none } ), ccl_p(']') ).
ccl_suffix(Env, fn(Ps, Var)) --> ccl_p('('), ccl_params(Env, Ps, Var), ccl_p(')').

ccl_params(_, [], false) --> ccl_kw(void), ccl_peek(p, ')'), !.
ccl_params(Env, Ps, Var) --> ccl_param_list(Env, Ps, Var), !.
ccl_params(_, [], false) --> [].
ccl_param_list(_, [], true) --> ccl_p('...'), !.
ccl_param_list(Env, [P|Ps], Var) --> ccl_param(Env, P), ( ccl_p(','), !, ccl_param_list(Env, Ps, Var) ; { Ps = [], Var = false } ).
ccl_param(Env, param(T, N)) --> ccl_decl_specs(Env, param, _, Base), ccl_abstract_or_declarator(Env, Base, N, T), ccl_attrs.

ccl_mk_type(decl(Ptrs, Direct, Sfx), Base, Name, Type) :-
    ccl_apply_pointers(Ptrs, Base, T1),
    ccl_apply_suffixes(Sfx, T1, T2),
    ( Direct = name(Name) -> Type = T2
    ; Direct = paren(D) -> ccl_mk_type(D, T2, Name, Type)
    ; Name = anon, Type = T2 ).
ccl_apply_pointers([], T, T).
ccl_apply_pointers([ptr(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, ptr(Q, T0), T).
ccl_apply_pointers([block(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, block(Q, T0), T).
ccl_apply_suffixes([], T, T).
ccl_apply_suffixes([S|Ss], T0, T) :- ccl_apply_suffixes(Ss, T0, T1), ccl_wrap_suffix(S, T1, T).
ccl_wrap_suffix(arr(N), T, arr(N, T)).
ccl_wrap_suffix(fn(Ps, V), T, fn(T, Ps, V)).

%% a type name, in casts and sizeof
ccl_type_name(Env, T) --> ccl_decl_specs(Env, typename, _, Base), ccl_abstract_or_declarator(Env, Base, _, T).

%% ---- initializers -----------------------------------------------------------
ccl_initializer(init(Items)) --> ccl_p('{'), !, ccl_init_items(Items), ccl_p('}').
ccl_initializer(E) --> ccl_assign_expr(E).
ccl_init_items([I|Is]) --> ccl_init_item(I), !, ( ccl_p(','), !, ccl_init_items(Is) ; { Is = [] } ).
ccl_init_items([]) --> [].
ccl_init_item(item(Ds, V)) --> ccl_designators(Ds), { Ds \== [] }, !, ccl_p('='), ccl_initializer(V).
ccl_init_item(item([], V)) --> ccl_initializer(V).
ccl_designators([D|Ds]) --> ccl_designator(D), !, ccl_designators(Ds).
ccl_designators([]) --> [].
ccl_designator(field(N)) --> ccl_p('.'), ccl_id(N).
ccl_designator(at(E)) --> ccl_p('['), ccl_cond_expr(E), ccl_p(']').

%% ---- statements -------------------------------------------------------------
ccl_compound(Env, block(Items)) --> ccl_p('{'), ccl_push_scope, ccl_block_items(Env, Items), ccl_p('}'), ccl_pop_scope.
ccl_block_items(Env0, Items) --> ccl_block_item(Env0, Env1, I), !, ccl_set_env(Env1), ccl_block_items(Env1, More), { ccl_splice(I, More, Items) }.
ccl_block_items(_, []) --> [].
ccl_block_item(Env, Env, directive(L, Text)) --> [tok(pp, Text, L)], !.
ccl_block_item(Env, Env, '$splice'(Ds)) --> ccl_line(L), ccl_p('{'), ccl_pattern(P), ccl_p('}'), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_destructure(L, P, E, Ds) }.
ccl_block_item(Env, Env, D) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_infer_decl(L, N, E, D), ccl_note_item(D) }.
ccl_block_item(Env0, Env, I) --> ccl_line(L), ccl_decl_specs(Env0, block, Sto, Base), ccl_init_declarators(Env0, Base, Ds), ccl_p(';'), !,
    { Sto == typedef -> ccl_declared_names(Ds, Ns), append(Ns, Env0, Env), I = typedef(L, Ds)
    ; Env = Env0, I = declaration(L, Sto, Base, Ds) }, { ccl_note_item(I) }.
ccl_block_item(Env, Env, declare(L, Base)) --> ccl_line(L), ccl_decl_specs(Env, block, _, Base), ccl_p(';'), !, { ccl_note_item(declare(L, Base)) }.
ccl_block_item(Env, Env, S) --> ccl_statement(Env, S).

ccl_statement(Env, S) --> ccl_compound(Env, S), !.
ccl_statement(Env, if(C, T, E)) --> ccl_kw(if), !, ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_statement(Env, T), ( ccl_kw(else), !, ccl_statement(Env, E) ; { E = none } ).
ccl_statement(Env, while(C, S)) --> ccl_kw(while), !, ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_statement(Env, S).
ccl_statement(Env, do(S, C)) --> ccl_kw(do), !, ccl_statement(Env, S), ccl_kw(while), ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_p(';').
ccl_statement(Env, for(Init, Cond, Step, S)) --> ccl_kw(for), !, ccl_p('('), ccl_for_init(Env, Init), ccl_opt_expr(Cond), ccl_p(';'), ccl_opt_expr(Step), ccl_p(')'), ccl_statement(Env, S).
ccl_statement(_, return(E)) --> ccl_kw(return), ccl_expr(E), !, ccl_p(';').
ccl_statement(_, return) --> ccl_kw(return), !, ccl_p(';').
ccl_statement(_, break) --> ccl_kw(break), !, ccl_p(';').
ccl_statement(_, continue) --> ccl_kw(continue), !, ccl_p(';').
ccl_statement(_, goto(L)) --> ccl_kw(goto), !, ccl_id(L), ccl_p(';').
ccl_statement(Env, switch(E, S)) --> ccl_kw(switch), !, ccl_p('('), ccl_expr(E), ccl_p(')'), ccl_statement(Env, S).
ccl_statement(Env, case(E, S)) --> ccl_kw(case), !, ccl_cond_expr(E), ccl_p(':'), ccl_statement(Env, S).
ccl_statement(Env, default(S)) --> ccl_kw(default), !, ccl_p(':'), ccl_statement(Env, S).
%% defer(a, b) { body }  runs body at every exit of the enclosing scope, last
%% registered first, over the named variables as they then are (owner's rule:
%% scope-bound, like Cicili's cleanup); a call is never followed by a block
ccl_statement(Env, defer(L, Vars, Body)) --> ccl_line(L), ccl_id(defer), ccl_p('('), ccl_defer_vars(Vars), ccl_p(')'), ccl_peek(p, '{'), !, ccl_compound(Env, Body).
ccl_statement(Env, label(L, S)) --> ccl_id(L), ccl_p(':'), !, ccl_statement(Env, S).
ccl_statement(_, empty) --> ccl_p(';'), !.
ccl_statement(_, S) --> ccl_expr(E), ccl_p(';'), { ccl_stmt_of(E, S) }.   % a macro's result may be a statement

ccl_defer_vars([id(V)|Vs]) --> ccl_id(V), ( ccl_p(','), !, ccl_defer_vars(Vs) ; { Vs = [] } ).
ccl_defer_vars([]) --> [].
ccl_for_init(_, decl(Base, Ds)) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_infer_decl(L, N, E, D), D = declaration(_, _, Base, Ds), ccl_note_item(D) }.
ccl_for_init(Env, decl(Base, Ds)) --> ccl_decl_specs(Env, block, _, Base), ccl_init_declarators(Env, Base, Ds), ccl_p(';'), !, { ccl_note_item(declaration(0, none, Base, Ds)) }.
ccl_for_init(_, E) --> ccl_opt_expr(E), ccl_p(';').
ccl_opt_expr(E) --> ccl_expr(E), !.
ccl_opt_expr(none) --> [].

%% ---- expressions, by precedence ----------------------------------------------
ccl_expr(E) --> ccl_assign_expr(A), ( ccl_p(','), !, ccl_expr(B), { E = comma(A, B) } ; { E = A } ).

ccl_assign_expr(assign(Op, L, R)) --> ccl_unary(L), ccl_assign_op(Op), !, ccl_assign_expr(R).
ccl_assign_expr(E) --> ccl_cond_expr(E).
ccl_assign_op(Op) --> ccl_p(Op), { memberchk(Op, ['=', '*=', '/=', '%=', '+=', '-=', '<<=', '>>=', '&=', '^=', '|=']) }.

ccl_cond_expr(E) --> ccl_lor(C), ( ccl_p('?'), !, ccl_expr(A), ccl_p(':'), ccl_cond_expr(B), { E = cond(C, A, B) } ; { E = C } ).

ccl_lor(E)   --> ccl_land(A), ccl_lor_(A, E).
ccl_lor_(A, E)   --> ccl_p('||'), !, ccl_land(B), ccl_lor_(bin('||', A, B), E).
ccl_lor_(E, E)   --> [].
ccl_land(E)  --> ccl_bor(A), ccl_land_(A, E).
ccl_land_(A, E)  --> ccl_p('&&'), !, ccl_bor(B), ccl_land_(bin('&&', A, B), E).
ccl_land_(E, E)  --> [].
ccl_bor(E)   --> ccl_bxor(A), ccl_bor_(A, E).
ccl_bor_(A, E)   --> ccl_p('|'), !, ccl_bxor(B), ccl_bor_(bin('|', A, B), E).
ccl_bor_(E, E)   --> [].
ccl_bxor(E)  --> ccl_band(A), ccl_bxor_(A, E).
ccl_bxor_(A, E)  --> ccl_p('^'), !, ccl_band(B), ccl_bxor_(bin('^', A, B), E).
ccl_bxor_(E, E)  --> [].
ccl_band(E)  --> ccl_equality(A), ccl_band_(A, E).
ccl_band_(A, E)  --> ccl_p('&'), !, ccl_equality(B), ccl_band_(bin('&', A, B), E).
ccl_band_(E, E)  --> [].
ccl_equality(E) --> ccl_relational(A), ccl_equality_(A, E).
ccl_equality_(A, E) --> ccl_p(Op), { Op == '==' ; Op == '!=' }, !, ccl_relational(B), ccl_equality_(bin(Op, A, B), E).
ccl_equality_(E, E) --> [].
ccl_relational(E) --> ccl_shift(A), ccl_relational_(A, E).
ccl_relational_(A, E) --> ccl_p(Op), { memberchk(Op, ['<', '>', '<=', '>=']) }, !, ccl_shift(B), ccl_relational_(bin(Op, A, B), E).
ccl_relational_(E, E) --> [].
ccl_shift(E) --> ccl_additive(A), ccl_shift_(A, E).
ccl_shift_(A, E) --> ccl_p(Op), { Op == '<<' ; Op == '>>' }, !, ccl_additive(B), ccl_shift_(bin(Op, A, B), E).
ccl_shift_(E, E) --> [].
ccl_additive(E) --> ccl_multiplicative(A), ccl_additive_(A, E).
ccl_additive_(A, E) --> ccl_p(Op), { Op == '+' ; Op == '-' }, !, ccl_multiplicative(B), ccl_additive_(bin(Op, A, B), E).
ccl_additive_(E, E) --> [].
ccl_multiplicative(E) --> ccl_cast_expr(A), ccl_multiplicative_(A, E).
ccl_multiplicative_(A, E) --> ccl_p(Op), { memberchk(Op, ['*', '/', '%']) }, !, ccl_cast_expr(B), ccl_multiplicative_(bin(Op, A, B), E).
ccl_multiplicative_(E, E) --> [].

%% a cast needs a type after `(', which an expression in parentheses never
%% is; the same shape followed by `{' is C99's compound literal, (T){ ... },
%% which is a postfix expression and may be followed by `.x' and the rest
ccl_cast_expr(E) --> ccl_p('('), ccl_type_name([], T), ccl_p(')'), ccl_peek(p, '{'), !, ccl_initializer(I), ccl_postfix_(compound_lit(T, I), E).
ccl_cast_expr(cast(T, E)) --> ccl_p('('), ccl_type_name([], T), ccl_p(')'), !, ccl_cast_expr(E).
ccl_cast_expr(E) --> ccl_unary(E).

ccl_unary(preinc(E)) --> ccl_p('++'), !, ccl_unary(E).
ccl_unary(predec(E)) --> ccl_p('--'), !, ccl_unary(E).
ccl_unary(addr(E))   --> ccl_p('&'), !, ccl_cast_expr(E).
ccl_unary(deref(E))  --> ccl_p('*'), !, ccl_cast_expr(E).
ccl_unary(pos(E))    --> ccl_p('+'), !, ccl_cast_expr(E).
ccl_unary(neg(E))    --> ccl_p('-'), !, ccl_cast_expr(E).
ccl_unary(bitnot(E)) --> ccl_p('~'), !, ccl_cast_expr(E).
ccl_unary(not(E))    --> ccl_p('!'), !, ccl_cast_expr(E).
ccl_unary(E)         --> ccl_kw(sizeof), !, ( ccl_p('('), ccl_type_name([], T), ccl_p(')'), !, { E = sizeof_type(T) } ; ccl_unary(X), { E = sizeof(X) } ).
ccl_unary(E)         --> ccl_postfix(E).

ccl_postfix(E) --> ccl_primary(P), ccl_postfix_(P, E).
ccl_postfix_(A, E) --> ccl_p('['), !, ccl_expr(I), ccl_p(']'), ccl_postfix_(index(A, I), E).
ccl_postfix_(A, E) --> ccl_p('('), !, ccl_args(As), ccl_p(')'), { ccl_call_or_macro(A, As, C) }, ccl_postfix_(C, E).
ccl_postfix_(A, E) --> ccl_p('.'), !, ccl_id(N), ccl_postfix_(member(A, N), E).
ccl_postfix_(A, E) --> ccl_p('->'), !, ccl_id(N), ccl_postfix_(arrow(A, N), E).
ccl_postfix_(A, E) --> ccl_p('++'), !, ccl_postfix_(postinc(A), E).
ccl_postfix_(A, E) --> ccl_p('--'), !, ccl_postfix_(postdec(A), E).
ccl_postfix_(E, E) --> [].
ccl_args([A|As]) --> ccl_assign_expr(A), !, ( ccl_p(','), !, ccl_args(As) ; { As = [] } ).
ccl_args([]) --> [].

ccl_primary(int(N))   --> [tok(int, N, _)], !.
ccl_primary(float(F)) --> [tok(float, F, _)], !.
ccl_primary(str(S))   --> [tok(str, S0, _)], !, ccl_strings(S0, S).          % "a" "b" is one string
ccl_primary(chr(C))   --> [tok(chr, C, _)], !.
ccl_primary(id(N))    --> ccl_id(N), !.
ccl_primary(stmt_expr(B)) --> ccl_p('('), ccl_peek(p, '{'), !, { nb_getval('$ccl_env', Env) }, ccl_compound(Env, B), ccl_p(')').   % GNU ({ ... })
ccl_primary(E)        --> ccl_p('('), ccl_expr(E), ccl_p(')').
ccl_strings(S0, S) --> [tok(str, S1, _)], !, { append(S0, S1, S2) }, ccl_strings(S2, S).
ccl_strings(S, S) --> [].
