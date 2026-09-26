#!/bin/sh
# test/warm.sh [SECS] [MB]: warm the C++ summary cache OUTSIDE the gates -- one header a process, at every level a
# fixture asks for, so a gate never pays a cold flatten (a killed cold run writes no summary and stays cold; the
# finding in CLAUDE.md). The headers are the ones test/cpp/*.cpp and test/cpp/run/*.cpp include, each at the
# level its .flags gives and at C++17, with Cicili's own test/cpp/*.cpp (the reader's whole reads), <version> first
# (the gate's NAME.needs test reads it). Each build is
# capped: SECS a header (2400), MB of resident size (7000), the cap of a whole gate.
SECS=${1:-2400}; MB=${2:-7000}
ROOT=$(cd "$(dirname "$0")/.." && pwd); . "$ROOT/test/config.sh"
W=$(mktemp -d -t cclwarm.XXXXXX); trap 'rm -rf "$W"' EXIT
levels() { for f in "$ROOT"/test/cpp/*.cpp "$ROOT"/test/cpp/run/*.cpp "$CICILI"/test/cpp/*.cpp; do   # ... and Cicili's own C++ test files, which the reader's gate reads WHOLE (<sstream>, <stdexcept>: the cold flatten every reader bump used to pay inside the gate)
    std=17; fl="${f%.cpp}.flags"; [ -f "$fl" ] && std=$(sed -n 's/.*-std=c++\([0-9]*\).*/\1/p' "$fl"); [ -n "$std" ] || std=17
    echo "$std version"; sed -n 's/^#include <\([^>]*\)>.*/\1/p' "$f" | sed "s/^/$std /"; done | sort -u; }
[ -n "$(ls "$CICILI"/test/cpp/*.cpp 2>/dev/null)" ] || echo "warm: no C++ test files under CICILI=$CICILI -- Cicili's headers (<sstream>, <stdexcept>) are NOT warmed"
n=0; start=$(date +%s)
echo "warm: $(levels | wc -l | tr -d ' ') headers"
levels | while read -r std h; do
  f="$W/w.cpp"; printf '#include <%s>\nint main() { return 0; }\n' "$h" > "$f"
  a=$(date +%s)
  ( "$ROOT/bin/cicili++" -std=c++$std -fsyntax-only "$f" > "$W/out" 2>&1 < /dev/null & p=$!
    t=0; peak=0
    while kill -0 $p 2>/dev/null; do sleep 1; t=$((t + 1)); rss=$(ps -eo rss,args | awk '/[c]ocolog .*query/ { s += $1 } END { print int(s / 1024) }'); [ "$rss" -gt "$peak" ] && peak=$rss
      if [ "$rss" -gt "$MB" ] || [ "$t" -ge "$SECS" ]; then pkill -9 -f "[c]ocolog .*query"; echo "KILLED at ${rss} MB, ${t} s" >> "$W/out"; break; fi; done
    wait $p; echo "peak $peak MB" >> "$W/out" )
  b=$(date +%s); echo "-std=c++$std <$h>: $((b - a)) s, $(tail -1 "$W/out")$(grep -q KILLED "$W/out" && echo ' -- KILLED, the summary NOT written')"
done
echo "warm: $(( $(date +%s) - start )) s"
