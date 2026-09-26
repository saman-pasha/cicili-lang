%% cicili-lang -- library(ccl_infer): what a macro can ask, as the parser
%% stands at the call. The parser (library(ccl_syntax)) keeps the scope of
%% declared names, the typedef definitions and the struct tags as it reads;
%% a macro predicate from an included .pl runs at that point and may ask:
%%
%%   ccl_type_of(+Expr, -Type)        the type of an expression AST, or unknown
%%   ccl_resolve_type(+T, -T1)        typedef names unwrapped, a tag's members filled
%%   ccl_declared(+Name, -Type)       a name in scope, innermost first
%%   ccl_typedef_of(+Name, -Type)     a typedef's definition
%%   ccl_tag(+Tag, -Members)          a struct/union's members, an enum's enumerators
%%   ccl_members_of(+Type, -Members)  the members of a struct or union type
%%   ccl_member_type(+Type, +Name, -T)
%%   ccl_is_integer(+T) ccl_is_float(+T) ccl_is_arith(+T) ccl_is_pointer(+T)
%%   ccl_size_of(+T, -Bytes)          LP64: char 1 short 2 int 4 long 8 float 4 double 8 pointer 8
%%   ccl_enum_value(+Name, -Int)      an enumerator's value
%%   ccl_const_eval(+Expr, -Int)      an integer constant expression, folded as C folds it
%%   ccl_scope(-Frames)               every frame, innermost first
%%   ccl_gensym(+Prefix, -Atom)       a fresh identifier for a macro's temporary
%%   ccl_here(-File, -Line)           where the parser is
%%   ccl_macro_error(+Message)        stop the read with a message and the place
%%
%% Types are the AST's: base(Quals, Specs), ptr(Quals, T), arr(Size, T),
%% fn(Ret, Params, Variadic), block(Quals, T); and unknown.

%% no catch on a read of a global here: the keys are set once per process
%% (ccl_ensure_globals/0, library(ccl_include)), and a catch costs in
%% proportion to the terms bound inside it (a cocolog finding, in CLAUDE.md)
ccl_scope(Fs) :- nb_getval('$ccl_scope', Ls), nb_getval('$ccl_gscope', G), append(Ls, [G], Fs).   % every frame, the file scope's last
ccl_locals(Ls) :- nb_getval('$ccl_scope', Ls).                                                   % the open frames alone, innermost first
ccl_declared(N, T) :- nb_getval('$ccl_scope', Ls), ( ccl_in_frames(Ls, N, T0) -> T = T0 ; ccl_gdeclared(N, T) ).
ccl_gdeclared(N, T) :- ccl_cached_named('$ccl_g:', N, T, ( nb_getval('$ccl_gscope', G), memberchk(N-T, G) )).
%% a small answer cache in a global -- the Key-Value pairs found so far; a
%% copy of a dozen pairs is microseconds where the table's is a millisecond.
%% For keys that are terms (a type, a member list) whose values are small.
ccl_cached(Cache, Key, Value, Goal) :-
    nb_getval(Cache, C),
    (   memberchk(Key-V0, C) -> Value = V0
    ;   call(Goal), nb_setval(Cache, [Key-Value|C]) ).
%% the same for a NAME whose value may be large -- a tag's members, a
%% typedef's resolution, a function's type: a global per name, so a lookup
%% copies that one value and not every value found so far (nb_getval/2
%% copies what it answers); the names found are an index of atoms
ccl_cached_named(Prefix, Name, Value, Goal) :-
    atom_concat(Prefix, names, IK), nb_getval(IK, Names),
    (   memberchk(Name, Names) -> atom_concat(Prefix, Name, K), nb_getval(K, Value)
    ;   call(Goal), atom_concat(Prefix, Name, K), nb_setval(K, Value), nb_setval(IK, [Name|Names]) ).
ccl_named_caches(['$ccl_td:', '$ccl_tag:', '$ccl_r:', '$ccl_g:', '$ck_oa:', '$ccl_ts:']).
ccl_in_frames([F|Fs], N, T) :- ( memberchk(N-T0, F) -> T = T0 ; ccl_in_frames(Fs, N, T) ).
%% nb_getval/2 COPIES the term it answers, 0.05 ms for the typedef table and
%% 0.15 ms for the tags, and the lowering of 170 lines asks 2000 typedefs
%% and 1100 tags; the names a file uses are a dozen, so each answer is kept
%% in a small cache (a copy of a dozen pairs is microseconds), emptied by
%% ccl_tables_changed/0 wherever a table is written
ccl_typedef_of(N, T) :- ccl_cached_named('$ccl_td:', N, T, ( nb_getval('$ccl_typedefs', L), memberchk(N-T, L) )).
ccl_tag(Tag, Ms) :- ccl_cached_named('$ccl_tag:', Tag, Ms, ( nb_getval('$ccl_tags', L), memberchk(Tag-Ms, L) )).

%% ---- constants ---------------------------------------------------------------------
ccl_enum_value(N, V) :- nb_getval('$ccl_enums', L), memberchk(N-V, L).
%% an integer constant expression, as C folds it
ccl_const_eval(int(big(A)), big(A)) :- !.     % A LITERAL PAST 2^60 (big(Atom), the lexers' term; 0.94) IS ITS OWN VALUE: the 64-bit arithmetic below takes it
ccl_const_eval(uint(big(A)), big(A)) :- !.
ccl_const_eval(long(big(A)), big(A)) :- !.
ccl_const_eval(ulong(big(A)), big(A)) :- !.
ccl_const_eval(wb(big(_)), _) :- !, fail.       % a _BitInt literal past 2^60 folds nowhere (its width is read off the value)
ccl_const_eval(uwb(big(_)), _) :- !, fail.
ccl_const_eval(int(N), N) :- !.
ccl_const_eval(uint(N), N) :- !.
ccl_const_eval(long(N), N) :- !.
ccl_const_eval(ulong(N), N) :- !.
ccl_const_eval(wchr(N), N) :- !.
ccl_const_eval(u16chr(N), N) :- !.
ccl_const_eval(u32chr(N), N) :- !.
ccl_const_eval(wb(N), N) :- !.
ccl_const_eval(uwb(N), N) :- !.
ccl_const_eval(bool(true), 1) :- !.                                            % C++
ccl_const_eval(comma(A, B), V) :- !, ( ccl_const_eval(A, _) -> true ; A = cast(base(_, [void]), _) ), ccl_const_eval(B, V).   % THE COMMA OPERATOR IS A CONSTANT EXPRESSION (C++11, [expr.const]): the right operand's value, the left one a constant or a `(void)' cast of anything. libc++ writes its conjunction as `_IsSame<__all_dummy<_Preds...>, __all_dummy<((void)_Preds, true)...>>', and unfolded the second instance was keyed by the term's spelling, so `__all<true, true, true>' was FALSE and every tuple constructed from another tuple lost its converting constructor (0.93)
ccl_const_eval(bool(false), 0) :- !.
ccl_const_eval(chr(C), C) :- !.
ccl_const_eval(id(N), V) :- !, \+ ccl_shadowed_constant(N), ccl_enum_value(N, V).   % a name is a constant only where no PLAIN local shadows the enumerator (0.94)
%% ... a `const' local with a constant initializer IS the constant (0.63's rule 11, `cpp_note_const'): libc++'s `__mu' writes
%% `const size_t __indx = is_placeholder<_Ti>::value - 1;' and indexes a tuple by it, and refused as a shadow it never folded
ccl_shadowed_constant(N) :- ccl_locals(Ls), ccl_in_frames(Ls, N, T), \+ ( ccl_resolve_type(T, base(Q, _)), memberchk(const, Q) ).
%% ---- 64-BIT CONSTANT ARITHMETIC (0.94) ------------------------------------------------------------------
%% cocolog's integers are 61-bit (the finding): `_Tp(1) << 63' folded to 0 and `type(type(~0) ^ __min)' -- how libc++
%% computes every numeric_limits<...>::max() -- to -1, so a string read, bounded by numeric_limits<streamsize>::max(),
%% never looped. A folded value is a cocolog integer where it fits in 61 bits and `big(Atom)' beyond (the lexers'
%% term for a literal past 2^60: its decimal digits, `-' first when negative); an operation whose result could pass
%% 61 bits computes on base-2^30 limbs (ccl_w_* over ccl_mag_*), and a CAST TO AN INTEGER TYPE WRAPS to its width
%% and signedness ([conv.integral]), which is where a 64-bit two's complement pattern is made: `(long long) (1ULL <<
%% 63)' is -2^63. The bitwise operators are the mathematical two's complement (`~0' is -1, as cocolog and C have it),
%% which with the casts gives C's answer; `/' and `%' truncate toward zero as C does, `>>' of a negative is arithmetic.
ccl_const_eval(neg(E), V) :- !, ccl_const_eval(E, V0), ccl_w_neg(V0, V).
ccl_const_eval(pos(E), V) :- !, ccl_const_eval(E, V).
ccl_const_eval(bitnot(E), V) :- !, ccl_const_eval(E, V0), ccl_w_sub(-1, V0, V).
ccl_const_eval(not(E), V) :- !, ccl_const_eval(E, V0), ( V0 == 0 -> V = 1 ; V = 0 ).
ccl_const_eval(cast(T, E), V) :- !, ccl_const_eval(E, V0), ccl_w_cast(T, V0, V).
ccl_const_eval(ccast(_, T, E), V) :- !, ccl_const_eval(E, V0), ccl_w_cast(T, V0, V).      % C++'s own casts, a functional one among them: `type(~0)' folds as `(type) ~0' does
ccl_const_eval(sizeof_type(T), V) :- !, ccl_size_of(T, V).
ccl_const_eval(alignof_type(T), V) :- !, ccl_resolve_type(T, T1), ccl_size_align(T1, _, V).   % `alignof(T)' ([expr.alignof]): the alignment the layout already computes
ccl_const_eval(sizeof(E), V) :- !, ccl_type_of(E, T), ccl_size_of(T, V).
ccl_const_eval(cond(C, A, B), V) :- !, ccl_const_eval(C, CV), ( CV \== 0 -> ccl_const_eval(A, V) ; ccl_const_eval(B, V) ).
ccl_const_eval(bin(Op, A, B), V) :- ccl_const_eval(A, X), ccl_const_eval(B, Y), ccl_const_op(Op, X, Y, V).
ccl_const_op('+', X, Y, V) :- ccl_w_add(X, Y, V).
ccl_const_op('-', X, Y, V) :- ccl_w_sub(X, Y, V).
ccl_const_op('*', X, Y, V) :- ccl_w_mul(X, Y, V).
ccl_const_op('/', X, Y, V) :- Y \== 0, ccl_w_div(X, Y, V).
ccl_const_op('%', X, Y, V) :- Y \== 0, ccl_w_mod(X, Y, V).
ccl_const_op('<<', X, Y, V) :- integer(Y), Y >= 0, ccl_w_shl(X, Y, V).
ccl_const_op('>>', X, Y, V) :- integer(Y), Y >= 0, ccl_w_shr(X, Y, V).
ccl_const_op('&', X, Y, V) :- ccl_w_bit(and, X, Y, V).
ccl_const_op('|', X, Y, V) :- ccl_w_bit(or, X, Y, V).
ccl_const_op('^', X, Y, V) :- ccl_w_bit(xor, X, Y, V).
ccl_const_op('<', X, Y, V) :- ( ccl_w_cmp(X, Y, <) -> V = 1 ; V = 0 ).
ccl_const_op('>', X, Y, V) :- ( ccl_w_cmp(X, Y, >) -> V = 1 ; V = 0 ).
ccl_const_op('<=', X, Y, V) :- ( ccl_w_cmp(X, Y, >) -> V = 0 ; V = 1 ).
ccl_const_op('>=', X, Y, V) :- ( ccl_w_cmp(X, Y, <) -> V = 0 ; V = 1 ).
ccl_const_op('==', X, Y, V) :- ( ccl_w_cmp(X, Y, =) -> V = 1 ; V = 0 ).
ccl_const_op('!=', X, Y, V) :- ( ccl_w_cmp(X, Y, =) -> V = 0 ; V = 1 ).
ccl_const_op('&&', X, Y, V) :- ( X \== 0, Y \== 0 -> V = 1 ; V = 0 ).
ccl_const_op('||', X, Y, V) :- ( ( X \== 0 ; Y \== 0 ) -> V = 1 ; V = 0 ).
%% the operations: a fast path in the engine's own arithmetic where the result cannot pass 61 bits, else the limbs
ccl_w_fits(X) :- integer(X), X < 576460752303423488, X > -576460752303423488.          % |X| < 2^59
ccl_w_neg(X, V) :- integer(X), !, V is -X.
ccl_w_neg(X, V) :- ccl_wide(X, w(S, M)), S1 is -S, ccl_narrow(w(S1, M), V).
ccl_w_add(X, Y, V) :- ccl_w_fits(X), ccl_w_fits(Y), !, V is X + Y.
ccl_w_add(X, Y, V) :- ccl_wide(X, A), ccl_wide(Y, B), ccl_w_add_(A, B, C), ccl_narrow(C, V).
ccl_w_sub(X, Y, V) :- ccl_w_fits(X), ccl_w_fits(Y), !, V is X - Y.
ccl_w_sub(X, Y, V) :- ccl_wide(X, A), ccl_wide(Y, w(S, M)), S1 is -S, ccl_w_add_(A, w(S1, M), C), ccl_narrow(C, V).
ccl_w_mul(X, Y, V) :- integer(X), integer(Y), X < 1073741824, X > -1073741824, Y < 1073741824, Y > -1073741824, !, V is X * Y.
ccl_w_mul(X, Y, V) :- ccl_wide(X, w(SA, MA)), ccl_wide(Y, w(SB, MB)), S is SA * SB, ccl_mag_mul(MA, MB, M), ccl_narrow(w(S, M), V).
ccl_w_div(X, Y, V) :- integer(X), integer(Y), !, V is X // Y.                            % `//' truncates, as C does
ccl_w_div(X, Y, V) :- ccl_wide(X, w(SA, MA)), ccl_wide(Y, w(SB, MB)), ccl_mag_divmod(MA, MB, Q, _), S is SA * SB, ccl_narrow(w(S, Q), V).
ccl_w_mod(X, Y, V) :- integer(X), integer(Y), !, V is X - (X // Y) * Y.                 % the remainder takes the dividend's sign, as C has it
ccl_w_mod(X, Y, V) :- ccl_wide(X, w(SA, MA)), ccl_wide(Y, w(_, MB)), ccl_mag_divmod(MA, MB, _, R), ccl_narrow(w(SA, R), V).
ccl_w_shl(X, N, V) :- integer(X), N < 30, X < 1073741824, X > -1073741824, !, V is X << N.
ccl_w_shl(X, N, V) :- ccl_wide(X, w(S, M)), ccl_mag_shl(M, N, M1), ccl_narrow(w(S, M1), V).
ccl_w_shr(X, N, V) :- integer(X), !, V is X >> N.                                        % arithmetic: the floor, as every compiler here has it
ccl_w_shr(X, N, V) :- ccl_wide(X, w(S, M)), ccl_mag_shr(M, N, M1, Rem), ( S < 0, Rem == nonzero -> ccl_mag_add(M1, [1], M2) ; M2 = M1 ), ccl_narrow(w(S, M2), V).
ccl_w_bit(Op, X, Y, V) :- integer(X), integer(Y), !, ccl_w_bit_int(Op, X, Y, V).
ccl_w_bit(Op, X, Y, V) :- ccl_wide(X, A), ccl_wide(Y, B), ccl_w_tc(A, TA), ccl_w_tc(B, TB), ccl_mag_bit(Op, TA, TB, TC), ccl_w_untc(TC, C), ccl_narrow(C, V).
ccl_w_bit_int(and, X, Y, V) :- V is X /\ Y.
ccl_w_bit_int(or, X, Y, V) :- V is X \/ Y.
ccl_w_bit_int(xor, X, Y, V) :- V is xor(X, Y).
ccl_w_cmp(X, Y, O) :- integer(X), integer(Y), !, compare(O, X, Y).
ccl_w_cmp(X, Y, O) :- ccl_wide(X, w(SA, MA)), ccl_wide(Y, w(SB, MB)),
    ( SA < SB -> O = (<) ; SA > SB -> O = (>) ; ccl_mag_cmp(MA, MB, O0), ( SA < 0 -> ccl_w_flip(O0, O) ; O = O0 ) ).
ccl_w_flip(<, >). ccl_w_flip(>, <). ccl_w_flip(=, =).
%% a cast to an integer type wraps to its width, then to its signedness; to bool it is the test; to anything else the value
ccl_w_cast(T, X, V) :- ccl_resolve_type(T, RT), ccl_cast_shape(RT, Bits, Signed), !, ccl_w_wrap(X, Bits, Signed, V).
ccl_w_cast(_, X, X).
ccl_cast_shape(base(_, S), 1, bool) :- ( memberchk(bool, S) ; memberchk('_Bool', S) ), !.
ccl_cast_shape(RT, Bits, Signed) :- ccl_is_integer(RT), ccl_size_of(RT, Bytes), Bits is Bytes * 8, ( ccl_int_rank(RT, _, true) -> Signed = false ; Signed = true ).
ccl_w_wrap(X, 1, bool, V) :- !, ( X == 0 -> V = 0 ; V = 1 ).
ccl_w_wrap(X, Bits, Signed, V) :- integer(X), Bits =< 32, !, P is 1 << Bits, M0 is X mod P, ( M0 < 0 -> M is M0 + P ; M = M0 ), H is P // 2, ( Signed == true, M >= H -> V is M - P ; V = M ).
ccl_w_wrap(X, Bits, Signed, V) :- integer(X), Bits >= 61, ( X >= 0 ; Signed == true ), !, V = X.   % a value that fits in 61 bits is unchanged by a 64-bit wrap, unless it is negative and the type is unsigned
ccl_w_wrap(X, Bits, Signed, V) :- ccl_wide(X, w(S, M)), ccl_pow2_mag(Bits, P), ccl_mag_lowbits(M, Bits, L0),
    ( S < 0, L0 \== [] -> ccl_mag_sub(P, L0, L) ; L = L0 ),
    B1 is Bits - 1, ( Signed == true, ccl_mag_bit_set(L, B1) -> ccl_mag_sub(P, L, M1), ccl_narrow(w(-1, M1), V) ; ccl_narrow(w(1, L), V) ).
%% a value between the engine's integers and the limbs: w(Sign, Limbs), little-endian base 2^30, no trailing zero limb
ccl_wide(V, W) :- integer(V), !, ( V < 0 -> M is -V, S = -1 ; M = V, S = 1 ), ccl_limbs_of_int(M, Ls), ccl_w_norm(S, Ls, W).
ccl_wide(big(A), W) :- atom_codes(A, Cs), ( Cs = [0'-|Ds] -> S = -1 ; Ds = Cs, S = 1 ), ccl_limbs_of_dec(Ds, [], Ls), ccl_w_norm(S, Ls, W).
ccl_w_norm(S, Ls0, w(S1, Ls)) :- ccl_mag_norm(Ls0, Ls), ( Ls == [] -> S1 = 1 ; S1 = S ).
ccl_narrow(w(S, M), V) :-
    (   M == [] -> V = 0
    ;   M = [L0] -> V is S * L0
    ;   M = [L0, L1] -> V is S * (L0 + L1 * 1073741824)
    ;   ccl_mag_dec(M, Ds), ( S < 0 -> atom_codes(A, [0'-|Ds]) ; atom_codes(A, Ds) ), V = big(A) ).
ccl_w_add_(w(SA, MA), w(SB, MB), C) :-
    (   SA =:= SB -> ccl_mag_add(MA, MB, M), ccl_w_norm(SA, M, C)
    ;   ccl_mag_cmp(MA, MB, O), ( O == (<) -> ccl_mag_sub(MB, MA, M), ccl_w_norm(SB, M, C) ; ccl_mag_sub(MA, MB, M), ccl_w_norm(SA, M, C) ) ).
ccl_w_tc(w(S, M), T) :- ( S >= 0 -> T = M ; ccl_pow2_mag(128, P), ccl_mag_sub(P, M, T) ).                    % two's complement at 128 bits
ccl_w_untc(T, C) :- ( ccl_mag_bit_set(T, 127) -> ccl_pow2_mag(128, P), ccl_mag_sub(P, T, M), C = w(-1, M) ; C = w(1, T) ).
%% the magnitudes
ccl_limbs_of_int(0, []) :- !.
ccl_limbs_of_int(M, [L|Ls]) :- L is M mod 1073741824, M1 is M // 1073741824, ccl_limbs_of_int(M1, Ls).
ccl_limbs_of_dec([], Ls, Ls).
ccl_limbs_of_dec([D|Ds], Acc0, Ls) :- V is D - 0'0, ccl_mag_mul_small(Acc0, 10, V, Acc1), ccl_limbs_of_dec(Ds, Acc1, Ls).
ccl_mag_norm(Ls, N) :- reverse(Ls, R0), ccl_drop_zeros(R0, R), reverse(R, N).
ccl_drop_zeros([0|Xs], R) :- !, ccl_drop_zeros(Xs, R).
ccl_drop_zeros(Xs, Xs).
ccl_mag_add(A, B, C) :- ccl_mag_add_(A, B, 0, C0), ccl_mag_norm(C0, C).
ccl_mag_add_([], [], 0, []) :- !.
ccl_mag_add_([], [], Cy, [Cy]) :- !.
ccl_mag_add_([], Bs, Cy, C) :- !, ccl_mag_add_([0], Bs, Cy, C).
ccl_mag_add_(As, [], Cy, C) :- !, ccl_mag_add_(As, [0], Cy, C).
ccl_mag_add_([A|As], [B|Bs], Cy, [D|Ds]) :- T is A + B + Cy, D is T mod 1073741824, Cy1 is T // 1073741824, ccl_mag_add_(As, Bs, Cy1, Ds).
ccl_mag_sub(A, B, C) :- ccl_mag_sub_(A, B, 0, C0), ccl_mag_norm(C0, C).                  % A >= B
ccl_mag_sub_([], [], 0, []) :- !.
ccl_mag_sub_(As, [], Bw, C) :- !, ccl_mag_sub_(As, [0], Bw, C).
ccl_mag_sub_([A|As], [B|Bs], Bw, [D|Ds]) :- T is A - B - Bw, ( T < 0 -> D is T + 1073741824, Bw1 = 1 ; D = T, Bw1 = 0 ), ccl_mag_sub_(As, Bs, Bw1, Ds).
ccl_mag_cmp(A, B, O) :- length(A, LA), length(B, LB), ( LA < LB -> O = (<) ; LA > LB -> O = (>) ; reverse(A, RA), reverse(B, RB), compare(O, RA, RB) ).
ccl_mag_mul_small([], _, Cy, Ls) :- ( Cy =:= 0 -> Ls = [] ; Ls = [Cy] ).               % K and the carry below 2^30
ccl_mag_mul_small([L|Ls], K, Cy, [R|Rs]) :- T is L * K + Cy, R is T mod 1073741824, Cy1 is T // 1073741824, ccl_mag_mul_small(Ls, K, Cy1, Rs).
ccl_mag_mul([], _, []) :- !.
ccl_mag_mul([A|As], B, C) :- ccl_mag_mul_small(B, A, 0, P), ccl_mag_mul(As, B, C1), ( C1 == [] -> ccl_mag_norm(P, C) ; ccl_mag_add(P, [0|C1], C) ).
ccl_mag_divmod(A, [K], Q, R) :- !, ccl_mag_divmod_small(A, K, Q, R0), ( R0 =:= 0 -> R = [] ; R = [R0] ).
ccl_mag_divmod(A, B, Q, R) :- ccl_mag_bits_be(A, Bits), ccl_mag_ldiv(Bits, B, [], QBits, R), ccl_mag_of_bits_be(QBits, Q).
ccl_mag_divmod_small(A, K, Q, R) :- reverse(A, BE), ccl_mag_dms_(BE, K, 0, QBE, R), reverse(QBE, Q0), ccl_mag_norm(Q0, Q).
ccl_mag_dms_([], _, R, [], R).
ccl_mag_dms_([L|Ls], K, R0, [Q|Qs], R) :- T is R0 * 1073741824 + L, Q is T // K, R1 is T mod K, ccl_mag_dms_(Ls, K, R1, Qs, R).
ccl_mag_bits_be(M, Bits) :- reverse(M, BE), ccl_limbs_bits_be(BE, Bits0), ccl_drop_zeros(Bits0, Bits).
ccl_limbs_bits_be([], []).
ccl_limbs_bits_be([L|Ls], Bits) :- ccl_limb_bits(29, L, B0), ccl_limbs_bits_be(Ls, B1), append(B0, B1, Bits).
ccl_limb_bits(-1, _, []) :- !.
ccl_limb_bits(I, L, [B|Bs]) :- B is (L >> I) /\ 1, I1 is I - 1, ccl_limb_bits(I1, L, Bs).
ccl_mag_ldiv([], _, R, [], R).
ccl_mag_ldiv([Bit|Bits], B, R0, [QB|QBs], R) :-
    ccl_mag_shl(R0, 1, R1a), ( Bit =:= 1 -> ccl_mag_add(R1a, [1], R1) ; R1 = R1a ),
    ( ccl_mag_cmp(R1, B, O), O \== (<) -> ccl_mag_sub(R1, B, R2), QB = 1 ; R2 = R1, QB = 0 ), ccl_mag_ldiv(Bits, B, R2, QBs, R).
ccl_mag_of_bits_be(Bits, M) :- ccl_mag_of_bits_(Bits, [], M0), ccl_mag_norm(M0, M).
ccl_mag_of_bits_([], M, M).
ccl_mag_of_bits_([B|Bs], Acc, M) :- ccl_mag_shl(Acc, 1, A1), ( B =:= 1 -> ccl_mag_add(A1, [1], A2) ; A2 = A1 ), ccl_mag_of_bits_(Bs, A2, M).
ccl_mag_shl(M, N, R) :- Q is N // 30, Rm is N mod 30, K is 1 << Rm, ccl_mag_mul_small(M, K, 0, M1), ( M1 == [] -> R = [] ; length(Z, Q), ccl_fill_zeros(Z), append(Z, M1, R0), ccl_mag_norm(R0, R) ).
ccl_fill_zeros([]).
ccl_fill_zeros([0|Z]) :- ccl_fill_zeros(Z).
ccl_mag_shr(M, N, R, Rem) :- Q is N // 30, Rm is N mod 30, ccl_mag_drop(Q, M, M1, Rem0), K is 1 << Rm, ccl_mag_divmod_small(M1, K, R, Rm2), ( ( Rem0 == nonzero ; Rm2 =\= 0 ) -> Rem = nonzero ; Rem = zero ).
ccl_mag_drop(0, M, M, zero) :- !.
ccl_mag_drop(_, [], [], zero) :- !.
ccl_mag_drop(Q, [L|Ls], M, Rem) :- Q1 is Q - 1, ccl_mag_drop(Q1, Ls, M, Rem1), ( ( L =\= 0 ; Rem1 == nonzero ) -> Rem = nonzero ; Rem = zero ).
ccl_mag_lowbits(M, Bits, L) :- Q is Bits // 30, Rb is Bits mod 30, ccl_mag_take(Q, M, Full, Rest), ( Rb > 0, Rest = [X|_] -> Mask is (1 << Rb) - 1, Y is X /\ Mask, append(Full, [Y], L0) ; L0 = Full ), ccl_mag_norm(L0, L).
ccl_mag_take(0, M, [], M) :- !.
ccl_mag_take(_, [], [], []) :- !.
ccl_mag_take(Q, [X|Xs], [X|Ys], Rest) :- Q1 is Q - 1, ccl_mag_take(Q1, Xs, Ys, Rest).
ccl_mag_bit_set(M, I) :- Q is I // 30, Rb is I mod 30, nth0(Q, M, L), (L >> Rb) /\ 1 =:= 1.
ccl_pow2_mag(Bits, P) :- ccl_mag_shl([1], Bits, P).
ccl_mag_bit(Op, A, B, C) :- length(A, LA), length(B, LB), Lm is max(LA, LB), ccl_mag_pad(A, Lm, A1), ccl_mag_pad(B, Lm, B1), ccl_mag_bit_(Op, A1, B1, C0), ccl_mag_norm(C0, C).
ccl_mag_pad(M, N, P) :- length(M, L), ( L >= N -> P = M ; K is N - L, length(Z, K), ccl_fill_zeros(Z), append(M, Z, P) ).
ccl_mag_bit_(_, [], [], []).
ccl_mag_bit_(Op, [A|As], [B|Bs], [C|Cs]) :- ccl_w_bit_int(Op, A, B, C), ccl_mag_bit_(Op, As, Bs, Cs).
ccl_mag_dec([], [0'0]) :- !.
ccl_mag_dec(M, Ds) :- ccl_mag_dec_(M, [], Ds).
ccl_mag_dec_([], Acc, Acc) :- !.
ccl_mag_dec_(M, Acc, Ds) :- ccl_mag_divmod_small(M, 10, Q, R), D is 0'0 + R, ccl_mag_dec_(Q, [D|Acc], Ds).

ccl_here(File, Line) :- ccl_ensure_globals, nb_getval('$ccl_file', File), nb_getval('$ccl_far', Line).
ccl_gensym(Prefix, Atom) :-
    ccl_ensure_globals, nb_getval('$ccl_gensym', N0), N is N0 + 1, nb_setval('$ccl_gensym', N),
    atomic_list_concat([Prefix, '_', N], Atom).
ccl_macro_error(Msg) :- ccl_here(F, L), throw(error(macro_error(Msg, here(F, L)), _)).

%% ---- resolving ------------------------------------------------------------------
%% a typedef resolves to its end in one step: the chain (size_t -> __darwin_size_t
%% -> unsigned long) is walked once per name and kept (the lowering of 170 lines
%% asked 16,600 resolutions, most of them links of a chain)
%% (asked 12,000 times in the lowering of 170 lines, most for a pointer or a
%% plain base type: the functor decides the clause, one try)
ccl_resolve_type(base(Q, [S|Ss]), base(Q, [S|Ss])) :- atom(S), !.               % a plain specifier list, the commonest: one call
ccl_resolve_type(base(Q, S), T) :- !, ccl_resolve_base(S, Q, T).
ccl_resolve_type(T, T).
ccl_resolve_base([S|Ss], Q, base(Q, [S|Ss])) :- atom(S), !.                      % a plain specifier list, the common case: one try
ccl_resolve_base([typedef(N)], Q, T) :- atom(N), ccl_cached_named('$ccl_r:', N, T1, ccl_resolve_typedef(N, T1)), !, ccl_add_quals(Q, T1, T).
ccl_resolve_base([typedef(N)], Q, T) :- atom(N), ccl_lang(cpp), ccl_tag(N, Ms), !, ccl_tag_type(N, Ms, Q, T).   % C++: a tag's name is a type name; a template-id (a compound) stays as it is
%% typeof(x): the TYPE when a type was written (GNU's, and C23's own), else the expression's -- nothing
%% resolved it before, so a `typeof' reached the lowering as a specifier it could not take
ccl_resolve_base([typeof(unqual(X))], Q, T) :- !, ccl_resolve_base([typeof(X)], [], T0), ccl_strip_quals(T0, T1), ccl_add_quals(Q, T1, T).   % C23's typeof_unqual: the top-level qualifiers off
ccl_resolve_base([typeof(X)], Q, T) :- ccl_type_term(X), !, ccl_resolve_type(X, T0), ccl_add_quals(Q, T0, T).
ccl_resolve_base([typeof(X)], Q, T) :- ccl_type_of(X, T0), T0 \== unknown, !, ccl_resolve_type(T0, T1), ccl_add_quals(Q, T1, T).
ccl_type_term(T) :- compound(T), functor(T, F, _), memberchk(F, [base, ptr, arr, fn, ref, rref]).
ccl_resolve_base([decltype(E)], Q, base(Q, [unsigned, long])) :- ccl_lang(cpp), ccl_sizeof_expr(E), !.   % C++: libc++ spells size_t `decltype(sizeof(int))', and the type of a sizeof is size_t: the concrete type here, or the chain turns
ccl_resolve_base([decltype(E)], Q, T) :- ccl_lang(cpp), ccl_type_of(E, T0), T0 \== unknown, !, ccl_add_quals(Q, T0, T).
ccl_resolve_base([struct(Tag, none)], Q, base(Q, [struct(Tag, Ms)])) :- ccl_tag(Tag, Ms), !.
ccl_resolve_base([union(Tag, none)], Q, base(Q, [union(Tag, Ms)])) :- ccl_tag(Tag, Ms), !.
ccl_resolve_base(S, Q, base(Q, S)).
%% what a C++ tag's name stands for, told by its members' shape: enumerators,
%% plain members (a struct), or a class's (a constructor, a method, a label)
ccl_tag_type(N, Ms0, Q, base(Q, [union(N, Ms)])) :- ccl_is_union_tag(Ms0), !, ccl_tag(N, Ms).   % a UNION with constructors: a class whose members share storage
ccl_tag_type(N, Ms0, Q, base(Q, [enum(N, Ms)])) :- ccl_is_enum_tag(Ms0), !, ccl_tag(N, Ms).
ccl_tag_type(N, Ms, Q, base(Q, [struct(N, Ms2)])) :- ccl_class_shape(Ms), ccl_tag_struct(N, Ms2), !.   % the class desugared: its struct, noted beside the raw class
ccl_tag_type(N, Ms, Q, base(Q, [class(class, N, [], Ms)])) :- ccl_class_shape(Ms), !.
ccl_tag_type(N, Ms, Q, base(Q, [struct(N, Ms)])).
%% A TAG'S MEMBERS TELL AN ENUM FROM A STRUCT: its enumerators, or the underlying type kept before them
%% (ccl_enum_members//3 in the reader) -- which is the only thing that tells `enum class C : size_t { }',
%% libc++'s strong typedef for a count, from an empty struct. Asked wherever a tag's name is resolved,
%% cast to, or taken as a scope.
%% ... and a marker before them tells a UNION-CLASS from a struct, the same way: libc++'s `basic_string::__rep'
%% is a union with four constructors -- a class whose members share storage, so its LAYOUT is a union's while its
%% constructors and methods are a class's
ccl_is_union_tag([union_tag|_]).
ccl_is_enum_tag([enumerator(_, _)|_]).
ccl_is_enum_tag([enum_base(_)|_]).
ccl_tag_struct(N, Ms) :- ccl_cached_named('$ccl_ts:', N, Ms, ( nb_getval('$ccl_tags', L), member(N-Ms, L), \+ ccl_class_shape(Ms) )).
%% a member list that is a CLASS's and not a plain struct's: something in it is no data member. The
%% `align_as' a class states is LAYOUT and not a member, so it counts for neither shape -- read as one,
%% an `alignas' struct answered its raw class where its desugared struct was meant and `sizeof' had
%% nothing to lay out.
ccl_class_shape(Ms) :- member(M, Ms), \+ ccl_layout_marker(M), M \= member(_, _, _), !.
ccl_layout_marker(align_as(_)).
ccl_resolve_typedef(N, T) :- ccl_typedef_of(N, T0), ccl_resolve_type(T0, T).
ccl_add_quals([], T, T) :- !.
ccl_add_quals(Q, base(Q0, S), base(Q1, S)) :- !, append(Q, Q0, Q1).
ccl_add_quals(Q, ptr(Q0, T), ptr(Q1, T)) :- !, append(Q, Q0, Q1).
ccl_add_quals(_, T, T).
%% the one door for a struct's members, so the LAYOUT MARKERS a tag carries beside them (`align_as')
%% are taken out here: the check's field walks and the lowering's member roads read this, and a marker
%% where a member/3 is expected fails a walk without a word (`phase(check)')
ccl_members_of(T, Ms) :- ccl_members_of_(T, Ms0), ccl_data_members(Ms0, Ms).
ccl_data_members([], []) :- !.
ccl_data_members([M|Ms], Out) :- ( ccl_layout_marker(M) -> Out = Out1 ; Out = [M|Out1] ), ccl_data_members(Ms, Out1).
ccl_members_of_(base(_, [struct(_, Ms)]), Ms) :- Ms \== none, !.                 % resolved already: no resolution
ccl_members_of_(base(_, [union(_, Ms)]), Ms) :- Ms \== none, !.
ccl_members_of_(T, Ms) :- ccl_resolve_type(T, T1), ( T1 = base(_, [struct(_, Ms)]) ; T1 = base(_, [union(_, Ms)]) ), Ms \== none, !.
ccl_members_of_(T, Ms) :- ccl_resolve_type(T, base(_, [class(_, _, _, Ms0)])), !, findall(member(MT, N, I), ( member(member(MT, N, I), Ms0), \+ ( MT = base(Q, _), memberchk(static, Q) ) ), Ms).   % C++: a class's data members, the statics apart
ccl_member_type(T, N, MT) :- ccl_members_of(T, Ms), memberchk(member(MT, N, _), Ms).

%% ---- classes ----------------------------------------------------------------------
ccl_is_pointer(T) :- ccl_resolve_type(T, T1), ( T1 = ptr(_, _) ; T1 = arr(_, _) ; T1 = block(_, _) ), !.
ccl_is_float(T) :- ccl_resolve_type(T, base(_, S)), ( memberchk(double, S) ; memberchk(float, S) ; memberchk('_Float16', S) ), !.
ccl_is_integer(T) :- ccl_resolve_type(T, base(_, S)), \+ memberchk(double, S), \+ memberchk(float, S), \+ memberchk(void, S),
    ( memberchk(int, S) ; memberchk(char, S) ; memberchk(short, S) ; memberchk(long, S) ; memberchk(signed, S)
    ; memberchk(unsigned, S) ; memberchk('_Bool', S) ; memberchk(bool, S) ; memberchk(char8_t, S) ; memberchk(wchar_t, S) ; memberchk(char16_t, S) ; memberchk(char32_t, S) ; S = [enum(_, _)] ; S = [enum_class(_, _)] ; memberchk(bitint(_), S) ), !.   % C23's _BitInt(N) is an integer
ccl_is_arith(T) :- ( ccl_is_integer(T) ; ccl_is_float(T) ), !.

%% integer rank and signedness, for the usual arithmetic conversions
ccl_int_rank(T, Rank, Unsigned) :-
    ccl_resolve_type(T, base(_, S)),
    ( memberchk(unsigned, S) -> Unsigned = true ; memberchk(char16_t, S) -> Unsigned = true ; memberchk(char32_t, S) -> Unsigned = true ; memberchk(char8_t, S) -> Unsigned = true ; Unsigned = false ),   % C++'s char16_t, char32_t and char8_t are UNSIGNED; wchar_t is signed on this ABI
    (   memberchk(bitint(E), S) -> ccl_bitint_width(E, W), ccl_bitint_rank(W, Rank)           % C23: below the standard type of its width, above every narrower one (6.3.1.1)
    ; ccl_count(long, S, 2) -> Rank = 5 ; memberchk(long, S) -> Rank = 4 ; memberchk(short, S) -> Rank = 2 ; memberchk(char16_t, S) -> Rank = 2
    ; memberchk(char, S) -> Rank = 1 ; memberchk(char8_t, S) -> Rank = 1 ; memberchk('_Bool', S) -> Rank = 0 ; memberchk(bool, S) -> Rank = 0 ; Rank = 3 ).
ccl_bitint_width(E, W) :- ( ccl_const_eval(E, W0) -> W = W0 ; W = 32 ).
ccl_bitint_rank(W, R) :- ( W =< 8 -> R = 0.5 ; W =< 16 -> R = 1.5 ; W =< 32 -> R = 2.5 ; W =< 64 -> R = 3.5 ; R = 5.5 ).
ccl_is_bitint(T) :- ccl_resolve_type(T, base(_, S)), memberchk(bitint(_), S), !.
ccl_count(_, [], 0).
ccl_count(X, [Y|T], N) :- ccl_count(X, T, N0), ( X == Y -> N is N0 + 1 ; N = N0 ).
ccl_promote(T, P) :- ( \+ ccl_is_bitint(T), ccl_int_rank(T, R, _), R < 3 -> P = base([], [int]) ; P = T ).   % a _BitInt is never promoted (C23 6.3.1.1/2)
ccl_usual(A, B, T) :-
    (   ccl_is_float(A), ccl_is_float(B) -> ( ccl_resolve_type(A, base(_, SA)), memberchk(double, SA) -> T = A ; T = B )
    ;   ccl_is_float(A) -> T = A
    ;   ccl_is_float(B) -> T = B
    ;   ccl_is_integer(A), ccl_is_integer(B) ->
            ccl_promote(A, PA), ccl_promote(B, PB), ccl_int_rank(PA, RA, UA), ccl_int_rank(PB, RB, UB),
            ( RA > RB -> T = PA ; RB > RA -> T = PB ; UA == true -> T = PA ; UB == true -> T = PB ; T = PA )
    ;   T = unknown ).
%% `__builtin_add_overflow(a, b, &r)' and kin, the lowering's exact arithmetic with a bool for `did not fit'
ccl_overflow_builtin('__builtin_add_overflow', add).  ccl_overflow_builtin('__builtin_sub_overflow', sub).  ccl_overflow_builtin('__builtin_mul_overflow', mul).
ccl_size_type(T) :- ( ccl_typedef_of(size_t, _) -> T = base([], [typedef(size_t)]) ; T = base([], [unsigned, long]) ).
ccl_sizeof_expr(sizeof(_)).
ccl_sizeof_expr(sizeof_type(_)).

%% ---- the type of an expression ----------------------------------------------------
ccl_type_of(int(big(A)), T) :- !, ccl_big_type(A, T).                                  % a literal past 2^60 (0.94): the first of long and unsigned long that holds it
ccl_type_of(uint(big(_)), base([], [unsigned, long])) :- !.
ccl_type_of(int(_), base([], [int])) :- !.
ccl_type_of(uint(_), base([], [unsigned])) :- !.
ccl_type_of(long(_), base([], [long])) :- !.
ccl_big_type(A, T) :- ( ccl_big_signed(A) -> T = base([], [long]) ; T = base([], [unsigned, long]) ).
ccl_big_signed(A) :- atom_codes(A, Cs),
    (   Cs = [0'0, 0'x|Hs] -> length(Hs, N), ( N < 16 -> true ; N =:= 16, Hs = [D|_], D =< 0'7 )
    ;   length(Cs, N), ( N < 19 -> true ; N =:= 19, atom_codes('9223372036854775807', M), Cs @=< M ) ).
ccl_type_of(ulong(_), base([], [unsigned, long])) :- !.
ccl_type_of(wb(N), base([], [bitint(int(W))])) :- !, ccl_wb_width(N, W0), W is W0 + 1.   % C23's 9wb: a _BitInt of the width the value needs, plus the sign
ccl_type_of(uwb(N), base([], [unsigned, bitint(int(W))])) :- !, ccl_wb_width(N, W).
ccl_wb_width(N, W) :- ( N =:= 0 -> W = 1 ; W is msb(N) + 1 ).
ccl_type_of(bool(_), base([], [bool])) :- !.                          % C++
ccl_type_of(nullptr, ptr([], base([], [void]))) :- !.
ccl_type_of(float(_), base([], [double])) :- !.
ccl_type_of(chr(_), base([], [char])) :- ccl_lang(cpp), !.   % C++: a character literal is a char (C's is an int): `cout << ' '' takes the char inserter, not operator<<(int)
ccl_type_of(chr(_), base([], [int])) :- !.
ccl_type_of(str(_), ptr([], base([], [char]))) :- !.
ccl_type_of(wstr(_), ptr([], base([], [wchar_t]))) :- !.                          % L"...": wchar_t's, u"..." char16_t's, U"..." char32_t's
ccl_type_of(u16str(_), ptr([], base([], [char16_t]))) :- !.
ccl_type_of(u32str(_), ptr([], base([], [char32_t]))) :- !.
ccl_type_of(wchr(_), base([], [wchar_t])) :- !.
ccl_type_of(u16chr(_), base([], [char16_t])) :- !.
ccl_type_of(u32chr(_), base([], [char32_t])) :- !.
ccl_type_of(id(N), T) :- !, ( ccl_declared(N, T0) -> ccl_unref(T0, T) ; T = unknown ).
ccl_type_of(call(id(B), _), base([], [bool])) :- ccl_overflow_builtin(B, _), !.   % C23's <stdckdint.h> is written on them
ccl_type_of(call(F, _), T) :- !,
    (   F = id(N), ccl_declared(N, fn(R, _, _)) -> ccl_unref(R, T)
    ;   ccl_type_of(F, FT), ccl_resolve_type(FT, FT1),
        ( FT1 = fn(R, _, _) -> ccl_unref(R, T) ; FT1 = ptr(_, fn(R, _, _)) -> ccl_unref(R, T) ; FT1 = block(_, fn(R, _, _)) -> ccl_unref(R, T) ; T = unknown ) ).
ccl_type_of(member(E, N), T) :- !, ccl_type_of(E, ET), ( ccl_member_type(ET, N, T0) -> ccl_unref(T0, T) ; T = unknown ).
ccl_type_of(arrow(E, N), T) :- !, ccl_type_of(E, ET), ccl_resolve_type(ET, ET1),
    ( ( ET1 = ptr(_, ST) ; ET1 = arr(_, ST) ), ccl_member_type(ST, N, T0) -> ccl_unref(T0, T) ; T = unknown ).
ccl_type_of(index(A, _), T) :- !, ccl_type_of(A, AT), ccl_resolve_type(AT, AT1), ( ( AT1 = ptr(_, T0) ; AT1 = arr(_, T0) ) -> ccl_unref(T0, T) ; T = unknown ).
ccl_type_of(deref(E), T) :- !, ccl_type_of(E, ET), ccl_resolve_type(ET, ET1), ( ( ET1 = ptr(_, T0) ; ET1 = arr(_, T0) ) -> ccl_unref(T0, T) ; T = unknown ).
%% C++ (M6): a reference is the thing it refers to wherever a value is asked;
%% a qualified name is its bare name (a namespace flattens); the casts, new
ccl_type_of(scoped(_, N), T) :- !, ccl_type_of(id(N), T).
ccl_type_of(ccast(_, T0, _), T) :- !, ccl_unref(T0, T).   % a C++ cast to a REFERENCE type names the object, as every other lvalue does: `const_cast<value_type &>(*p)' has the value's type here (deduction took the reference as the argument's type and addressof's `_Tp &' became a reference to a reference)
ccl_type_of(new(T, _), ptr([], T)) :- !.
ccl_type_of(new_at(_, N), T) :- !, ccl_type_of(N, T).                              % placement new: the type the plain one has
ccl_type_of(new_array(T, _), ptr([], T)) :- !.
ccl_type_of(delete(_), base([], [void])) :- !.
ccl_type_of(delete_array(_), base([], [void])) :- !.
ccl_type_of(addr(E), T) :- !, ccl_type_of(E, ET), ( ET == unknown -> T = unknown ; T = ptr([], ET) ).
ccl_type_of(neg(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(pos(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(bitnot(E), T) :- !, ccl_type_of(E, ET), ccl_promoted_or_unknown(ET, T).
ccl_type_of(not(_), base([], [int])) :- !.
ccl_type_of(preinc(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(predec(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(postinc(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(postdec(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(sizeof(_), T) :- !, ccl_size_type(T).
ccl_type_of(sizeof_type(_), T) :- !, ccl_size_type(T).
ccl_type_of(alignof_type(_), T) :- !, ccl_size_type(T).
ccl_type_of(cast(T, _), T) :- !.
ccl_type_of(move(E), T) :- !, ccl_type_of(E, T).
ccl_type_of(compound_lit(T, _), T) :- !.
ccl_type_of(assign(_, L, _), T) :- !, ccl_type_of(L, T).
ccl_type_of(comma(_, B), T) :- !, ccl_type_of(B, T).
ccl_type_of(cond(_, A, B), T) :- !, ccl_type_of(A, AT), ccl_type_of(B, BT),
    (   ccl_is_arith(AT), ccl_is_arith(BT) -> ccl_usual(AT, BT, T)
    ;   A == nullptr -> T = BT          % a null pointer constant takes the OTHER arm's type ([expr.cond]), unknown included: typed `void *' by its
    ;   B == nullptr -> T = AT          % nullptr while the other arm was still unknown, `__nbc > 0 ? allocate(...) : nullptr' chose unique_ptr's `reset(nullptr_t)' and dropped the buckets
    ;   AT \== unknown -> T = AT ; T = BT ).
ccl_type_of(stmt_expr(block(Is)), T) :- !,            % its declarations are in scope for its last expression
    ccl_scope_push, ccl_note_items(Is),
    ( append(_, [expr(_, E)], Is) -> ccl_type_of(E, T) ; T = base([], [void]) ),
    ccl_scope_pop.
ccl_type_of(bin(Op, A, B), T) :- !,
    ccl_type_of(A, AT), ccl_type_of(B, BT),
    (   memberchk(Op, ['<', '>', '<=', '>=', '==', '!=', '&&', '||']) -> T = base([], [int])
    ;   memberchk(Op, ['<<', '>>']) -> ccl_promoted_or_unknown(AT, T)
    ;   memberchk(Op, ['+', '-']), ccl_is_pointer(AT), ccl_is_pointer(BT) -> T = base([], [long])
    ;   memberchk(Op, ['+', '-']), ccl_is_pointer(AT) -> ccl_decay(AT, T)
    ;   Op == '+', ccl_is_pointer(BT) -> ccl_decay(BT, T)
    ;   ccl_is_arith(AT), ccl_is_arith(BT) -> ccl_usual(AT, BT, T)
    ;   T = unknown ).
ccl_type_of(_, unknown).
ccl_unref(ref(_, T), T) :- !.
ccl_unref(rref(_, T), T) :- !.
ccl_unref(T, T).
%% a range-for over an array as the for it is: `for (T x : xs) S' is
%% `for (int i = 0; i < N; i++) { T x = xs[i]; S }', an `auto &' binding a
%% reference to the element; the check and the lowering both walk the for
ccl_for_each_as_for(for_each(L, var(N, T, none), Range, S),
                    for(L, decl(base([], [int]), [var(I, base([], [int]), int(0))]), bin('<', id(I), NE), postinc(id(I)),
                        block([declaration(L, none, ET, [var(N, T1, index(Range, id(I)))]), S]))) :-
    ccl_type_of(Range, RT), ccl_resolve_type(RT, arr(NE, ET)),
    ccl_gensym('$i', I), ccl_range_var_type(T, ET, T1).
ccl_range_var_type(base(_, [auto]), ET, ET) :- !.
ccl_range_var_type(ref(Q, base(_, [auto])), ET, ref(Q, ET)) :- !.
ccl_range_var_type(rref(Q, base(_, [auto])), ET, ref(Q, ET)) :- !.
ccl_range_var_type(ptr(Q, base(_, [auto])), ET, T) :- !, ( ccl_resolve_type(ET, ptr(_, _)) -> T = ET ; T = ptr(Q, ET) ).
ccl_range_var_type(T, _, T).
ccl_promoted_or_unknown(ET, T) :- ( ccl_is_integer(ET) -> ccl_promote(ET, T) ; ccl_is_float(ET) -> T = ET ; T = unknown ).
%% an array decays to a pointer to its element, a function to a pointer to
%% itself; anything else keeps its name (a typedef stays a typedef)
%% the canonical form of a resolved type, for `_Generic' (the reader) -- every typedef resolved through the pointers,
%% arrays and functions, the specifiers sorted with `signed' dropped (but on a char), `int' dropped beside short or
%% long and supplied for a bare `unsigned', so `unsigned' and `unsigned int' are one type as C has them
ccl_type_canon(T, K) :- ccl_resolve_type(T, T1), ccl_type_canon_(T1, K).
ccl_type_canon_(base(Q, S), base(Q1, K)) :- !, msort(Q, Q1), msort(S, S1), ( memberchk(char, S1) -> S2 = S1 ; delete(S1, signed, S2) ),
    ( ( memberchk(short, S2) ; memberchk(long, S2) ) -> delete(S2, int, S3) ; S2 == [unsigned] -> S3 = [int, unsigned] ; S3 = S2 ), ccl_canon_specs(S3, K).
ccl_type_canon_(ptr(_, T), ptr(K)) :- !, ccl_type_canon(T, K).
ccl_type_canon_(arr(N, T), arr(V, K)) :- !, ( ccl_const_eval(N, V) -> true ; V = N ), ccl_type_canon(T, K).
ccl_type_canon_(fn(R, Ps, V), fn(RK, PKs, V)) :- !, ccl_type_canon(R, RK), findall(PK, ( member(param(PT, _), Ps), ccl_type_canon(PT, PK) ), PKs).
ccl_type_canon_(T, T).
ccl_canon_specs([], []).
ccl_canon_specs([S|Ss], [K|Ks]) :- ( S = struct(Tag, _) -> K = struct(Tag) ; S = union(Tag, _) -> K = union(Tag) ; S = enum(Tag, _) -> K = enum(Tag) ; K = S ), ccl_canon_specs(Ss, Ks).
ccl_decay(T, D) :- ccl_resolve_type(T, T1), ( T1 = arr(_, E) -> D = ptr([], E) ; T1 = fn(_, _, _) -> D = ptr([], T1) ; D = T ).

%% ---- sizes, LP64 ---------------------------------------------------------------------
ccl_size_of(T, N) :- ccl_resolve_type(T, T1), ccl_size_align(T1, N, _).
ccl_size_align(ptr(_, _), 8, 8) :- !.
ccl_size_align(block(_, _), 8, 8) :- !.
ccl_size_align(fn(_, _, _), 8, 8) :- !.
ccl_size_align(memptr(_, _, fn(_, _, _)), 8, 8) :- !.                          % a pointer to member function: the address of the one function emitted for it
ccl_size_align(arr(NE, E), N, A) :- !, ( ccl_size_align(E, EN0, A0) -> EN = EN0, A = A0 ; ccl_resolve_type(E, E1), ccl_size_align(E1, EN, A) ), ( ccl_const_eval(NE, K) -> N is K * EN ; N = 0 ).   % a flexible member, `T a[]' or `own T *a[n]': no bytes of its own; the ELEMENT resolved (the resolver leaves an array as it is, and `std::string s[2]' had no size)
ccl_size_align(base(_, S), N, A) :- memberchk(bitint(E), S), !, ccl_bitint_width(E, W),     % _BitInt(N): the smallest integer type that holds it up to 64 bits; past that, whole eightbytes aligned 8 (the psABI)
    ( W =< 8 -> N = 1 ; W =< 16 -> N = 2 ; W =< 32 -> N = 4 ; N is ((W + 63) // 64) * 8 ), ( N > 8 -> A = 8 ; A = N ).
ccl_size_align(base(_, S), N, A) :- ccl_basic_size(S, N), !, A = N.
ccl_size_align(base(_, [struct(_, Ms)]), N, A) :- Ms \== none, !, ccl_struct_layout(Ms, 0, 1, N0, A0), ccl_tag_size(Ms, N0, A0, N, A).
ccl_size_align(base(_, [union(_, Ms)]), N, A) :- Ms \== none, !, ccl_union_layout(Ms, 0, 1, N0, A0), ccl_tag_size(Ms, N0, A0, N, A).
%% a tag's size and alignment: the members' own, the empty class's byte, and `alignas' where the class
%% states one ([dcl.align]: never smaller than the natural alignment, and the size rounds up to it)
ccl_tag_size(Ms, N0, A0, N, A) :- ccl_class_size(Ms, N0, N1), ccl_align_as(Ms, A0, A), ccl_round_up(N1, A, N).
ccl_align_as(Ms, A0, A) :- findall(V, ( member(align_as(E), Ms), ccl_const_eval(E, V) ), Vs), ccl_max_align(Vs, A0, A).
ccl_max_align([], A, A).
ccl_max_align([V|Vs], A0, A) :- ( V > A0 -> A1 = V ; A1 = A0 ), ccl_max_align(Vs, A1, A).
%% AN EMPTY CLASS HAS SIZE ONE ([class]/4): two objects of it must have two addresses, an array of
%% them n, and `new' must hand back something. In C an empty struct is a GNU extension of no bytes
%% and stays so. The rule cannot be written without the one beside it -- an empty BASE takes no
%% bytes (cpp_base_layout, the empty base optimization) -- or every class deriving from an empty one
%% would grow by a byte where C++ gives it none, and libc++'s allocators, comparators and tuple
%% leaves are empty bases everywhere.
ccl_class_size(Ms, 0, N) :- ccl_lang(cpp), ccl_no_data_members(Ms), !, N = 1.   % NO DATA MEMBERS AT ALL is what [class]/4 asks: a class whose one member is a zero-length array (libc++'s compressed-pair padding, `char __padding_[sizeof(T) - __datasizeof_v<T>]') HAS a member and keeps the no bytes the GNU extension gives it
ccl_class_size(_, N, N).
ccl_size_align(base(_, [enum(_, [enum_base(T)|_])]), N, A) :- !, ccl_size_align(T, N, A).   % `enum E : size_t' is eight bytes
ccl_size_align(base(_, [enum(_, _)]), 4, 4) :- !.
ccl_size_align(base(_, [enum_class(_, _)]), 4, 4) :- !.
ccl_size_align(ref(_, _), 8, 8) :- !.                                            % C++: a reference is a pointer in memory
ccl_size_align(rref(_, _), 8, 8) :- !.
ccl_basic_size(S, N) :- ( memberchk(double, S) -> N = 8 ; memberchk(float, S) -> N = 4 ; memberchk('_Float16', S) -> N = 2 ; memberchk('_Decimal32', S) -> N = 4 ; memberchk('_Decimal64', S) -> N = 8 ; memberchk('_Decimal128', S) -> N = 16 ; ccl_count(long, S, 2) -> N = 8
    ; memberchk(long, S) -> N = 8 ; memberchk(short, S) -> N = 2 ; memberchk(char, S) -> N = 1 ; memberchk('_Bool', S) -> N = 1 ; memberchk(bool, S) -> N = 1 ; memberchk(char8_t, S) -> N = 1 ; memberchk(char16_t, S) -> N = 2 ; memberchk(wchar_t, S) -> N = 4 ; memberchk(char32_t, S) -> N = 4
    ; memberchk(int, S) -> N = 4 ; memberchk(unsigned, S) -> N = 4 ; memberchk(signed, S) -> N = 4 ; memberchk(void, S) -> N = 1 ; fail ).
ccl_struct_layout(Ms, _, _, N, Al) :- ccl_members_layout(Ms, _, N, Al).
%% ccl_members_layout(+Members, -Lays, -Size, -Align): where every member lies --
%% lay(Name, T, ByteOff, none) for a plain member, lay(Name, T, UnitByteOff,
%% bits(BitOffInUnit, Width, UnitBytes)) for a bitfield. The packing is the
%% SysV one (clang's): a bitfield lands at the next bit unless it would cross
%% a boundary of its declared type's alignment, then at that boundary; a zero
%% width closes the unit; a plain member is aligned as usual; the struct's
%% alignment counts every member's, a bitfield's declared type included.
%% a struct's layout is asked at every member access: kept per member list
ccl_members_layout(Ms, Lays, Size, Align) :- ccl_cached('$ccl_laycache', Ms, lay(Lays, Size, Align), ccl_members_layout_nocache(Ms, Lays, Size, Align)).
ccl_members_layout_nocache(Ms, Lays, Size, Align) :- ccl_members_layout_(Ms, 0, 1, acc([], 0), Lays, Bits, Align, EE), Bytes0 is (Bits + 7) // 8, Bytes is max(Bytes0, EE), ccl_round_up(Bytes, Align, Size).
%% THE EMPTY SUBOBJECTS PLACED SO FAR travel with the walk (acc(Seen, EmptyEnd): the empty subobjects' tags and offsets,
%% and the byte past the last of them), since an EMPTY `[[no_unique_address]]' MEMBER IS PLACED BY THE ABI'S RULE
%% (Itanium 2.4 II.3, measured against clang++, 0.96): at offset ZERO, whatever lies there, unless an empty subobject of
%% ITS OWN TYPE is there already -- then at the current data size, rounded to its alignment, and on by its alignment
%% while such a subobject is in the way. It takes no bytes of the data, and the class's size still covers its byte.
%% `struct { int x; [[no_unique_address]] E a, b; }' is `a' at 0, `b' at 4, eight bytes; `struct { [[no_unique_address]]
%% E a; char c; }' one byte, `c' at 0. Before, such a member lay one past the members before it (0.89's not-done).
ccl_members_layout_([], Bits, Al, acc(_, EE), [], Bits, Al, EE).
ccl_members_layout_([member(T, N, W0)|Ms], Bit0, Al0, acc(Seen, EE0), Lays, Bits, Al, EE) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), ABits is A * 8,
    (   W0 == no_unique_address, ccl_empty_layout(T1)
    ->  ccl_empty_tag(T1, Tag), ccl_empty_offset(Tag, A, Bit0, Seen, Off), Bit1 = Bit0, Al1 is max(Al0, A),   % no bytes, its ALIGNMENT kept -- libc++ marks every container's allocator and comparator with it
        EE1 is max(EE0, Off + S), Seen1 = [Tag-Off|Seen],
        Lays = [lay(N, T, Off, empty)|Lays1]
    ;   ccl_plain_width(W0)
    ->  ccl_round_up(Bit0, ABits, B1), Off is B1 // 8, Bit1 is B1 + S * 8, Al1 is max(Al0, A), EE1 = EE0,
        ( ccl_empty_layout(T1), ccl_empty_tag(T1, Tag) -> Seen1 = [Tag-Off|Seen] ; Seen1 = Seen ),   % a plain member of an empty class is an empty subobject too, and its byte is in the way of a marked one of its type
        Lays = [lay(N, T, Off, none)|Lays1]
    ;   ccl_bit_width(W0, W), Seen1 = Seen, EE1 = EE0,
        (   W =:= 0 -> ccl_round_up(Bit0, ABits, Bit1), Al1 = Al0, Lays = Lays1
        ;   ( (Bit0 mod ABits) + W > ABits -> ccl_round_up(Bit0, ABits, Start) ; Start = Bit0 ),
            UnitStart is (Start // ABits) * ABits, Off is UnitStart // 8, BOff is Start - UnitStart,
            Bit1 is Start + W, Al1 is max(Al0, A),
            Lays = [lay(N, T, Off, bits(BOff, W, S))|Lays1] ) ),
    ccl_members_layout_(Ms, Bit1, Al1, acc(Seen1, EE1), Lays1, Bits, Al, EE).
%% A LAYOUT IS OVER DATA MEMBERS: a C++ class's tag carries its constructors, methods and typedefs beside them, and
%% a nested one reaches the layout as the reader gave it -- libc++'s `union __rep' has three constructors.
ccl_members_layout_([_|Ms], Bit0, Al0, Acc, Lays, Bits, Al, EE) :- ccl_members_layout_(Ms, Bit0, Al0, Acc, Lays, Bits, Al, EE).
ccl_empty_tag(base(_, [struct(Tag, _)]), Tag) :- !.
ccl_empty_tag(base(_, [union(Tag, _)]), Tag) :- !.
ccl_empty_tag(T, T).
ccl_empty_offset(Tag, A, Bit0, Seen, Off) :-
    (   \+ memberchk(Tag-0, Seen) -> Off = 0
    ;   Bytes is (Bit0 + 7) // 8, ccl_round_up(Bytes, A, C0), ccl_empty_step(Tag, A, Seen, C0, Off) ).
ccl_empty_step(Tag, A, Seen, C, Off) :- ( memberchk(Tag-C, Seen) -> C1 is C + A, ccl_empty_step(Tag, A, Seen, C1, Off) ; Off = C ).
ccl_plain_width(none).
ccl_plain_width(no_unique_address).                                              % the mark is no bitfield width: a member carrying it over a type with bytes lies where it always did
%% AN EMPTY CLASS IS ONE WITH NO DATA MEMBERS AT ALL ([class]/4) -- the same test `ccl_class_size' asks, and
%% written once. NOT "lays out to zero": `ccl_members_layout_' SKIPS a member whose type it cannot size yet (its
%% last clause takes anything), so a class whose members are not resolvable at the moment of asking lays out to
%% zero and would read as empty. libc++'s compressed pair marks `__rep_' ITSELF with `[[no_unique_address]]', and
%% by the weaker test basic_string's 24-byte union became a member of no bytes -- the struct came out
%% `{ {}, padding, {}, {} }' with no `__rep_' in it, every string was its own first byte, and `a + ", "' was empty.
ccl_empty_layout(T) :- ( T = base(_, [struct(_, Ms)]) ; T = base(_, [union(_, Ms)]) ), Ms \== none, ccl_no_data_members(Ms).
ccl_no_data_members(Ms) :- \+ member(member(_, _, _), Ms).
ccl_bit_width(int(W), W) :- !.
ccl_bit_width(W, W) :- integer(W), !.
ccl_bit_width(E, W) :- ccl_const_eval(E, W).
ccl_union_layout([], S, Al, N, Al) :- ccl_round_up(S, Al, N).
ccl_union_layout([member(T, _, _)|Ms], S0, Al0, N, Al) :-
    ccl_resolve_type(T, T1), ccl_size_align(T1, S, A), S1 is max(S0, S), Al1 is max(Al0, A), ccl_union_layout(Ms, S1, Al1, N, Al).
ccl_union_layout([_|Ms], S0, Al0, N, Al) :- ccl_union_layout(Ms, S0, Al0, N, Al).      % the data members alone, as above
ccl_round_up(X, A, Y) :- Y is ((X + A - 1) // A) * A.

%% ---- the tie operator, `<*>' --------------------------------------------------
%% `x <*> y' declares x to live within y. The reader keeps it as the qualifier
%% tie(Y) in the OUTERMOST qualifier list of x's type -- through an array to
%% its element, through a function to its result, which is how a result is
%% tied to a parameter. The check reads it (library(ccl_check)); the lowering
%% and the layout never look at a qualifier, so it costs them nothing.
ccl_add_tie(Y, base(Q, S), base([tie(Y)|Q], S)) :- !.
ccl_add_tie(Y, ptr(Q, T), ptr([tie(Y)|Q], T)) :- !.
ccl_add_tie(Y, block(Q, T), block([tie(Y)|Q], T)) :- !.
ccl_add_tie(Y, arr(N, T0), arr(N, T)) :- !, ccl_add_tie(Y, T0, T).
ccl_add_tie(Y, fn(R0, Ps, V), fn(R, Ps, V)) :- !, ccl_add_tie(Y, R0, R).
ccl_add_tie(_, T, T).
ccl_tie_of(base(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(ptr(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(block(Q, _), Y) :- memberchk(tie(Y), Q), !.
ccl_tie_of(arr(_, T), Y) :- !, ccl_tie_of(T, Y).
ccl_tie_of(fn(R, _, _), Y) :- !, ccl_tie_of(R, Y).
%% a struct (or union) with an own member, at any depth held by value: its copy
%% would own the same memory twice, so clone refuses it
ccl_has_own_member(T) :- ccl_members_of(T, Ms), member(member(MT, _, _), Ms), ( ccl_own_quals(MT) -> true ; ccl_has_own_member(MT) ), !.
ccl_own_quals(ptr(Q, B)) :- ( memberchk(own, Q) ; B = base(Q2, _), memberchk(own, Q2) ), !.
ccl_own_quals(base(Q, _)) :- memberchk(own, Q), !.
ccl_own_quals(arr(_, T)) :- ccl_own_quals(T), !.
