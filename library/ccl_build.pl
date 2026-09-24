%% cicili-lang -- library(ccl_build): from IR to an object file, and from
%% object files to a binary or a library.
%%
%%   cicili_compile(+IR, +File, +Flags)   the IR module text -> the object File;
%%                                        Flags a list of atoms ('-O2', '-g' ...)
%%   cicili_link(+Objects, +Flags, +Out)  object files -> Out, a binary, or a
%%                                        library when Flags say so (-shared)
%%
%% cicili_compile goes through the embedded LLVM, library(ccl_llvm): parse,
%% verify, the passes the flags ask for, the object. That module is the whole
%% back end (owner's rule: no clang, no LLVM binary); where it is not built
%% the compile is an error naming module/build-llvm.sh. cicili_link drives
%% the system linker through cc (c++ for cicili++), the way Cicili drives cc
%% for its C: llvm-c has no linker to embed.

:- use_module(library(process)).

ccl_compile(IR, File, Flags) :-
    ( ccl_llvm_ready -> ccl_llvm_compile(IR, File, Flags) ; throw(error(no_embedded_llvm, cicili_compile(File))) ).
ccl_llvm_ready :- once(catch(use_module(library(ccl_llvm)), _, fail)), once(catch(ccl_llvm_version(_), _, fail)).

ccl_link(Objects, Flags, Out) :-
    ccl_words(Objects, Os), ccl_words(Flags, F),
    ( ccl_lang(cpp) -> Ld = 'c++' ; Ld = cc ),                                % cicili++ links through c++
    ccl_link_libs(Libs),
    atomic_list_concat([Ld, ' ', Os, ' ', F, Libs, ' -o \'', Out, '\' 2>&1'], Cmd),
    ccl_sh(Cmd, O, Exit),
    ( Exit =:= 0 -> true ; atom_codes(Msg, O), throw(error(link_failed(Msg), cicili_link(Out))) ).

%% THE C++ RUNTIME IS NAMED ON LINUX (0.93): a program is compiled against libc++'s headers (the one tree this compiler reads,
%% ccl_toolchain_dirs), and on macOS `c++' is clang, whose C++ library is libc++; on Debian and Ubuntu `c++' is g++, whose is
%% libstdc++, so the link found no `std::__1::__libcpp_verbose_abort' -- libc++'s runtime, `-lc++', is asked for by name there.
ccl_link_libs(' -lc++') :- ccl_lang(cpp), ccl_host_os(linux), !.
ccl_link_libs('').
ccl_sh(Cmd, Out, Exit) :- ( once(catch(proc_run(Cmd, 300000, Out, Exit), _, fail)) -> true ; Out = "could not run", Exit = 1 ).
ccl_words([], '').
ccl_words([W|Ws], A) :- ccl_words(Ws, A1), atomic_list_concat(['\'', W, '\' ', A1], A).
