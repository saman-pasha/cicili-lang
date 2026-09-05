%% cicili-lang -- library(ccl_build): from IR to an object file, and from
%% object files to a binary or a library.
%%
%%   cicili_compile(+IR, +File, +Flags)   the IR module text -> the object File;
%%                                        Flags a list of atoms ('-O2', '-g' ...)
%%   cicili_link(+Objects, +Flags, +Out)  object files -> Out, a binary, or a
%%                                        library when Flags say so (-shared)
%%
%% cicili_compile goes through the embedded LLVM, library(ccl_llvm), when it
%% is built: parse, verify, the passes the flags ask for, the object. Until
%% then, and wherever the module is absent, the same IR goes through clang
%% (`clang -c -x ir'), which is the LLVM backend by another door -- M0's
%% proof -- so the pipeline is whole either way. cicili_link drives the
%% system linker through cc, the way Cicili drives cc for its C.

:- use_module(library(process)).

ccl_compile(IR, File, Flags) :-
    ( ccl_llvm_ready -> ccl_llvm_compile(IR, File, Flags) ; ccl_compile_clang(IR, File, Flags) ).
ccl_llvm_ready :- once(catch(use_module(library(ccl_llvm)), _, fail)), once(catch(ccl_llvm_version(_), _, fail)).

ccl_compile_clang(IR, File, Flags) :-
    tmp_file(ccl_ir, T0), atom_concat(T0, '.ll', LL),
    atom_codes(IR, Codes), write_file_from_codes(LL, Codes),
    ccl_words(Flags, F),
    atomic_list_concat(['clang -c -x ir \'', LL, '\' -o \'', File, '\' ', F, ' 2>&1'], Cmd),
    ccl_sh(Cmd, Out, Exit),
    ( Exit =:= 0 -> true ; atom_codes(Msg, Out), throw(error(compile_failed(Msg), cicili_compile(File))) ).

ccl_link(Objects, Flags, Out) :-
    ccl_words(Objects, Os), ccl_words(Flags, F),
    ( ccl_lang(cpp) -> Ld = 'c++' ; Ld = cc ),                                % cicili++ links through c++
    atomic_list_concat([Ld, ' ', Os, ' ', F, ' -o \'', Out, '\' 2>&1'], Cmd),
    ccl_sh(Cmd, O, Exit),
    ( Exit =:= 0 -> true ; atom_codes(Msg, O), throw(error(link_failed(Msg), cicili_link(Out))) ).

ccl_sh(Cmd, Out, Exit) :- ( once(catch(proc_run(Cmd, 300000, Out, Exit), _, fail)) -> true ; Out = "could not run", Exit = 1 ).
ccl_words([], '').
ccl_words([W|Ws], A) :- ccl_words(Ws, A1), atomic_list_concat(['\'', W, '\' ', A1], A).
