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
%%   '$expansions'([expansion(Line, Macro, Args) ...])   last, when macros expanded: where
%% Types:  base(Quals, Specs) where Specs is the specifier list as written
%%           ([int], [unsigned, long], [struct(Name, Members)], [enum(N, Es)],
%%            [typedef(Name)], [typeof(ExprOrType)] ...); Quals from const volatile restrict _Atomic
%%         ptr(Quals, Type)   block(Quals, Type)   arr(Size, Type)   fn(Ret, Params, Variadic)
%%         Members: [member(Type, Name, Bits) ...]; Params: [param(Type, Name) ...]
%%         Enumerators: [enumerator(Name, Value) ...]
%% Statements, each with its Line first:  block(Items)  if(L, C, Then, Else)
%%   while(L, C, S)  do(L, S, C)  for(L, Init, Cond, Step, S)  return(L, E)
%%   return(L)  break(L)  continue(L)  goto(L, Name)  switch(L, E, S)
%%   case(L, E, S)  default(L, S)  label(L, Name, S)  expr(L, E)  empty
%%   defer(Line, [id(V) ...], Body)   runs Body at every exit of the scope, LIFO
%%   (a macro may write them without the line; ccl_add_lines/3 adds the call's)
%%   and a declaration/4 or typedef/2 or declare/2 as a block item;
%%   `name := expr;' is a declaration/4 with the type inferred from expr, and
%%   `{ a, _, f: b } := expr;' one declaration/4 per binding, from the struct's members
%% Expressions: int(N) float(F) str(Codes) chr(C) id(N) call(F, Args)
%%   index(A, I) member(E, N) arrow(E, N) postinc(E) postdec(E) preinc(E)
%%   predec(E) neg(E) pos(E) not(E) bitnot(E) addr(E) deref(E) sizeof(E)
%%   sizeof_type(T) cast(T, E) bin(Op, A, B) assign(Op, L, R) cond(C, A, B)
%%   comma(A, B) init([item(Designators, Value) ...]) stmt_expr(Block)
%%   compound_lit(Type, init(Items))            C99's (T){ ... }
%%   move(E)                                    the safe part: ownership leaves E (an owner)
%% Owners: `own T *p' is ptr([own|...], T): linear, consumed once on every path
%% (library(ccl_check))
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
ccl_reader_version(32).

%% ---- the lexer: a DCG over codes ------------------------------------------

%% the lexer runs native when library(cicili)'s module is loaded
%% (ccl_lex_native/6 in module/cicili.cicili, the DCG token for token, C
%% speed); '$ccl_lexer' says which, decided once by ccl_ensure_globals
ccl_tokens(Codes, Tokens, Rest) :-
    (   ccl_native_lexer -> atom_codes(A, Codes), ccl_lex_atom_(A, 1, Tokens, Rest)
    ;   phrase(ccl_lex(1, Tokens), Codes, Rest) ).
%% the same over an atom, from a line: the preprocessor's door
ccl_lex_atom(A, L0, Tokens, Rest) :-
    (   ccl_native_lexer -> ccl_lex_atom_(A, L0, Tokens, Rest)
    ;   atom_codes(A, Codes), phrase(ccl_lex(L0, Tokens), Codes, Rest) ).
ccl_lex_atom_(A, L0, Tokens, Rest) :- nb_getval('$ccl_hash', M), nb_getval('$ccl_lang', Lg), ccl_lex_native(A, L0, M, Lg, Tokens, Rest).
ccl_native_lexer :- ccl_global('$ccl_lexer', native, _).

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
ccl_token(L, L, tok(p, '##', L))     --> [35, 35], { nb_getval('$ccl_hash', punct) }, !.      % inside a macro body (the preprocessor's mode): the operators
ccl_token(L, L, tok(p, '#', L))      --> [35], { nb_getval('$ccl_hash', punct) }, !.
ccl_token(L0, L, tok(cocolog, Text, L0)) --> [35], ccl_pp_line(L0, L1, Cs), { ccl_trim(Cs, T), atom_codes(cocolog, T) }, !,   % #cocolog ... #end: the lines between, raw
    ccl_cocolog_body(L1, L, Body), { atom_codes(Text, Body) }.
ccl_token(L0, L, tok(pp, Text, L0)) --> [35], !, ccl_pp_line(L0, L, Cs), { atom_codes(Text, [35|Cs]) }.
ccl_token(L, L, tok(str, S, L))     --> [34], !, ccl_str_body(S).
ccl_token(L, L, tok(chr, C, L))     --> [39], !, ccl_chr_body(C), [39].
ccl_token(L, L, tok(num, Cs, L))    --> [D], { ccl_digit(D), nb_getval('$ccl_hash', punct) }, !, ccl_pp_number(Ds), { Cs = [D|Ds] }.   % the preprocessor's mode: a number as spelled, suffix and all, for `##'
ccl_token(L, L, T)                  --> ccl_number(L, T), !.
ccl_token(L, L, T)                  --> ccl_word(L, T), !.
ccl_token(L, L, tok(p, P, L))       --> ccl_punct(P).

%% the body of a #cocolog block: every line up to the `#end' line (or the end
%% of the file), as it stands -- Prolog, not C, so no continuation, no comment
ccl_cocolog_body(L0, L, Body) --> ccl_line_codes(Cs, NL), { ( NL == yes -> L1 is L0 + 1 ; L1 = L0 ) }, ccl_cocolog_rest(Cs, NL, L1, L, Body).
ccl_cocolog_rest(Cs, _, L, L, []) --> { ccl_trim(Cs, T), atom_codes('#end', T) }, !.
ccl_cocolog_rest(Cs, no, L, L, Cs) --> !.                                  % the file ended inside the block
ccl_cocolog_rest(Cs, yes, L0, L, Body) --> ccl_cocolog_body(L0, L, Rest), { append(Cs, [10|Rest], Body) }.
ccl_line_codes([], yes) --> [10], !.
ccl_line_codes([C|Cs], NL) --> [C], !, ccl_line_codes(Cs, NL).
ccl_line_codes([], no) --> [].
ccl_trim(Cs, T) :- ccl_drop_ws(Cs, Cs1), reverse(Cs1, R), ccl_drop_ws(R, R1), reverse(R1, T).
ccl_drop_ws([C|Cs], T) :- ( C =:= 32 ; C =:= 9 ; C =:= 13 ), !, ccl_drop_ws(Cs, T).
ccl_drop_ws(Cs, Cs).

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
%% a pp-number: digits, letters, dots, and a sign after an exponent letter
ccl_pp_number([E, S|Cs]) --> [E, S], { ( E =:= 0'e ; E =:= 0'E ; E =:= 0'p ; E =:= 0'P ), ( S =:= 0'+ ; S =:= 0'- ) }, !, ccl_pp_number(Cs).
ccl_pp_number([C|Cs]) --> [C], { ( ccl_alnum(C) ; C =:= 0'. ) }, !, ccl_pp_number(Cs).
ccl_pp_number([]) --> [].
ccl_alnums([]) --> [].
ccl_alpha(C) :- ( C >= 0'a, C =< 0'z ; C >= 0'A, C =< 0'Z ; C =:= 0'_ ).
ccl_alnum(C) :- ( ccl_alpha(C) ; ccl_digit(C) ).

ccl_keyword(K) :- ccl_c_keyword(K), !.
ccl_keyword(K) :- ccl_lang(cpp), ccl_cpp_keyword(K).
ccl_c_keyword(K) :- memberchk(K, [auto, break, case, char, const, continue, default, do, double, else,
    enum, extern, float, for, goto, if, inline, int, long, register, restrict, return, short,
    signed, sizeof, static, struct, switch, typedef, union, unsigned, void, volatile, while,
    '_Bool', '_Complex', '_Noreturn', '_Atomic', '_Static_assert', '_Thread_local', '_Float16']).
%% ---- C++ (M5, cicili++): the mode -------------------------------------------
%% '$ccl_lang' is c or cpp: from the file's extension (ccl_read_file: .cpp .cc
%% .cxx .C .hpp .hh .hxx) or forced by the driver (cicili++ reads everything as
%% C++). Every C++ rule below is guarded by ccl_cpp, so a .c reads as it did.
%% `override' and `final' stay identifiers, contextual as in C++.
ccl_lang(L) :- nb_getval('$ccl_lang', L).
ccl_cpp --> { ccl_lang(cpp) }.
ccl_cpp_keyword(K) :- memberchk(K, [bool, class, namespace, template, typename, this, new, delete, operator, using,
    public, private, protected, virtual, friend, true, false, nullptr, try, catch, throw, static_cast, dynamic_cast,
    reinterpret_cast, const_cast, explicit, mutable, constexpr, noexcept, decltype, typeid, wchar_t, char16_t, char32_t,
    thread_local, alignas, alignof, static_assert,
    concept, requires, co_await, co_yield, co_return, consteval, constinit, char8_t]).                % C++20

%% punctuators, longest first
ccl_punct(P) --> "...", !, { P = '...' }.
ccl_punct(P) --> ">>=", !, { P = '>>=' }.
ccl_punct(P) --> ":=", !, { P = ':=' }.
ccl_punct(P) --> "<=>", !, { P = '<=>' }.                                      % C++20's three-way comparison
ccl_punct(P) --> "<<=", !, { P = '<<=' }.
ccl_punct(P) --> "<*>", !, { P = '<*>' }.
ccl_punct(P) --> "::", { ccl_lang(cpp) }, !, { P = '::' }.      % C++'s scope, never in C        % the tie operator: x <*> y, x lives within y (no C reads <*>)
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

ccl_unit(Tokens, unit(Items), Rest) :-
    ccl_ensure_globals, ccl_seed_typedefs(Env), nb_setval('$ccl_env', Env), nb_setval('$ccl_far', 0), nb_setval('$ccl_macros', []), nb_setval('$ccl_expansions', []),
    ccl_standard_macros, ccl_scope_init,
    phrase(ccl_externals(Env, Items0), Tokens, Rest),
    nb_getval('$ccl_expansions', Es0),
    ( Es0 == [] -> Items = Items0 ; reverse(Es0, Es), append(Items0, ['$expansions'(Es)], Items) ).

%% ---- name := expr ---------------------------------------------------------------
%% The type is ccl_type_of/2's (library(ccl_infer)) over the scope as it stands:
%% arrays and functions decay to pointers, top-level qualifiers are dropped
%% (the new variable is its own), and a type that cannot be inferred is an
%% error naming the variable, the expression and the place.
ccl_infer_decl(L, N, E, D) :- ccl_infer_decl(L, N, E, none, D).
ccl_infer_decl(L, N, E, Tie, declaration(L, none, Base, [var(N, T, E)])) :-        % Tie: none, or the name after <*>
    ccl_type_of(E, T0),
    ( T0 == unknown -> ccl_here(F, _), throw(error(cannot_infer(N, E), here(F, L))) ; true ),
    ccl_decay(T0, T1), ccl_strip_quals(T1, T2), ( Tie == none -> T = T2 ; ccl_add_tie(Tie, T2, T) ), ccl_base_of(T, Base).
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
ccl_scope_init :- ccl_tables_changed, nb_setval('$ccl_scope', []), nb_setval('$ccl_gscope', []), nb_setval('$ccl_typedefs', []), nb_setval('$ccl_tags', []), nb_setval('$ccl_enums', []).
ccl_push_scope --> { ccl_scope_push }.
ccl_pop_scope --> { ccl_scope_pop }.
ccl_scope_push :- nb_getval('$ccl_scope', S), nb_setval('$ccl_scope', [[]|S]).
ccl_scope_pop :- nb_getval('$ccl_scope', S), ( S = [_|S1] -> nb_setval('$ccl_scope', S1) ; true ).
ccl_note_items([]).
ccl_note_items([I|Is]) :- ccl_note_item(I), ccl_note_items(Is).
%% the file scope is a global of its own, '$ccl_gscope': nb_getval/2 copies what
%% it answers, and the frame holds the headers' hundreds of names -- a local
%% declared or looked up must not copy them (the check declared 250 locals
%% and asked 600 names of the B-tree: 0.14 ms each)
ccl_declare(N, T) :- nb_getval('$ccl_scope', S), ( S = [F|S1] -> nb_setval('$ccl_scope', [[N-T|F]|S1]) ; ccl_gdeclare([N-T]) ).
ccl_gdeclare(Ds) :- nb_getval('$ccl_gscope', G), append(Ds, G, G1), nb_setval('$ccl_gscope', G1), nb_setval('$ccl_gcache', []).
%% a list of declarations into the innermost frame -- the file scope's when no frame is open
ccl_scope_add(Ds) :- nb_getval('$ccl_scope', S), ( S = [F|S1] -> append(Ds, F, F1), nb_setval('$ccl_scope', [F1|S1]) ; ccl_gdeclare(Ds) ).
ccl_note_typedef(N, T) :- nb_getval('$ccl_typedefs', L), nb_setval('$ccl_typedefs', [N-T|L]), ccl_tables_changed.
ccl_note_tag(Tag, Ms) :- nb_getval('$ccl_tags', L), nb_setval('$ccl_tags', [Tag-Ms|L]), ccl_tables_changed.
%% the answer caches of ccl_typedef_of/2, ccl_tag/2 and ccl_members_layout/4 (ccl_infer), emptied when a table is written
ccl_tables_changed :-
    ccl_named_caches(Ps), ccl_forget_named(Ps),
    nb_setval('$ccl_laycache', []), nb_setval('$ir_tcache', []), nb_setval('$ir_abicache', []).
ccl_forget_named([]).
ccl_forget_named([P|Ps]) :- atom_concat(P, names, IK), nb_setval(IK, []), ccl_forget_named(Ps).
%% ---- the bulk noter: a whole unit tree into the tables, each set once ------------
%% ccl_note_item/1 above is the parser's, one item at a time. Rebuilding the
%% table from units -- the checker, the lowering, an included unit's scope --
%% notes tens of thousands of items, and nb_setval/2 copies the whole list
%% every time; so the bulk noter collects first and sets each table once.
ccl_items_note(Is) :-
    ccl_collect_items(Is, D, [], T, [], G, [], E, []),
    ccl_scope_add(D),
    nb_getval('$ccl_typedefs', T0), append(T, T0, T1), nb_setval('$ccl_typedefs', T1),
    nb_getval('$ccl_tags', G0), append(G, G0, G1), nb_setval('$ccl_tags', G1), ccl_tables_changed,
    nb_getval('$ccl_enums', E0), append(E, E0, E1), nb_setval('$ccl_enums', E1).
%% accumulators as difference lists: declarations, typedefs, tags, enumerators
ccl_collect_items([], D, D, T, T, G, G, E, E).
ccl_collect_items([I|Is], D0, D, T0, T, G0, G, E0, E) :-
    ccl_collect_item(I, D0, D1, T0, T1, G0, G1, E0, E1),
    ccl_collect_items(Is, D1, D, T1, T, G1, G, E1, E).
ccl_collect_item(include(_, _, file(_, _, U)), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_unit(U, D0, D, T0, T, G0, G, E0, E).
ccl_collect_item(include(_, _, _), D, D, T, T, G, G, E, E) :- !.
ccl_collect_item(declaration(_, _, Base, Vs), D0, D, T, T, G0, G, E0, E) :- !,
    ccl_collect_type(Base, G0, G1, E0, E1), ccl_collect_vars(Vs, D0, D, G1, G, E1, E).
ccl_collect_item(typedef(_, Vs), D, D, T0, T, G0, G, E0, E) :- !, ccl_collect_typedefs(Vs, T0, T, G0, G, E0, E).
ccl_collect_item(declare(_, Base), D, D, T, T, G0, G, E0, E) :- !, ccl_collect_type(Base, G0, G, E0, E).
ccl_collect_item(function(_, _, _, Name, _, _, _), D, D, T, T, G, G, E, E) :- \+ atom(Name), !.   % C++: a method defined out of its class
ccl_collect_item(function(_, _, Ret, Name, Ps, V, _), [Name-fn(Ret, Ps, V)|D], D, T, T, G0, G, E0, E) :- !,
    ccl_collect_type(Ret, G0, G1, E0, E1), ccl_collect_params(Ps, G1, G, E1, E).
ccl_collect_item(extern_c(_, Is), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_items(Is, D0, D, T0, T, G0, G, E0, E).      % C++: what the block declares
ccl_collect_item(namespace(_, _, Is), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_items(Is, D0, D, T0, T, G0, G, E0, E).   % by its bare name, for now
ccl_collect_item(template(_, _, I), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_item(I, D0, D, T0, T, G0, G, E0, E).
ccl_collect_item(_, D, D, T, T, G, G, E, E).
ccl_collect_unit(unit(Is), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_items(Is, D0, D, T0, T, G0, G, E0, E).
ccl_collect_unit(partial(U, _, _), D0, D, T0, T, G0, G, E0, E) :- !, ccl_collect_unit(U, D0, D, T0, T, G0, G, E0, E).
ccl_collect_unit(summary(F), D0, D, T0, T, G0, G, E0, E) :- !,                  % a C++ library header's summary (ccl_include)
    ccl_sum_load(F, Ds, Ts, Gs, Es, Tmpls, Names), append(Ds, D, D0), append(Ts, T, T0), append(Gs, G, G0), append(Es, E, E0),
    ccl_note_templates(Tmpls), ccl_add_envs(Names).
ccl_collect_unit(_, D, D, T, T, G, G, E, E).
ccl_collect_vars([], D, D, G, G, E, E).
ccl_collect_vars([var(N, _, _)|Vs], D0, D, G0, G, E0, E) :- \+ atom(N), !, ccl_collect_vars(Vs, D0, D, G0, G, E0, E).   % C++: a member defined out of its class (Counter::made), the class step's
ccl_collect_vars([var(N, Ty, _)|Vs], [N-Ty|D0], D, G0, G, E0, E) :- ccl_collect_type(Ty, G0, G1, E0, E1), ccl_collect_vars(Vs, D0, D, G1, G, E1, E).
ccl_collect_typedefs([], T, T, G, G, E, E).
ccl_collect_typedefs([var(N, Ty, _)|Vs], [N-Ty|T0], T, G0, G, E0, E) :- ccl_collect_type(Ty, G0, G1, E0, E1), ccl_collect_typedefs(Vs, T0, T, G1, G, E1, E).
ccl_collect_params([], G, G, E, E).
ccl_collect_params([param(Ty, _)|Ps], G0, G, E0, E) :- ccl_collect_type(Ty, G0, G1, E0, E1), ccl_collect_params(Ps, G1, G, E1, E).
ccl_collect_params([param(Ty, _, _)|Ps], G0, G, E0, E) :- ccl_collect_type(Ty, G0, G1, E0, E1), ccl_collect_params(Ps, G1, G, E1, E).   % C++: a default argument
ccl_collect_type(base(_, Specs), G0, G, E0, E) :- !, ccl_collect_specs(Specs, G0, G, E0, E).
ccl_collect_type(ptr(_, Ty), G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G, E0, E).
ccl_collect_type(ref(_, Ty), G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G, E0, E).       % C++'s references
ccl_collect_type(rref(_, Ty), G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G, E0, E).
ccl_collect_type(block(_, Ty), G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G, E0, E).
ccl_collect_type(arr(_, Ty), G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G, E0, E).
ccl_collect_type(fn(R, Ps, _), G0, G, E0, E) :- !, ccl_collect_type(R, G0, G1, E0, E1), ccl_collect_params(Ps, G1, G, E1, E).
ccl_collect_type(_, G, G, E, E).
ccl_collect_specs([], G, G, E, E).
ccl_collect_specs([S|Ss], G0, G, E0, E) :- ccl_collect_spec(S, G0, G1, E0, E1), ccl_collect_specs(Ss, G1, G, E1, E).
ccl_collect_spec(class(_, Tag, _, Ms), G0, G, E0, E) :- !, ( Tag == anon -> G1 = G0 ; G0 = [Tag-Ms|G1] ), ccl_collect_members(Ms, G1, G, E0, E).   % C++: a class is a tag too
ccl_collect_spec(struct(Tag, Ms), G0, G, E0, E) :- Ms \== none, !, ( Tag == anon -> G1 = G0 ; G0 = [Tag-Ms|G1] ), ccl_collect_members(Ms, G1, G, E0, E).
ccl_collect_spec(union(Tag, Ms), G0, G, E0, E) :- Ms \== none, !, ( Tag == anon -> G1 = G0 ; G0 = [Tag-Ms|G1] ), ccl_collect_members(Ms, G1, G, E0, E).
ccl_collect_spec(enum(Tag, Es), G0, G, E0, E) :- Es \== none, !, ( Tag == anon -> G = G0 ; G0 = [Tag-Es|G] ), ccl_collect_enumerators(Es, 0, [], E0, E).
ccl_collect_spec(enum_class(Tag, Es), [Tag-Es|G], G, E0, E) :- Es \== none, !, ccl_collect_enumerators(Es, 0, [], E0, E).   % C++
ccl_collect_spec(_, G, G, E, E).
ccl_collect_members([], G, G, E, E).
ccl_collect_members([member(Ty, _, _)|Ms], G0, G, E0, E) :- !, ccl_collect_type(Ty, G0, G1, E0, E1), ccl_collect_members(Ms, G1, G, E1, E).
ccl_collect_members([_|Ms], G0, G, E0, E) :- ccl_collect_members(Ms, G0, G, E0, E).        % a C++ class's methods, labels, defaults
%% enumerators: a value may name an earlier one of the same enum, so the ones
%% met so far are kept in a closed list (never memberchk on the open accumulator:
%% it would bind its tail)
ccl_collect_enumerators([], _, _, E, E).
ccl_collect_enumerators([enumerator(N, Ex)|Es], Next, Sofar, [N-V|E0], E) :-
    ( Ex == none -> V = Next ; ccl_const_eval_in(Ex, Sofar, V0) -> V = V0 ; V = Next ),
    Next1 is V + 1, ccl_collect_enumerators(Es, Next1, [N-V|Sofar], E0, E).
ccl_const_eval_in(id(N), Sofar, V) :- !, ( memberchk(N-V0, Sofar) -> V = V0 ; ccl_enum_value(N, V) ).
ccl_const_eval_in(neg(Ex), Sofar, V) :- !, ccl_const_eval_in(Ex, Sofar, V0), V is -V0.
ccl_const_eval_in(bin(Op, A, B), Sofar, V) :- !, ccl_const_eval_in(A, Sofar, X), ccl_const_eval_in(B, Sofar, Y), ccl_const_op(Op, X, Y, V).
ccl_const_eval_in(cast(_, Ex), Sofar, V) :- !, ccl_const_eval_in(Ex, Sofar, V).
ccl_const_eval_in(Ex, _, V) :- ccl_const_eval(Ex, V).

ccl_note_item(declaration(_, _, Base, Ds)) :- !, ccl_note_tags(Base), ccl_declare_vars(Ds).
ccl_note_item(typedef(_, Ds)) :- !, ccl_note_typedefs(Ds).
ccl_note_item(declare(_, Base)) :- !, ccl_note_tags(Base).
ccl_note_item(function(_, _, _, Name, _, _, _)) :- \+ atom(Name), !.
ccl_note_item(function(_, _, Ret, Name, Ps, V, _)) :- !, ccl_note_tags(Ret), ccl_note_params(Ps), ccl_declare(Name, fn(Ret, Ps, V)).
ccl_note_item(namespace(_, _, Is)) :- !, ccl_note_each(Is).
ccl_note_item(extern_c(_, Is)) :- !, ccl_note_each(Is).
ccl_note_item(template(_, _, I)) :- !, ccl_note_item(I).
ccl_note_each([]).
ccl_note_each([I|Is]) :- ccl_note_item(I), ccl_note_each(Is).
ccl_note_item(_).
ccl_declare_vars([]).
ccl_declare_vars([var(N, _, _)|Ds]) :- \+ atom(N), !, ccl_declare_vars(Ds).
ccl_declare_vars([var(N, T, _)|Ds]) :- ccl_note_tags(T), ccl_declare(N, T), ccl_declare_vars(Ds).
ccl_note_typedefs([]).
ccl_note_typedefs([var(N, T, _)|Ds]) :- ccl_note_tags(T), ccl_note_typedef(N, T), ccl_note_typedefs(Ds).
ccl_note_params([]).
ccl_note_params([param(T, _)|Ps]) :- ccl_note_tags(T), ccl_note_params(Ps).
ccl_note_params([param(T, _, _)|Ps]) :- ccl_note_tags(T), ccl_note_params(Ps).
ccl_declare_params([]).
ccl_declare_params([param(T, N)|Ps]) :- ( N == anon -> true ; ccl_declare(N, T) ), ccl_declare_params(Ps).
ccl_declare_params([param(T, N, _)|Ps]) :- ( N == anon -> true ; ccl_declare(N, T) ), ccl_declare_params(Ps).
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
ccl_note_spec(class(_, Tag, _, Ms)) :- !, ( Tag == anon -> true ; ccl_note_tag(Tag, Ms) ), ccl_note_members(Ms).
ccl_note_spec(enum_class(Tag, Es)) :- Es \== none, !, ccl_note_tag(Tag, Es), ccl_declare_enumerators(Es).
ccl_note_spec(_).
ccl_note_members([]).
ccl_note_members([member(T, _, _)|Ms]) :- !, ccl_note_tags(T), ccl_note_members(Ms).
ccl_note_members([_|Ms]) :- ccl_note_members(Ms).
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
ccl_is_macro(N, K) :- nb_getval('$ccl_macros', Ms), ( K1 is K + 1, memberchk(macro(N, _, K1), Ms) -> true ; memberchk(macro(N, _, dcg), Ms) ).
ccl_macro_name(N) :- nb_getval('$ccl_macros', Ms), memberchk(macro(N, _, _), Ms).
%% a plain macro name/K+1 is called pred(A1..AK, R); a DCG macro name//1 is
%% phrase(pred(R), [A1..AK]): the arguments are the list it parses
%% An error in a macro names both places: where the macro was called in the
%% C file (here(File, Line, ...)) and where it went wrong inside the macro
%% (in_macro(Pred, MacroFile), and the Prolog error itself). An expansion
%% that succeeds is recorded -- expansion(Line, Name, Args) -- and the unit
%% carries them as its last item, '$expansions'(List), so a later refusal of
%% what a macro produced can say so (the driver's `note: expanded from macro').
ccl_expand_macro(N, As, R) :-
    nb_getval('$ccl_macros', Ms), length(As, K), K1 is K + 1,
    ( memberchk(macro(N, P, K1), Ms) -> append(As, [R0], Args), G =.. [P|Args] ; memberchk(macro(N, P, dcg), Ms), G = phrase(N1, As), N1 =.. [P, R0] ),
    ccl_here(File, L), ccl_macro_file(P, MF),
    (   catch(G, E, ( E = error(macro_error(_, here(_, _)), _) -> throw(E) ; throw(error(macro_error(N, As, E), here(File, L, in_macro(P, MF)))) ))
    ->  ( is_list(R0) -> ccl_add_lines(L, '$splice'(R0), R) ; ccl_add_lines(L, R0, R) ),
        ccl_note_expansion(L, N, As)
    ;   throw(error(macro_failed(N, As), here(File, L, in_macro(P, MF)))) ).
ccl_macro_file(P, File) :- ( nb_getval('$ccl_macro_files', L), member(File-Preds, L), memberchk(macro(_, P, _), Preds) -> true ; File = unknown ).
ccl_note_expansion(L, N, As) :- nb_getval('$ccl_expansions', Es), nb_setval('$ccl_expansions', [expansion(L, N, As)|Es]).
ccl_call_or_macro(id(move), [E], move(E)) :- !.                      % the safe part: ownership leaves E
ccl_call_or_macro(id(N), As, R) :- length(As, K), ccl_is_macro(N, K), !, ccl_expand_macro(N, As, R).
ccl_call_or_macro(F, As, call(F, As)).
ccl_stmt_of(L, E, S) :- ccl_is_stmt(E), !, ccl_add_lines(L, E, S).
ccl_stmt_of(L, E, expr(L, E)).
ccl_is_stmt('$splice'(_)).
ccl_is_stmt(T) :- functor(T, F, _), memberchk(F, [block, if, while, do, for, return, break, continue, goto, switch, case, default, label, empty, declaration, typedef, declare, defer]).
%% a macro may write a statement in its short form -- expr(E), if(C, T, E),
%% return(E) ... -- and here it gets the line of the call (declarations and
%% defers written with line 0 too); a lined one is left as it is; the walk
%% goes into blocks, and through expressions into their stmt_expr blocks
ccl_add_lines(_, V, V) :- var(V), !.
ccl_add_lines(L, '$splice'(Is), '$splice'(Js)) :- !, ccl_add_lines_list(L, Is, Js).
ccl_add_lines(L, block(Is), block(Js)) :- !, ccl_add_lines_list(L, Is, Js).
ccl_add_lines(L, expr(E), expr(L, E1)) :- !, ccl_add_lines(L, E, E1).
ccl_add_lines(L, if(C, T, E), if(L, C1, T1, E1)) :- !, ccl_add_lines(L, C, C1), ccl_add_lines(L, T, T1), ccl_add_lines(L, E, E1).
ccl_add_lines(L, while(C, S), while(L, C1, S1)) :- !, ccl_add_lines(L, C, C1), ccl_add_lines(L, S, S1).
ccl_add_lines(L, do(S, C), do(L, S1, C1)) :- !, ccl_add_lines(L, S, S1), ccl_add_lines(L, C, C1).
ccl_add_lines(L, for(I, C, St, S), for(L, I, C1, St1, S1)) :- !, ccl_add_lines(L, C, C1), ccl_add_lines(L, St, St1), ccl_add_lines(L, S, S1).
ccl_add_lines(L, return(E), return(L, E1)) :- !, ccl_add_lines(L, E, E1).
ccl_add_lines(L, return, return(L)) :- !.
ccl_add_lines(L, break, break(L)) :- !.
ccl_add_lines(L, continue, continue(L)) :- !.
ccl_add_lines(L, goto(N), goto(L, N)) :- !.
ccl_add_lines(L, switch(E, S), switch(L, E1, S1)) :- !, ccl_add_lines(L, E, E1), ccl_add_lines(L, S, S1).
ccl_add_lines(L, case(E, S), case(L, E, S1)) :- !, ccl_add_lines(L, S, S1).
ccl_add_lines(L, default(S), default(L, S1)) :- !, ccl_add_lines(L, S, S1).
ccl_add_lines(L, label(N, S), label(L, N, S1)) :- atom(N), !, ccl_add_lines(L, S, S1).
ccl_add_lines(L, declaration(0, St, B, Vs), declaration(L, St, B, Vs1)) :- !, ccl_add_lines_vars(L, Vs, Vs1).
ccl_add_lines(L, defer(0, Vs, B), defer(L, Vs, B1)) :- !, ccl_add_lines(L, B, B1).
ccl_add_lines(L, T, T1) :- compound(T), functor(T, F, _), \+ memberchk(F, [expr, if, while, do, for, return, switch, case, default, label, declaration, defer, typedef, declare]), !,
    T =.. [F|As], ccl_add_lines_list(L, As, Bs), T1 =.. [F|Bs].
ccl_add_lines(_, T, T).
ccl_add_lines_list(_, [], []).
ccl_add_lines_list(L, [X|Xs], [Y|Ys]) :- ( is_list(X) -> ccl_add_lines_list(L, X, Y) ; ccl_add_lines(L, X, Y) ), ccl_add_lines_list(L, Xs, Ys).
ccl_add_lines_vars(_, [], []).
ccl_add_lines_vars(L, [var(N, T, I)|Vs], [var(N, T, I1)|Vs1]) :- ccl_add_lines(L, I, I1), ccl_add_lines_vars(L, Vs, Vs1).
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
ccl_externals(Env0, Items) --> ccl_external(Env0, Env1, I), !, { ( Env1 == Env0 -> true ; nb_setval('$ccl_env', Env1) ) }, ccl_externals(Env1, More), { ccl_splice(I, More, Items) }.
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
ccl_external(Env, Env, D) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_tie_name(Y), ccl_p(';'), { ccl_infer_decl(L, N, E, Y, D), ccl_note_item(D) }.
%% a macro call at file scope: name(args) with an optional `;', its result an item (or items)
ccl_external(Env, Env, Item) --> ccl_id(N), ccl_peek(p, '('), { ccl_macro_name(N) }, ccl_p('('), ccl_args(As), ccl_p(')'), { length(As, K), ccl_is_macro(N, K) }, !,
    ( ccl_p(';'), ! ; [] ), { ccl_expand_macro(N, As, Item) }.
ccl_external(Env, Env, cocolog(L, Text)) --> [tok(cocolog, Text, L)], !, { ccl_cocolog_block(L, Text) }.   % its predicates are macros from here
ccl_external(Env, Env, directive(L, Text)) --> [tok(pp, Text, L)], !.
ccl_external(Env, Env, empty) --> ccl_p(';'), !.
ccl_external(Env, Env, static_assert(L, E, Msg)) --> ccl_line(L), ccl_kw('_Static_assert'), !, ccl_p('('), ccl_cond_expr(E), ( ccl_p(','), ccl_primary(Msg), ! ; { Msg = none } ), ccl_p(')'), ccl_p(';').
%% C++ items: a namespace (its items inside), using, extern "C", a template
%% (its type parameters are type names inside it), `auto' by inference, a
%% constructor or destructor defined out of its class, static_assert
ccl_external(Env, Env, namespace(L, N, Items)) --> ccl_cpp, ccl_line(L), ( ccl_kw(inline) ; [] ), ccl_kw(namespace), !, ccl_attrs, ( ccl_id(N), ! ; { N = anon } ), ccl_p('{'), ccl_externals(Env, Items), ccl_p('}').
ccl_external(Env, Env, using(L, enum(Q))) --> ccl_cpp, ccl_line(L), ccl_kw(using), ccl_kw(enum), !, ccl_qname(Env, type, Q), ccl_p(';').      % C++20: using enum E
ccl_external(Env, Env, using(L, namespace(Q))) --> ccl_cpp, ccl_line(L), ccl_kw(using), ccl_kw(namespace), !, ccl_qname(Env, type, Q), ccl_p(';').
ccl_external(Env0, [T|Env0], typedef(L, [var(T, Type, none)])) --> ccl_cpp, ccl_line(L), ccl_kw(using), ccl_id(T), ccl_p('='), !, ccl_type_name(Env0, Type), ccl_p(';'),
    { ccl_add_env(T), ccl_note_item(typedef(L, [var(T, Type, none)])) }.
ccl_external(Env, Env, using(L, name(Q))) --> ccl_cpp, ccl_line(L), ccl_kw(using), !, ccl_qname(Env, type, Q), ccl_p(';').
ccl_external(Env, Env, extern_c(L, Items)) --> ccl_cpp, ccl_line(L), ccl_kw(extern), [tok(str, S, _)], { ( S = [67] ; S = [67, 43, 43] ) }, !,
    ( ccl_p('{'), !, ccl_externals(Env, Items), ccl_p('}') ; ccl_external(Env, _, I), { Items = [I] } ).
ccl_external(Env0, Env0, template(L, Ps, Item)) --> ccl_cpp, ccl_line(L), ccl_kw(template), !, ccl_tparams(Env0, Ps0, Env1),
    ( ccl_kw(requires), ccl_lor(R), { append(Ps0, [requires(R)], Ps) } ; { Ps = Ps0 } ),        % C++20: a requires-clause on the head, kept with the parameters
    ccl_external(Env1, _, Item), { ccl_template_name(Item, N), ccl_note_template(N) }.
ccl_external(Env, Env, concept(L, N, E)) --> ccl_cpp, ccl_line(L), ccl_kw(concept), !, ccl_id(N), { ccl_note_template(N) }, ccl_p('='), ccl_cond_expr(E), ccl_p(';').   % C++20: concept N = constraint
ccl_external(Env, Env, D) --> ccl_cpp, ccl_line(L), ccl_kw(auto), ccl_id(N), ccl_p('='), !, ccl_expr(E), ccl_p(';'), { ccl_auto_decl(L, N, E, none, D) }.
ccl_external(Env, Env, ctor_def(L, C, Qs, Ps, Inits, Body)) --> ccl_cpp, ccl_line(L), ccl_id(C), ccl_p('::'), ccl_id(C), ccl_p('('), !, ccl_params(Env, Ps, _), ccl_p(')'), ccl_method_quals(Qs), ccl_ctor_inits(Env, Inits), ccl_fn_body(Env, Ps, Body).
ccl_external(Env, Env, dtor_def(L, C, Qs, Body)) --> ccl_cpp, ccl_line(L), ccl_id(C), ccl_p('::'), ccl_p('~'), !, ccl_id(C), ccl_p('('), ccl_p(')'), ccl_method_quals(Qs), ccl_fn_body(Env, [], Body).
ccl_external(Env, Env, static_assert(L, E, Msg)) --> ccl_cpp, ccl_line(L), ccl_kw(static_assert), !, ccl_p('('), ccl_cond_expr(E), ( ccl_p(','), ccl_primary(Msg), ! ; { Msg = none } ), ccl_p(')'), ccl_p(';').
ccl_external(Env0, Env, Item) --> ccl_line(L), ccl_decl_specs(Env0, file, Sto, Base), ccl_external_rest(Env0, Env, L, Sto, Base, Item).
%% template <typename T, int N = 4, class... Ts> -- tparam(type | Type, Name, Default); the names are types in the item
ccl_tparams(Env0, Ps, Env) --> ccl_p('<'), ( ccl_tparam_list(Env0, Ps, Env), ! ; { Ps = [], Env = Env0 } ), ccl_tclose.
ccl_tparam_list(Env0, [P|Ps], Env) --> ccl_tparam(Env0, P, Env1), ( ccl_p(','), !, ccl_tparam_list(Env1, Ps, Env) ; { Ps = [], Env = Env1 } ).
ccl_tparam(Env0, tparam(type, N, D), [N|Env0]) --> ( ccl_kw(typename), ! ; ccl_kw(class) ), !, ( ccl_p('...'), ! ; [] ), ccl_id(N), ( ccl_p('='), !, ccl_type_name([N|Env0], D) ; { D = none } ).
ccl_tparam(Env0, tparam(template, N, none), [N|Env0]) --> ccl_kw(template), !, ccl_p('<'), ccl_skip_to_close, ( ccl_kw(class), ! ; ccl_kw(typename) ), ccl_id(N).
ccl_tparam(Env0, tparam(T, N, D), Env0) --> ccl_decl_specs(Env0, param, _, Base), ccl_abstract_or_declarator(Env0, Base, N, T), ( ccl_p('='), !, ccl_shift(D) ; { D = none } ).
ccl_skip_to_close --> ccl_p('>'), !.
ccl_skip_to_close --> [_], ccl_skip_to_close.
ccl_template_name(concept(_, N, _), N) :- !.
ccl_template_name(function(_, _, _, N, _, _, _), N) :- !.
ccl_template_name(declaration(_, _, _, [var(N, _, _)|_]), N) :- !.
ccl_template_name(declare(_, base(_, [class(_, N, _, _)])), N) :- !.
ccl_template_name(declare(_, base(_, [struct(N, _)])), N) :- !.
ccl_template_name(typedef(_, [var(N, _, _)|_]), N) :- !.
ccl_template_name(_, none).
%% `auto x = e': the type inferred as `:=' infers it, or auto when it cannot be
ccl_auto_decl(L, N, E, R, D) :-
    (   ccl_type_of(E, T0), T0 \== unknown -> ccl_infer_decl(L, N, E, D0), D0 = declaration(L, none, Base, [var(N, T1, E)]), ( R == ref -> T = ref([], T1) ; T = T1 ), D = declaration(L, none, Base, [var(N, T, E)])
    ;   ( R == ref -> T = ref([], base([], [auto])) ; T = base([], [auto]) ), D = declaration(L, none, base([], [auto]), [var(N, T, E)]) ),
    ccl_note_item(D).

ccl_external_rest(Env, Env, L, Sto, Base, function(L, Sto, Ret, Name, Params, Var, Body)) -->
    ccl_declarator(Env, Base, Name, Type0), { Type0 = fn(_, _, _) }, ccl_attrs, ccl_method_quals(_), ccl_tie(Type0, Type), { Type = fn(Ret, Params, Var) }, ccl_peek(p, '{'),   % C++'s const/override after the parameters; no cut here, a prototype falls through
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

ccl_specs(Env, Sc, St0, Q0, [], St, Q, S) --> ccl_cpp, ccl_kw(auto), !, ccl_specs(Env, Sc, St0, Q0, [auto], St, Q, S).   % C++: auto is a type to deduce (C's storage class it is not)
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_storage(K) }, !, ccl_specs(Env, Sc, [K|St0], Q0, S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_qualifier(K) }, !, ccl_specs(Env, Sc, St0, [K|Q0], S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_id(own), !, ccl_specs(Env, Sc, St0, [own|Q0], S0, St, Q, S).   % the safe part's owner
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_kw(K), { ccl_basic_type(K) }, !, ccl_specs(Env, Sc, St0, Q0, [K|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_struct_spec(Env, T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_enum_spec(T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_gnu_attr, !, ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S).
ccl_specs(Env, Sc, St0, Q0, S0, St, Q, S) --> ccl_typeof(T), !, ccl_specs(Env, Sc, St0, Q0, [T|S0], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, [], St, Q, S) --> ccl_cpp, ccl_cpp_type(Env, Sc, T), !, ccl_specs(Env, Sc, St0, Q0, [T], St, Q, S).
ccl_specs(Env, Sc, St0, Q0, [], St, Q, S) --> ccl_typedef_name(Env, Sc, N), !, ccl_specs(Env, Sc, St0, Q0, [typedef(N)], St, Q, S).
%% a C++ type name: `typename Q', `decltype(e)', or a qualified or template
%% name -- typedef(scoped(Path, N)), typedef(tmpl(N, Args)); a plain name is
%% left to the C heuristics, and in a block the name must be followed by what
%% a declarator starts with (`std::cout << x' is an expression)
ccl_cpp_type(Env, _, typedef(Q)) --> ccl_kw(typename), !, ccl_qname(Env, type, Q).
ccl_cpp_type(_, _, decltype(E)) --> ccl_kw(decltype), !, ccl_p('('), ccl_expr(E), ccl_p(')').
ccl_cpp_type(Env, Sc, typedef(Q)) --> ccl_qname(Env, type, Q), { compound(Q) }, ccl_type_follows(Sc).
ccl_type_follows(Sc) --> { memberchk(Sc, [file, param, member, typename]) }, !.
ccl_type_follows(_) --> ( ccl_peek(id, _), ! ; ccl_peek(p, '*'), ! ; ccl_peek(p, '&'), ! ; ccl_peek(p, '&&') ).
%% a qualified name: ::a::b<args>::c -- an atom for a plain name, tmpl(N, Args)
%% for a template-id, scoped(Path, Last) for a chain (global first for a leading
%% ::). Mode type takes `N <' as a template-id when N is a known template or the
%% arguments read as such and end before a declarator; mode expr only when known.
ccl_qname(Env, Mode, Q) --> ccl_p('::'), !, ccl_qseg(Env, Mode, S0), ccl_qrest(Env, Mode, [S0], global, Q).
ccl_qname(Env, Mode, Q) --> ccl_qseg(Env, Mode, S0), ccl_qrest(Env, Mode, [S0], none, Q).
ccl_qrest(Env, Mode, Acc, Lead, Q) --> ccl_p('::'), ccl_qseg(Env, Mode, S), !, ccl_qrest(Env, Mode, [S|Acc], Lead, Q).
ccl_qrest(_, _, [S], none, S) --> !.
ccl_qrest(_, _, [Last|Rev], Lead, scoped(Path, Last)) --> { reverse(Rev, P0), ( Lead == global -> Path = [global|P0] ; Path = P0 ) }.
ccl_qseg(Env, Mode, S) --> ccl_id(N), ( ccl_targs_start(N, Mode), ccl_targs(Env, As), { S = tmpl(N, As) }, ! ; { S = N } ).
ccl_targs_start(N, _) --> ccl_peek(p, '<'), { ccl_known_template(N) }, !.
ccl_targs_start(_, type) --> ccl_targs_ahead.
ccl_targs_ahead(S, S) :- S = [tok(p, '<', _)|T], ccl_skip_targs(T, 1, R), ccl_targs_follow(R).
ccl_skip_targs([tok(p, '<', _)|T], D, R) :- !, D1 is D + 1, ccl_skip_targs(T, D1, R).
ccl_skip_targs([tok(p, '>', _)|T], 1, T) :- !.
ccl_skip_targs([tok(p, '>', _)|T], D, R) :- !, D1 is D - 1, ccl_skip_targs(T, D1, R).
ccl_skip_targs([tok(p, '>>', L)|T], 1, [tok(p, '>', L)|T]) :- !.
ccl_skip_targs([tok(p, '>>', _)|T], D, R) :- !, D1 is D - 2, D1 >= 1, ccl_skip_targs(T, D1, R).
ccl_skip_targs([tok(p, '(', _)|T], D, R) :- !, ccl_skip_parens(T, 1, T1), ccl_skip_targs(T1, D, R).
ccl_skip_targs([tok(p, V, _)|_], _, _) :- memberchk(V, [';', '{', '}']), !, fail.
ccl_skip_targs([_|T], D, R) :- ccl_skip_targs(T, D, R).
ccl_skip_parens([tok(p, '(', _)|T], D, R) :- !, D1 is D + 1, ccl_skip_parens(T, D1, R).
ccl_skip_parens([tok(p, ')', _)|T], 1, T) :- !.
ccl_skip_parens([tok(p, ')', _)|T], D, R) :- !, D1 is D - 1, ccl_skip_parens(T, D1, R).
ccl_skip_parens([_|T], D, R) :- ccl_skip_parens(T, D, R).
ccl_targs_follow([tok(K, V, _)|_]) :- ( K == id ; K == p, memberchk(V, ['*', '&', '&&', '::', ',', ')', '>', '>>', ';', '{', '(']) ; K == kw, ccl_qualifier(V) ), !.
ccl_targs(Env, As) --> ccl_p('<'), ( ccl_targ_list(Env, As), ! ; { As = [] } ), ccl_tclose.
ccl_targ_list(Env, [A|As]) --> ccl_targ(Env, A), ( ccl_p(','), !, ccl_targ_list(Env, As) ; { As = [] } ).
ccl_targ(Env, A) --> ccl_type_name(Env, A), ccl_targ_end, !.
ccl_targ(_, A) --> ccl_shift(A).
ccl_targ_end(S, S) :- S = [tok(p, V, _)|_], memberchk(V, [',', '>', '>>']).
%% the closing `>' of template arguments; a `>>' closes two, so one is left
ccl_tclose(S0, S) :- S0 = [tok(p, '>', _)|S], !.
ccl_tclose([tok(p, '>>', L)|T], [tok(p, '>', L)|T]).
ccl_known_template(N) :- nb_getval('$ccl_templates', Ts), memberchk(N, Ts).
ccl_note_template(N) :- atom(N), nb_getval('$ccl_templates', Ts), ( memberchk(N, Ts) -> true ; nb_setval('$ccl_templates', [N|Ts]) ).
ccl_note_template(_).
%% a class or enum name is a type name from its declaration on, for the unit
ccl_add_env(N) :- nb_getval('$ccl_env', G), ( memberchk(N, G) -> true ; nb_setval('$ccl_env', [N|G]) ).
ccl_specs(_, _, St, Q0, S0, St, Q, S) --> [], { reverse(Q0, Q), reverse(S0, S) }.

ccl_storage(K) :- memberchk(K, [typedef, extern, static, auto, register, inline, '_Noreturn', '_Thread_local', mutable, thread_local, explicit, virtual, friend]).
ccl_qualifier(K) :- memberchk(K, [const, volatile, restrict, '_Atomic', constexpr, consteval, constinit]).
ccl_basic_type(K) :- memberchk(K, [void, char, short, int, long, float, double, signed, unsigned, '_Bool', '_Complex', '_Float16', bool, wchar_t, char16_t, char32_t, char8_t]).   % _Float16: the SDK's math.h, half

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
ccl_gnu_attr --> ccl_cpp, ccl_p('['), ccl_p('['), !, ccl_skip_attr.                         % C++'s [[nodiscard]] and kin, dropped
ccl_skip_attr --> ccl_p(']'), ccl_p(']'), !.
ccl_skip_attr --> [_], ccl_skip_attr.
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__attribute__', '__attribute']) }, !, ccl_p('('), ccl_p('('), ccl_balanced, ccl_p(')'), ccl_p(')').
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__asm', '__asm__']) }, !, ccl_p('('), ccl_balanced, ccl_p(')').   % int f(void) __asm("_f")
ccl_gnu_attr --> ccl_id(A), { memberchk(A, ['__extension__', '__inline__', '__inline', '__restrict', '__restrict__', '__volatile__', '__const',
                                             '_Nonnull', '_Nullable', '_Null_unspecified', '__nonnull', '__nullable', '__null_unspecified']) }.
ccl_balanced --> ccl_p('('), !, ccl_balanced, ccl_p(')'), ccl_balanced.
ccl_balanced --> [tok(K, V, _)], { \+ ( K == p, ( V == '(' ; V == ')' ) ) }, !, ccl_balanced.
ccl_balanced --> [].

ccl_struct_spec(Env, T) --> ccl_kw(K), { K == struct ; K == union ; K == class }, !, ccl_struct_body(Env, K, T).
ccl_struct_body(Env, K, T) --> ccl_attrs, ccl_id(N), !, { ( ccl_lang(cpp) -> ccl_add_env(N) ; true ) },
    ( ccl_cpp, ccl_class_tail(Env, K, N, T), ! ; ccl_p('{'), !, ccl_members(Env, Ms), ccl_p('}'), ccl_attrs, { T =.. [K, N, Ms] } ; { T =.. [K, N, none] } ).
ccl_struct_body(Env, K, T) --> ccl_attrs, ccl_p('{'), ccl_class_members(Env, anon, Ms), ccl_p('}'), ccl_attrs, { ccl_make_class(K, anon, [], Ms, T) }.
%% C++: `struct N final : public B, C { ... }' -- class(Kind, N, Bases, Ms) when
%% it has bases, is a `class', or holds anything but fields; else C's struct
ccl_class_tail(Env, K, N, T) --> ( ccl_id(final), ! ; [] ), ( ccl_p(':'), !, ccl_bases(Env, Bs) ; { Bs = [] } ),
    ( ccl_p('{'), !, ccl_class_members(Env, N, Ms), ccl_p('}'), ccl_attrs, { ccl_make_class(K, N, Bs, Ms, T) } ; { Bs == [], T =.. [K, N, none] } ).
ccl_bases(Env, [base(A, Q)|Bs]) --> ( ccl_kw(A), { memberchk(A, [public, private, protected]) }, ! ; { A = none } ), ( ccl_kw(virtual), ! ; [] ), ccl_qname(Env, type, Q),
    ( ccl_p(','), !, ccl_bases(Env, Bs) ; { Bs = [] } ).
ccl_class_members(Env, N, Ms) --> { ccl_class_push(N) }, ( ccl_members(Env, Ms), { ccl_class_pop }, ! ; { ccl_class_pop }, { fail } ).
ccl_class_push(N) :- nb_getval('$ccl_class', S), nb_setval('$ccl_class', [N|S]).
ccl_class_pop :- nb_getval('$ccl_class', [_|S]), nb_setval('$ccl_class', S).
ccl_current_class(N) :- nb_getval('$ccl_class', [N|_]).
ccl_make_class(union, N, _, Ms, union(N, Ms)) :- !.
ccl_make_class(K, N, Bs, Ms, class(K, N, Bs, Ms)) :- ccl_lang(cpp), ( K == class ; Bs \== [] ; member(M, Ms), M \= member(_, _, _) ), !.
ccl_make_class(K, N, _, Ms, T) :- T =.. [K, N, Ms].
ccl_members(Env, Ms) --> [tok(pp, _, _)], !, ccl_members(Env, Ms).          % a #define inside a struct body (clang -E -dD keeps them)
ccl_members(Env, Ms) --> ccl_member_decl(Env, M), !, ccl_members(Env, Ms1), { append(M, Ms1, Ms) }.
ccl_members(_, []) --> [].
%% C++ members: an access label; a friend or using declaration (skipped to
%% its `;'); a member template; a constructor (the class's own name, then `('),
%% with its initializers; a destructor; a method -- a function declarator with
%% a body, `;', `= 0', `= default' or `= delete', its qualifiers (virtual,
%% static, explicit, const, override, final, noexcept) in a list
ccl_member_decl(_, [access(A)]) --> ccl_cpp, ccl_kw(A), { memberchk(A, [public, private, protected]) }, ccl_p(':'), !.
ccl_member_decl(_, [friend(L)]) --> ccl_cpp, ccl_line(L), ccl_kw(friend), !, ccl_skip_to_semi.
ccl_member_decl(_, [using(L)]) --> ccl_cpp, ccl_line(L), ccl_kw(using), !, ccl_skip_to_semi.
ccl_member_decl(Env, [template(L, Ps, M)]) --> ccl_cpp, ccl_line(L), ccl_kw(template), !, ccl_tparams(Env, Ps, Env1), ccl_member_decl(Env1, [M]).
ccl_member_decl(Env, [ctor(L, Qs, Ps, Inits, Body)]) --> ccl_cpp, ccl_line(L), ccl_member_prefix(Qs0), ccl_id(N), { ccl_current_class(N) }, ccl_p('('), !,
    ccl_params(Env, Ps, _), ccl_p(')'), ccl_method_quals(Qs1), ccl_ctor_inits(Env, Inits), ccl_fn_body(Env, Ps, Body), { append(Qs0, Qs1, Qs) }.
ccl_member_decl(Env, [dtor(L, Qs, Body)]) --> ccl_cpp, ccl_line(L), ccl_member_prefix(Qs0), ccl_p('~'), !, ccl_id(_), ccl_p('('), ccl_p(')'), ccl_method_quals(Qs1), ccl_fn_body(Env, [], Body), { append(Qs0, Qs1, Qs) }.
ccl_member_decl(Env, [method(L, Qs, Ret, Name, Ps, Var, Body)]) --> ccl_cpp, ccl_line(L), ccl_member_prefix(Qs0), ccl_decl_specs(Env, member, Sto, Base), ccl_declarator(Env, Base, Name, Type), { Type = fn(Ret, Ps, Var) }, !,
    ccl_method_quals(Qs1), ccl_fn_body(Env, Ps, Body), { ( Sto == none -> Qs2 = Qs0 ; Qs2 = [Sto|Qs0] ), append(Qs2, Qs1, Qs) }.
ccl_member_decl(Env, Ms) --> ccl_decl_specs(Env, member, Sto, Base0), { ccl_member_base(Sto, Base0, Base) }, ccl_member_declarators(Env, Base, Ms), ccl_p(';').
ccl_member_base(static, base(Q, S), base([static|Q], S)) :- ccl_lang(cpp), !.      % a static member: the word kept as a qualifier
ccl_member_base(_, B, B).
ccl_member_prefix([K|Qs]) --> ccl_kw(K), { memberchk(K, [virtual, static, explicit, inline, constexpr, consteval]) }, !,
    ( { K == explicit }, ccl_p('('), ccl_expr(_), ccl_p(')') ; [] ), ccl_member_prefix(Qs).      % C++20: explicit(cond), the condition dropped
ccl_member_prefix([]) --> [].
ccl_method_quals([const|Qs]) --> ccl_kw(const), !, ccl_method_quals(Qs).
ccl_method_quals(Qs) --> ccl_kw(volatile), !, ccl_method_quals(Qs).
ccl_method_quals([override|Qs]) --> ccl_id(override), !, ccl_method_quals(Qs).
ccl_method_quals([final|Qs]) --> ccl_id(final), !, ccl_method_quals(Qs).
ccl_method_quals([noexcept|Qs]) --> ccl_kw(noexcept), !, ( ccl_p('('), ccl_balanced, ccl_p(')'), ! ; [] ), ccl_method_quals(Qs).
ccl_method_quals(Qs) --> ccl_kw(throw), !, ccl_p('('), ccl_balanced, ccl_p(')'), ccl_method_quals(Qs).
ccl_method_quals(Qs) --> ( ccl_p('&'), ! ; ccl_p('&&') ), !, ccl_method_quals(Qs).
ccl_method_quals(Qs) --> ccl_gnu_attr, !, ccl_method_quals(Qs).
ccl_method_quals([trailing(T)|Qs]) --> ccl_p('->'), !, { nb_getval('$ccl_env', Env) }, ccl_type_name(Env, T), ccl_method_quals(Qs).
ccl_method_quals([]) --> [].
ccl_ctor_inits(Env, Inits) --> ccl_p(':'), !, ccl_init_list(Env, Inits).
ccl_ctor_inits(_, []) --> [].
ccl_init_list(Env, [init(N, As)|Is]) --> ccl_qname(Env, type, N), ( ccl_p('('), !, ccl_args(As), ccl_p(')') ; ccl_p('{'), ccl_args(As), ccl_p('}') ), ( ccl_p(','), !, ccl_init_list(Env, Is) ; { Is = [] } ).
ccl_fn_body(_, _, pure) --> ccl_p('='), [tok(int, 0, _)], !, ccl_p(';').
ccl_fn_body(_, _, default) --> ccl_p('='), ccl_kw(default), !, ccl_p(';').
ccl_fn_body(_, _, delete) --> ccl_p('='), ccl_kw(delete), !, ccl_p(';').
ccl_fn_body(_, _, none) --> ccl_p(';'), !.
ccl_fn_body(Env, Ps, Body) --> ccl_peek(p, '{'), ccl_push_scope, { ccl_declare_params(Ps) }, ccl_compound(Env, Body), ccl_pop_scope.
ccl_skip_to_semi --> ccl_p(';'), !.
ccl_skip_to_semi --> [_], ccl_skip_to_semi.
ccl_member_declarators(Env, Base, Ms) --> [tok(pp, _, _)], !, ccl_member_declarators(Env, Base, Ms).   % a #define between two declarators
ccl_member_declarators(Env, Base, Ms) --> ccl_member_declarator(Env, Base, M), ccl_member_default(M, Ds), ( ccl_p(','), !, ccl_member_declarators(Env, Base, Ms1) ; { Ms1 = [] } ), { append([M|Ds], Ms1, Ms) }.
%% C++: a default member initializer, `int limit = 100;', kept beside the member
ccl_member_default(member(_, N, _), [default_init(N, E)]) --> ccl_cpp, ccl_p('='), !, ccl_assign_expr(E).
ccl_member_default(member(_, N, _), [default_init(N, I)]) --> ccl_cpp, ccl_peek(p, '{'), !, ccl_initializer(I).
ccl_member_default(_, []) --> [].
ccl_member_declarators(_, _, []) --> [].
ccl_member_declarator(Env, Base, member(T, N, Bits)) --> ccl_declarator(Env, Base, N, T0), ccl_tie(T0, T), ( ccl_p(':'), !, ccl_cond_expr(Bits) ; { Bits = none } ).
ccl_member_declarator(_, Base, member(Base, anon, Bits)) --> ccl_p(':'), ccl_cond_expr(Bits).

ccl_enum_spec(enum_class(N, Es)) --> ccl_cpp, ccl_kw(enum), ( ccl_kw(class), ! ; ccl_kw(struct) ), !, ccl_id(N), { ccl_add_env(N) }, ccl_enum_base, ( ccl_p('{'), !, ccl_enumerators(Es), ccl_p('}') ; { Es = none } ).
ccl_enum_spec(enum(N, Es)) --> ccl_kw(enum), ( ccl_id(N), { ( ccl_lang(cpp) -> ccl_add_env(N) ; true ) }, ! ; { N = anon } ), ( ccl_cpp, ccl_enum_base, ! ; [] ), ( ccl_p('{'), !, ccl_enumerators(Es), ccl_p('}') ; { Es = none } ).
ccl_enum_base --> ccl_p(':'), !, { nb_getval('$ccl_env', Env) }, ccl_type_name(Env, _).   % `enum E : int', the underlying type dropped
ccl_enum_base --> [].
ccl_enumerators(Es) --> [tok(pp, _, _)], !, ccl_enumerators(Es).             % a #define among the enumerators
ccl_enumerators([E|Es]) --> ccl_enumerator(E), ( ccl_p(','), !, ccl_enumerators(Es) ; { Es = [] } ).
ccl_enumerators([]) --> [].
ccl_enumerator(enumerator(N, V)) --> ccl_id(N), ( ccl_p('='), !, ccl_cond_expr(V) ; { V = none } ).

%% ---- declarators ------------------------------------------------------------
%% Parsed inside-out the way C means them: pointers, then the direct part,
%% then array and function suffixes; ccl_mk_type folds them onto the base.
ccl_init_declarators(Env, Base, Ds) --> [tok(pp, _, _)], !, ccl_init_declarators(Env, Base, Ds).
ccl_init_declarators(Env, Base, [D|Ds]) --> ccl_init_declarator(Env, Base, D), ( ccl_p(','), !, ccl_init_declarators(Env, Base, Ds) ; { Ds = [] } ).
ccl_init_declarator(Env, Base, var(N, T, Init)) --> ccl_declarator(Env, Base, N, T0), ccl_attrs, ccl_tie(T0, T), ccl_var_init(Init).
ccl_var_init(Init) --> ccl_p('='), !, ccl_initializer(Init).
ccl_var_init(ctor(As)) --> ccl_cpp, ccl_p('('), !, ccl_args(As), ccl_p(')').           % C++: T x(args), direct initialization
ccl_var_init(Init) --> ccl_cpp, ccl_peek(p, '{'), !, ccl_initializer(Init).            % T x{args}
ccl_var_init(none) --> [].

ccl_declarator(Env, Base, Name, Type) --> ccl_decl_syntax(Env, D), { ccl_mk_type(D, Base, Name, Type) }.
%% the tie operator after a declarator: `x <*> y', x lives within y (owner's
%% rule; the check's business, library(ccl_check)) -- on a variable, a struct
%% member (tied to an earlier member), a parameter (to an earlier parameter),
%% a function (its result to a parameter), and after `name := expr'
ccl_tie(T0, T) --> ccl_p('<*>'), !, ccl_id(Y), { ccl_add_tie(Y, T0, T) }.
ccl_tie(T, T) --> [].
ccl_tie_name(Y) --> ccl_p('<*>'), !, ccl_id(Y).
ccl_tie_name(none) --> [].
ccl_abstract_or_declarator(Env, Base, Name, Type) --> ccl_decl_syntax(Env, D), !, { ccl_mk_type(D, Base, Name, Type) }.
ccl_abstract_or_declarator(_, Base, anon, Base) --> [].

ccl_decl_syntax(Env, decl(Ptrs, Direct, Sfx)) --> ccl_pointers(Ptrs), ccl_direct(Env, Direct), ccl_suffixes(Env, Sfx), { Direct \== none ; Ptrs \== [] ; Sfx \== [] }.
ccl_pointers([ref(Qs)|Ps]) --> ccl_cpp, ccl_p('&'), !, ccl_quals(Qs), ccl_pointers(Ps).      % C++'s references
ccl_pointers([rref(Qs)|Ps]) --> ccl_cpp, ccl_p('&&'), !, ccl_quals(Qs), ccl_pointers(Ps).
ccl_pointers([ptr(Qs)|Ps]) --> ccl_p('*'), !, ccl_quals(Qs), ccl_pointers(Ps).
ccl_pointers([block(Qs)|Ps]) --> ccl_p('^'), !, ccl_quals(Qs), ccl_pointers(Ps).   % Apple's block pointer, (^f)(int)
ccl_pointers([]) --> [].
ccl_quals([Q|Qs]) --> ccl_kw(Q), { ccl_qualifier(Q) }, !, ccl_quals(Qs).
ccl_quals([own|Qs]) --> ccl_id(own), !, ccl_quals(Qs).
ccl_quals(Qs) --> ccl_gnu_attr, !, ccl_quals(Qs).             % char * _Nonnull p, char * __restrict q
ccl_quals([]) --> [].
ccl_direct(_, name(operator(Op))) --> ccl_cpp, ccl_kw(operator), !, ccl_op_name(Op).
ccl_direct(Env, name(Q)) --> ccl_cpp, ccl_id(C), ccl_peek(p, '::'), !, ccl_qrest(Env, type, [C], none, Q).   % Shape::area, defined out of its class
ccl_direct(_, name(N)) --> ccl_id(N), !.
ccl_op_name('[]') --> ccl_p('['), !, ccl_p(']').
ccl_op_name('()') --> ccl_p('('), !, ccl_p(')').
ccl_op_name(new) --> ccl_kw(new), !, ( ccl_p('['), ccl_p(']'), ! ; [] ).
ccl_op_name(delete) --> ccl_kw(delete), !, ( ccl_p('['), ccl_p(']'), ! ; [] ).
ccl_op_name(Op) --> [tok(p, Op, _)], !.
ccl_op_name(conv(T)) --> { nb_getval('$ccl_env', Env) }, ccl_type_name(Env, T).
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
ccl_param(Env, P) --> ccl_decl_specs(Env, param, _, Base), ccl_abstract_or_declarator(Env, Base, N, T0), ccl_attrs, ccl_tie(T0, T), ccl_param_default(T, N, P).
ccl_param_default(T, N, param(T, N, E)) --> ccl_cpp, ccl_p('='), !, ccl_assign_expr(E).        % C++'s default argument
ccl_param_default(T, N, param(T, N)) --> [].

ccl_mk_type(decl(Ptrs, Direct, Sfx), Base, Name, Type) :-
    ccl_apply_pointers(Ptrs, Base, T1),
    ccl_apply_suffixes(Sfx, T1, T2),
    ( Direct = name(Name) -> Type = T2
    ; Direct = paren(D) -> ccl_mk_type(D, T2, Name, Type)
    ; Name = anon, Type = T2 ).
ccl_apply_pointers([], T, T).
ccl_apply_pointers([ptr(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, ptr(Q, T0), T).
ccl_apply_pointers([block(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, block(Q, T0), T).
ccl_apply_pointers([ref(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, ref(Q, T0), T).
ccl_apply_pointers([rref(Q)|Ps], T0, T) :- ccl_apply_pointers(Ps, rref(Q, T0), T).
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
ccl_block_items(Env0, Items) --> ccl_block_item(Env0, Env1, I), !, { ( Env1 == Env0 -> true ; nb_setval('$ccl_env', Env1) ) }, ccl_block_items(Env1, More), { ccl_splice(I, More, Items) }.
ccl_block_items(_, []) --> [].
ccl_block_item(Env, Env, directive(L, Text)) --> [tok(pp, Text, L)], !.
ccl_block_item(Env, Env, '$splice'(Ds)) --> ccl_line(L), ccl_p('{'), ccl_pattern(P), ccl_p('}'), ccl_p(':='), !, ccl_expr(E), ccl_p(';'), { ccl_destructure(L, P, E, Ds) }.
ccl_block_item(Env, Env, D) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_tie_name(Y), ccl_p(';'), { ccl_infer_decl(L, N, E, Y, D), ccl_note_item(D) }.
ccl_block_item(Env, Env, D) --> ccl_cpp, ccl_line(L), ccl_kw(auto), ( ccl_p('&'), { R = ref } ; { R = none } ), ccl_id(N), ccl_p('='), !, ccl_expr(E), ccl_p(';'), { ccl_auto_decl(L, N, E, R, D) }.
ccl_block_item(Env, Env, using(L, U)) --> ccl_cpp, ccl_line(L), ccl_kw(using), !, ( ccl_kw(namespace), !, ccl_qname(Env, type, Q), { U = namespace(Q) } ; ccl_kw(enum), !, ccl_qname(Env, type, Q), { U = enum(Q) } ; ccl_qname(Env, type, Q), { U = name(Q) } ), ccl_p(';').
ccl_block_item(Env0, Env, I) --> ccl_line(L), ccl_decl_specs(Env0, block, Sto, Base), ccl_init_declarators(Env0, Base, Ds), ccl_p(';'), !,
    { Sto == typedef -> ccl_declared_names(Ds, Ns), append(Ns, Env0, Env), I = typedef(L, Ds)
    ; Env = Env0, I = declaration(L, Sto, Base, Ds) }, { ccl_note_item(I) }.
ccl_block_item(Env, Env, declare(L, Base)) --> ccl_line(L), ccl_decl_specs(Env, block, _, Base), ccl_p(';'), !, { ccl_note_item(declare(L, Base)) }.
ccl_block_item(Env, Env, S) --> ccl_statement(Env, S).

ccl_statement(Env, S) --> ccl_compound(Env, S), !.
ccl_statement(Env, S) --> ccl_cpp, ccl_p('['), ccl_p('['), !, ccl_skip_attr, ccl_statement(Env, S).                    % C++20: [[likely]] on a statement, dropped
ccl_statement(_, co_return(L, none)) --> ccl_cpp, ccl_line(L), ccl_kw(co_return), ccl_p(';'), !.                            % coroutines: read, refused later
ccl_statement(_, co_return(L, E)) --> ccl_cpp, ccl_line(L), ccl_kw(co_return), !, ccl_expr(E), ccl_p(';').
ccl_statement(Env, if_constexpr(L, C, T, E)) --> ccl_cpp, ccl_line(L), ccl_kw(if), ccl_kw(constexpr), !, ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_statement(Env, T), ( ccl_kw(else), !, ccl_statement(Env, E) ; { E = none } ).   % C++17: decided at compile time
ccl_statement(Env, if(L, C, T, E)) --> ccl_line(L), ccl_kw(if), !, ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_statement(Env, T), ( ccl_kw(else), !, ccl_statement(Env, E) ; { E = none } ).
ccl_statement(Env, while(L, C, S)) --> ccl_line(L), ccl_kw(while), !, ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_statement(Env, S).
ccl_statement(Env, do(L, S, C)) --> ccl_line(L), ccl_kw(do), !, ccl_statement(Env, S), ccl_kw(while), ccl_p('('), ccl_expr(C), ccl_p(')'), ccl_p(';').
ccl_statement(Env, S) --> ccl_line(L), ccl_kw(for), !, ccl_p('('), ccl_for_rest(Env, L, S).
%% C++: for (decl : range) S is for_each(L, var(N, T, none), Range, S); `auto', `auto &', `auto &&', `auto *' read as such
ccl_for_rest(Env, L, block([Init1, for_each(L, Decl, R, S)])) --> ccl_cpp, ccl_for_init(Env, Init), ccl_range_decl(Env, Decl), ccl_p(':'), !, ccl_expr(R), ccl_p(')'), ccl_statement(Env, S), { ccl_init_stmt(L, Init, Init1) }.   % C++20: for (init; x : xs)
ccl_for_rest(Env, L, for_each(L, Decl, R, S)) --> ccl_cpp, ccl_range_decl(Env, Decl), ccl_p(':'), !, ccl_expr(R), ccl_p(')'), ccl_statement(Env, S).
ccl_for_rest(Env, L, for(L, Init, C, Step, S)) --> ccl_for_init(Env, Init), ccl_opt_expr(C), ccl_p(';'), ccl_opt_expr(Step), ccl_p(')'), ccl_statement(Env, S).
ccl_range_decl(_, var(N, T, none)) --> ( ccl_kw(const) ; [] ), ccl_kw(auto), !, ( ccl_p('&&'), !, { T = rref([], base([], [auto])) } ; ccl_p('&'), !, { T = ref([], base([], [auto])) } ; ccl_p('*'), !, { T = ptr([], base([], [auto])) } ; { T = base([], [auto]) } ), ccl_id(N).
ccl_range_decl(Env, var(N, T, none)) --> ccl_decl_specs(Env, block, _, Base), ccl_declarator(Env, Base, N, T).
ccl_statement(Env, try(L, Body, Catches)) --> ccl_cpp, ccl_line(L), ccl_kw(try), !, ccl_compound(Env, Body), ccl_catches(Env, Catches).
ccl_catches(Env, [catch(P, B)|Cs]) --> ccl_kw(catch), !, ccl_p('('), ( ccl_p('...'), !, { P = any } ; ccl_param(Env, P) ), ccl_p(')'), ccl_compound(Env, B), ccl_catches(Env, Cs).
ccl_catches(_, []) --> [].
ccl_statement(_, return(L, E)) --> ccl_line(L), ccl_kw(return), ccl_expr(E), !, ccl_p(';').
ccl_statement(_, return(L)) --> ccl_line(L), ccl_kw(return), !, ccl_p(';').
ccl_statement(_, break(L)) --> ccl_line(L), ccl_kw(break), !, ccl_p(';').
ccl_statement(_, continue(L)) --> ccl_line(L), ccl_kw(continue), !, ccl_p(';').
ccl_statement(_, goto(L, N)) --> ccl_line(L), ccl_kw(goto), !, ccl_id(N), ccl_p(';').
ccl_statement(Env, switch(L, E, S)) --> ccl_line(L), ccl_kw(switch), !, ccl_p('('), ccl_expr(E), ccl_p(')'), ccl_statement(Env, S).
ccl_statement(Env, case(L, E, S)) --> ccl_line(L), ccl_kw(case), !, ccl_cond_expr(E), ccl_p(':'), ccl_statement(Env, S).
ccl_statement(Env, default(L, S)) --> ccl_line(L), ccl_kw(default), !, ccl_p(':'), ccl_statement(Env, S).
%% defer(a, b) { body }  runs body at every exit of the enclosing scope, last
%% registered first, over the named variables as they then are (owner's rule:
%% scope-bound, like Cicili's cleanup); a call is never followed by a block
ccl_statement(Env, defer(L, Vars, Body)) --> ccl_line(L), ccl_id(defer), ccl_p('('), ccl_defer_vars(Vars), ccl_p(')'), ccl_peek(p, '{'), !, ccl_compound(Env, Body).
ccl_statement(Env, label(L, N, S)) --> ccl_line(L), ccl_id(N), ccl_p(':'), !, ccl_statement(Env, S).
ccl_statement(_, empty) --> ccl_p(';'), !.
ccl_statement(_, S) --> ccl_line(L), ccl_expr(E), ccl_p(';'), { ccl_stmt_of(L, E, S) }.   % a macro's result may be a statement

ccl_defer_vars([id(V)|Vs]) --> ccl_id(V), ( ccl_p(','), !, ccl_defer_vars(Vs) ; { Vs = [] } ).
ccl_defer_vars([]) --> [].
ccl_for_init(_, decl(Base, Ds)) --> ccl_line(L), ccl_id(N), ccl_p(':='), !, ccl_expr(E), ccl_tie_name(Y), ccl_p(';'), { ccl_infer_decl(L, N, E, Y, D), D = declaration(_, _, Base, Ds), ccl_note_item(D) }.
ccl_for_init(Env, decl(Base, Ds)) --> ccl_decl_specs(Env, block, _, Base), ccl_init_declarators(Env, Base, Ds), ccl_p(';'), !, { ccl_note_item(declaration(0, none, Base, Ds)) }.
ccl_for_init(_, E) --> ccl_opt_expr(E), ccl_p(';').
ccl_init_stmt(L, decl(Base, Ds), declaration(L, none, Base, Ds)) :- !.
ccl_init_stmt(_, none, empty) :- !.
ccl_init_stmt(L, E, expr(L, E)).
ccl_opt_expr(E) --> ccl_expr(E), !.
ccl_opt_expr(none) --> [].

%% ---- expressions, by precedence ----------------------------------------------
ccl_expr(E) --> ccl_assign_expr(A), ( ccl_p(','), !, ccl_expr(B), { E = comma(A, B) } ; { E = A } ).

%% the left of an assignment is read once, as a conditional expression, and
%% the operator looked for after it (the C grammar's unary-expression there
%% had every non-assignment expression's first operand parsed twice)
ccl_assign_expr(E) --> ccl_cond_expr(A), ccl_assign_rest(A, E).
ccl_assign_rest(A, assign(Op, A, R)) --> ccl_assign_op(Op), !, ccl_assign_expr(R).
ccl_assign_rest(E, E) --> [].
ccl_assign_op(Op) --> ccl_p(Op), { memberchk(Op, ['=', '*=', '/=', '%=', '+=', '-=', '<<=', '>>=', '&=', '^=', '|=']) }.

ccl_cond_expr(E) --> ccl_lor(C), ( ccl_p('?'), !, ccl_expr(A), ccl_p(':'), ccl_cond_expr(B), { E = cond(C, A, B) } ; { E = C } ).

%% the binary operators, one rule for the ten levels of precedence: an
%% operand, then every operator that binds at least as tightly as Min, its
%% right side read with the tighter operators only (precedence climbing), so
%% `a - b - c' is bin(-, bin(-, a, b), c) and `a + b * c' is bin(+, a, bin(*, b, c))
%% as the level-per-class cascade gave them -- at one look per token where
%% the cascade descended ten levels for every operand
ccl_lor(E) --> ccl_binary(1, E).
ccl_shift(E) --> ccl_binary(8, E).                                                % a template argument: shift and above, so its `>' closes
ccl_binary(Min, E) --> ccl_cast_expr(A), ccl_binary_rest(Min, A, E).
ccl_binary_rest(Min, A, E) --> ccl_peek(p, Op), ccl_line(L), { ccl_far(L), ccl_binop(Op, P), P >= Min }, !, ccl_p(Op), { P1 is P + 1 }, ccl_binary(P1, B), ccl_binary_rest(Min, bin(Op, A, B), E).
ccl_binary_rest(_, E, E) --> [].
ccl_binop('||', 1). ccl_binop('&&', 2). ccl_binop('|', 3). ccl_binop('^', 4). ccl_binop('&', 5).
ccl_binop('==', 6). ccl_binop('!=', 6). ccl_binop('<', 7). ccl_binop('>', 7). ccl_binop('<=', 7). ccl_binop('>=', 7).
ccl_binop('<=>', 7.5).                                                        % C++20: below the relational, above the shifts
ccl_binop('<<', 8). ccl_binop('>>', 8). ccl_binop('+', 9). ccl_binop('-', 9). ccl_binop('*', 10). ccl_binop('/', 10). ccl_binop('%', 10).

%% a cast needs a type after `(', which an expression in parentheses never
%% is; the same shape followed by `{' is C99's compound literal, (T){ ... },
%% which is a postfix expression and may be followed by `.x' and the rest
ccl_cast_expr(E) --> ccl_peek(p, '('), ccl_p('('), ccl_type_name([], T), ccl_p(')'), !, ccl_cast_rest(T, E).   % the type name tried once, for both
ccl_cast_expr(E) --> ccl_unary(E).
ccl_cast_rest(T, E) --> ccl_peek(p, '{'), !, ccl_initializer(I), ccl_postfix_(compound_lit(T, I), E).
ccl_cast_rest(T, cast(T, E)) --> ccl_cast_expr(E).

%% a unary expression is chosen by its first token (the value first, so the
%% clause is found by indexing, one try where each alternative was one)
%% C++: new T, new T(args), new T{args}, new T[n]; delete p, delete[] p; throw e
ccl_unary(E) --> ccl_peek(K, V), ccl_unary_(V, K, E).
ccl_unary_(new, kw, E) --> ccl_cpp, !, ccl_kw(new), ccl_new_expr(E).
ccl_unary_(delete, kw, E) --> ccl_cpp, !, ccl_kw(delete), ( ccl_p('['), !, ccl_p(']'), ccl_cast_expr(X), { E = delete_array(X) } ; ccl_cast_expr(X), { E = delete(X) } ).
ccl_unary_(co_await, kw, co_await(E)) --> ccl_cpp, !, ccl_kw(co_await), ccl_cast_expr(E).                  % C++20 coroutines: read, refused later
ccl_unary_(co_yield, kw, co_yield(E)) --> ccl_cpp, !, ccl_kw(co_yield), ccl_assign_expr(E).
ccl_unary_(throw, kw, throw(E)) --> ccl_cpp, !, ccl_kw(throw), ( ccl_assign_expr(E), ! ; { E = none } ).
ccl_new_expr(E) --> { nb_getval('$ccl_env', Env) }, ( ccl_p('('), ccl_args(_), ccl_p(')'), ! ; [] ), ccl_decl_specs(Env, typename, _, Base), ccl_pointers(Ptrs), { ccl_apply_pointers(Ptrs, Base, T) },
    ( ccl_p('['), !, ccl_expr(N), ccl_p(']'), { E = new_array(T, N) }
    ; ccl_p('('), !, ccl_args(As), ccl_p(')'), { E = new(T, As) }
    ; ccl_p('{'), !, ccl_args(As), ccl_p('}'), { E = new(T, As) }
    ; { E = new(T, []) } ).
ccl_unary_('++', p, preinc(E)) --> !, ccl_p('++'), ccl_unary(E).
ccl_unary_('--', p, predec(E)) --> !, ccl_p('--'), ccl_unary(E).
ccl_unary_('&', p, addr(E))    --> !, ccl_p('&'), ccl_cast_expr(E).
ccl_unary_('*', p, deref(E))   --> !, ccl_p('*'), ccl_cast_expr(E).
ccl_unary_('+', p, pos(E))     --> !, ccl_p('+'), ccl_cast_expr(E).
ccl_unary_('-', p, neg(E))     --> !, ccl_p('-'), ccl_cast_expr(E).
ccl_unary_('~', p, bitnot(E))  --> !, ccl_p('~'), ccl_cast_expr(E).
ccl_unary_('!', p, not(E))     --> !, ccl_p('!'), ccl_cast_expr(E).
ccl_unary_(sizeof, kw, E)      --> !, ccl_kw(sizeof), ( ccl_p('('), ccl_type_name([], T), ccl_p(')'), !, { E = sizeof_type(T) } ; ccl_unary(X), { E = sizeof(X) } ).
ccl_unary_(_, _, E)            --> ccl_postfix(E).

ccl_postfix(E) --> ccl_primary(P), ccl_postfix_(P, E).
%% the postfix operators, chosen by the punctuator that follows
ccl_postfix_(A, E) --> ccl_peek(p, V), !, ccl_postfix_p(V, A, E).
ccl_postfix_(E, E) --> [].
ccl_postfix_p('{', id(T), E) --> ccl_cpp, { nb_getval('$ccl_env', G), ccl_known_typedef(G, T) }, !, ccl_initializer(init(Is)), { ccl_item_values(Is, Vs) }, ccl_postfix_(call(id(T), Vs), E).   % T{args}, a temporary
ccl_postfix_p('[', A, E) --> !, ccl_p('['), ccl_expr(I), ccl_p(']'), ccl_postfix_(index(A, I), E).
ccl_postfix_p('(', A, E) --> !, ccl_p('('), ccl_args(As), ccl_p(')'), { ccl_call_or_macro(A, As, C) }, ccl_postfix_(C, E).
ccl_postfix_p('.', A, E) --> ccl_cpp, ccl_p('.'), ccl_p('~'), !, ccl_id(T), ccl_postfix_(member(A, dtor(T)), E).      % C++: x.~T(), the destructor called
ccl_postfix_p('->', A, E) --> ccl_cpp, ccl_p('->'), ccl_p('~'), !, ccl_id(T), ccl_postfix_(arrow(A, dtor(T)), E).
ccl_postfix_p('.', A, E) --> !, ccl_p('.'), ccl_member_name(N), ccl_postfix_(member(A, N), E).
ccl_postfix_p('->', A, E) --> !, ccl_p('->'), ccl_member_name(N), ccl_postfix_(arrow(A, N), E).
ccl_postfix_p('++', A, E) --> !, ccl_p('++'), ccl_postfix_(postinc(A), E).
ccl_postfix_p('--', A, E) --> !, ccl_p('--'), ccl_postfix_(postdec(A), E).
ccl_postfix_p(_, E, E) --> [].
%% C++: x.item<float>(), a member template with its arguments -- the member's
%% name is tmpl(N, Args) when the arguments read as such, ending before what a
%% call or a closing paren starts (`x.n < y' scans to its `;' and is not one)
ccl_member_name(tmpl(N, As)) --> ccl_cpp, ccl_id(N), ccl_targs_ahead, { nb_getval('$ccl_env', Env) }, ccl_targs(Env, As), !.
ccl_member_name(N) --> ccl_id(N).
ccl_args([A|As]) --> ccl_cpp, ccl_peek(p, '{'), !, ccl_initializer(A), ( ccl_p(','), !, ccl_args(As) ; { As = [] } ).   % C++: f({1, 2}), a braced list as an argument
ccl_args([A|As]) --> ccl_assign_expr(A), !, ( ccl_p(','), !, ccl_args(As) ; { As = [] } ).
ccl_item_values([], []).
ccl_item_values([item(_, V)|Is], [V|Vs]) :- ccl_item_values(Is, Vs).
ccl_args([]) --> [].

%% a primary is chosen by its token's kind and value: one look, one clause
ccl_primary(E) --> ccl_peek(K, V), ccl_primary_(K, V, E).
ccl_primary_(int, N, int(N))     --> !, [_].
ccl_primary_(float, F, float(F)) --> !, [_].
ccl_primary_(str, S0, str(S))    --> !, [_], ccl_strings(S0, S).          % "a" "b" is one string
ccl_primary_(chr, C, chr(C))     --> !, [_].
%% C++ primaries: this, true, false, nullptr, the casts, a functional cast of
%% a basic type, a lambda, and a qualified or template name
ccl_primary_(kw, this, this) --> ccl_cpp, !, ccl_kw(this).
ccl_primary_(kw, true, bool(true)) --> ccl_cpp, !, ccl_kw(true).
ccl_primary_(kw, false, bool(false)) --> ccl_cpp, !, ccl_kw(false).
ccl_primary_(kw, nullptr, nullptr) --> ccl_cpp, !, ccl_kw(nullptr).
ccl_primary_(kw, KW, ccast(K, T, E)) --> ccl_cpp, { ccl_cast_kw(KW, K) }, !, ccl_kw(KW), ccl_p('<'), { nb_getval('$ccl_env', Env) }, ccl_type_name(Env, T), ccl_tclose, ccl_p('('), ccl_expr(E), ccl_p(')').
ccl_primary_(kw, K, ccast(functional, base([], [K]), E)) --> ccl_cpp, { ccl_basic_type(K) }, !, ccl_kw(K), ccl_p('('), ccl_expr(E), ccl_p(')').
ccl_primary_(kw, requires, requires_expr(Ps, Reqs)) --> ccl_cpp, !, ccl_kw(requires), { nb_getval('$ccl_env', Env) },   % C++20: requires (params) { requirements }
    ( ccl_p('('), ccl_params(Env, Ps, _), ccl_p(')') ; { Ps = [] } ), ccl_p('{'), ccl_requirements(Env, Reqs), ccl_p('}').
ccl_primary_(p, '[', lambda(Caps1, Ps, Ret, Body)) --> ccl_cpp, !, ccl_p('['), ccl_lambda_caps(Caps), ccl_p(']'), { nb_getval('$ccl_env', Env0) },
    ( ccl_tparams(Env0, TPs, Env), { Caps1 = [tparams(TPs)|Caps] } ; { Env = Env0, Caps1 = Caps } ),                     % C++20: a template lambda, its parameters kept with the captures
    ( ccl_p('('), !, ccl_params(Env, Ps, _), ccl_p(')') ; { Ps = [] } ), ( ccl_kw(mutable), ! ; [] ), ( ccl_p('->'), !, ccl_type_name(Env, Ret) ; { Ret = none } ),
    ccl_push_scope, { ccl_declare_params(Ps) }, ccl_compound(Env, Body), ccl_pop_scope.
ccl_primary_(id, '__null', cast(ptr([], base([], [void])), int(0))) --> ccl_cpp, !, ccl_id('__null').   % C++'s NULL: what C's gives
%% the requirements of a requires-expression: typename T; { e } -> C; requires e; e;
ccl_requirements(Env, [R|Rs]) --> ccl_requirement(Env, R), !, ccl_requirements(Env, Rs).
ccl_requirements(_, []) --> [].
ccl_requirement(Env, type(T)) --> ccl_kw(typename), !, ccl_type_name(Env, T), ccl_p(';').
ccl_requirement(_, compound(E, C)) --> ccl_p('{'), !, ccl_expr(E), ccl_p('}'), ( ccl_p('->'), ccl_cond_expr(C) ; { C = none } ), ccl_p(';').
ccl_requirement(_, nested(E)) --> ccl_kw(requires), !, ccl_cond_expr(E), ccl_p(';').
ccl_requirement(_, expr(E)) --> ccl_expr(E), ccl_p(';').
ccl_primary_(id, _, E) --> ccl_cpp, { nb_getval('$ccl_env', Env) }, ccl_qname(Env, expr, Q), !, { ( atom(Q) -> E = id(Q) ; E = Q ) }.
ccl_primary_(p, '::', E) --> ccl_cpp, { nb_getval('$ccl_env', Env) }, ccl_qname(Env, expr, Q), !, { ( atom(Q) -> E = id(Q) ; E = Q ) }.
ccl_cast_kw(static_cast, static). ccl_cast_kw(dynamic_cast, dynamic). ccl_cast_kw(reinterpret_cast, reinterpret). ccl_cast_kw(const_cast, const).
ccl_lambda_caps([]) --> ccl_peek(p, ']'), !.
ccl_lambda_caps([C|Cs]) --> ccl_lambda_cap(C), ( ccl_p(','), !, ccl_lambda_caps(Cs) ; { Cs = [] } ).
ccl_lambda_cap(cap(default, '=')) --> ccl_p('='), !.
ccl_lambda_cap(C) --> ccl_p('&'), !, ( ccl_id(N), !, { C = cap(ref, N) } ; { C = cap(default, '&') } ).
ccl_lambda_cap(cap(this)) --> ccl_kw(this), !.
ccl_lambda_cap(cap(val, N)) --> ccl_id(N).
ccl_primary_(id, N, id(N))   --> !, ccl_id(N).
ccl_primary_(p, '(', stmt_expr(B)) --> ccl_p('('), ccl_peek(p, '{'), !, { nb_getval('$ccl_env', Env) }, ccl_compound(Env, B), ccl_p(')').   % GNU ({ ... })
ccl_primary_(p, '(', E)      --> ccl_p('('), ccl_expr(E), ccl_p(')').
ccl_strings(S0, S) --> [tok(str, S1, _)], !, { append(S0, S1, S2) }, ccl_strings(S2, S).
ccl_strings(S, S) --> [].
