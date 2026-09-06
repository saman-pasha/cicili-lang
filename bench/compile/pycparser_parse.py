# pycparser, the C parser written in Python (pip install pycparser): the
# file parsed to its AST, the preprocessing done by clang -E over
# pycparser's fake headers (the package ships none: FAKE is the
# utils/fake_libc_include directory of its repository).
#   python3 bench/compile/pycparser_parse.py FAKE FILE.c [K]     K runs, the minimum printed
import sys, time, pycparser
fake, path = sys.argv[1], sys.argv[2]; k = int(sys.argv[3]) if len(sys.argv) > 3 else 5
best = None
for _ in range(k):
    t0 = time.time()
    pycparser.parse_file(path, use_cpp=True, cpp_path='clang', cpp_args=['-E', '-I' + fake])
    best = min(best or 9e9, time.time() - t0)
print("%.3f" % best)
