# ShivyC, a C compiler written in Python (pip install shivyc), driven to
# assembly text: its front end, IL and x86-64 code generation, without the
# Linux-only check, assembler and linker its command runs. The one row a
# Python compiler can give on this Mac; the B-tree needs more of C than it
# has (enum, ?:, sizeof of a type, a variadic prototype).
#   python3 bench/compile/shivyc_asm.py FILE.c [K]     K runs, the minimum printed
import sys, time, platform
platform.system = lambda: "Linux"; platform.machine = lambda: "x86_64"
import shivyc.lexer as lexer, shivyc.preproc as preproc
from shivyc.errors import error_collector, CompilerError
from shivyc.parser.parser import parse
from shivyc.il_gen import ILCode, SymbolTable, Context
from shivyc.asm_gen import ASMCode, ASMGen
class Args: variables = False; show_reg_alloc_perf = False
def to_asm(path):
    with open(path) as f: code = f.read()
    toks = preproc.process(lexer.tokenize(code, path), path)
    root = parse(toks)
    if root is None or not error_collector.ok(): raise CompilerError("parse failed")
    il = ILCode(); st = SymbolTable(); root.make_il(il, st, Context())
    asm = ASMCode(); ASMGen(il, st, asm, Args()).make_asm()
    return asm.full_code()
path = sys.argv[1]; k = int(sys.argv[2]) if len(sys.argv) > 2 else 5
best = None
for _ in range(k):
    t0 = time.time(); asm = to_asm(path); best = min(best or 9e9, time.time() - t0)
print("%.3f" % best)
