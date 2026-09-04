#!/bin/sh
# The gate for library(cicili): one check per rule of the language, over
# cocolog as it is. GREEN or RED, exit 1 on RED. SKIPs when the module is
# not built (sh module/build.sh says how).
#
#   sh test/objects.sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
[ -x "$C" ] || { echo "SKIP (no cocolog binary at $C -- set COCOLOG)"; exit 0; }
[ -f "$ROOT/library/cicili.so" ] || { echo "SKIP (no library/cicili.so -- sh module/build.sh)"; exit 0; }
if ! "$C" query "use_module(library(cicili)), ccl_version(_)" >/dev/null 2>&1; then
  echo "SKIP (library(cicili) does not start)"; exit 0
fi
failures=0
check() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %-58s %s\n' "$1" "$(echo "$2" | cut -c1-40)"
  else
    printf 'FAIL %-58s\n     got  %s\n     want %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}
answer() { grep -aoE 'answer\(.*\)' | head -1 | sed 's/^answer(//; s/)$//'; }
D=$(mktemp -d "${TMPDIR:-/tmp}/cicili-XXXXXX")
trap 'rm -rf "$D"' EXIT

# ---- the objects of tutorial 01, consulted from a file ---------------------
cat > "$D/counters.pl" <<'EOF'
:- use_module(library(cicili)).
:- object(counter).
   state(count = 0).
   next(N) :- count := count + 1, N = count.
   reset   :- count := 0.
   twice(N) :- next(_), next(N).
   clone(C2) :- new(counter, [count = count], C2).
:- end_object.
:- object(named_counter, extends(counter)).
   state(name = anonymous).
   label(L) :- format(atom(L), "~w: ~w", [name, count]).
   reset    :- super::reset, name := anonymous.
:- end_object.
:- object(greeter).
   hello(Who, Text) :- atom_concat('hello ', Who, Text).
:- end_object.
EOF
q() { "$C" --local run "$D/counters.pl" "$1" 2>&1 | answer; }

echo "-- objects, slots, methods"
check "an object declares its slots with their initial values" \
  "$(q "findall(S-V, '\$slot'(counter, S, V), L), write(answer(L)), nl")" "[count-0]"
check "a method is a clause under the qualified name, Self first" \
  "$(q "current_predicate('counter::next'/2), write(answer(yes)), nl")" "yes"
check "the unqualified clauses are gone from the file's namespace" \
  "$(q "( catch(clause(next(_), _), _, fail) -> R = still_there ; R = gone ), write(answer(R)), nl")" "gone"
check "new/3 makes an instance with the slots' initial values" \
  "$(q "new(counter, [], C), slot(C, count, V), write(answer(V)), nl")" "0"
check ":= assigns, and a slot name reads, inside a method" \
  "$(q "new(counter, [], C), C::next(A), C::next(B), write(answer(A-B)), nl")" "1-2"
check "an unqualified call inside a method is a message to Self" \
  "$(q "new(counter, [], C), C::twice(N), write(answer(N)), nl")" "2"
check "a slot name is a read, except as the key of Key = Value" \
  "$(q "new(counter, [count = 7], C), C::clone(C2), slot(C2, count, V), write(answer(V)), nl")" "7"
check "a method with plain arguments and no state" \
  "$(q "new(greeter, [], G), G::hello(world, T), write(answer(T)), nl")" "hello world"
check "new/3 sets the slots it is given" \
  "$(q "new(named_counter, [name = clicks, count = 5], C), C::label(L), write(answer(L)), nl")" "clicks: 5"

echo "-- inheritance"
check "the child has the parent's slots and methods" \
  "$(q "new(named_counter, [], C), C::next(N), slot(C, name, Nm), write(answer(N-Nm)), nl")" "1-anonymous"
check "a redefined method wins, and super:: reaches the parent's" \
  "$(q "new(named_counter, [name = x], C), C::next(_), C::reset, C::label(L), write(answer(L)), nl")" "anonymous: 0"
check "instance_of holds for the class and every ancestor" \
  "$(q "new(named_counter, [], C), findall(K, instance_of(C, K), Ks), write(answer(Ks)), nl")" "[named_counter,counter]"
check "extends/2 is the declared parent" \
  "$(q "extends(named_counter, P), write(answer(P)), nl")" "counter"
check "instances/2 of a parent include the children's" \
  "$(q "new(counter, [], _), new(named_counter, [], _), instances(counter, Is), length(Is, N), write(answer(N)), nl")" "2"

echo "-- static calls, set_slot, delete"
check "a class as receiver is a static call" \
  "$(q "greeter::hello(there, T), write(answer(T)), nl")" "hello there"
check "a slot read in a static call is an error that says so" \
  "$(q "catch(counter::next(_), error(ccl_error(M), _), true), write(answer(M)), nl")" \
  "a slot read needs an instance: this is a static call"
check "set_slot/3 writes from outside" \
  "$(q "new(counter, [], C), set_slot(C, count, 41), C::next(N), write(answer(N)), nl")" "42"
check "delete/1 removes the instance and its values" \
  "$(q "new(counter, [], C), delete(C), ( catch(slot(C, count, _), error(existence_error(instance, _), _), fail) -> R = still ; R = gone ), write(answer(R)), nl")" "gone"

echo "-- errors are terms"
check "an unknown method" \
  "$(q "new(counter, [], C), catch(C::fly, error(E, _), true), write(answer(E)), nl")" \
  "existence_error(method,counter::fly/1)"
check "an unknown slot in new/3" \
  "$(q "catch(new(counter, [size = 1], _), error(E, _), true), write(answer(E)), nl")" \
  "existence_error(slot,counter::size)"
check "an unknown object" \
  "$(q "catch(new(rocket, [], _), error(E, _), true), write(answer(E)), nl")" \
  "existence_error(object,rocket)"
check "a message to nothing" \
  "$(q "catch(nobody::hello, error(E, _), true), write(answer(E)), nl")" \
  "existence_error(object,nobody)"

# ---- modules ---------------------------------------------------------------
cat > "$D/shapes.pl" <<'EOF'
:- use_module(library(cicili)).
:- module(geometry).
:- object(shape).
   state(name = shape).
   area(0).
:- end_object.
:- object(circle, extends(shape)).
   state(r = 1).
   area(A) :- A is pi * r * r.
   unit(C) :- new(circle, [r = 1], C).
   twins(C1, C2) :- unit(C1), circle::unit(C2).
:- end_object.
:- end_module.
EOF
qs() { "$C" --local run "$D/shapes.pl" "$1" 2>&1 | answer; }
echo "-- modules"
check "an object in a module has its full name" \
  "$(qs "objects(Os), write(answer(Os)), nl")" "[geometry::circle,geometry::shape]"
check "the parent resolves by short name inside the module" \
  "$(qs "extends('geometry::circle', P), write(answer(P)), nl")" "geometry::shape"
check "new/3 takes Module::Object" \
  "$(qs "new(geometry::circle, [r = 2], C), C::area(A), R is round(A * 100), write(answer(R)), nl")" "1257"
check "inside a module, a method names a sibling object short" \
  "$(qs "geometry::circle::unit(C), object_of(C, K), write(answer(K)), nl")" "geometry::circle"
check "and a short static call, from a static call" \
  "$(qs "geometry::circle::twins(A, B), instance_of(A, geometry::circle), instance_of(B, geometry::shape), write(answer(both)), nl")" "both"

# ---- persistence: an instance outlives its process -----------------------
echo "-- an instance outlives the process that made it"
S="$D/store"
"$C" --embed "$S" run "$D/counters.pl" "new(named_counter, [name = kept], C), C::next(_), C::next(_), write(made(C)), nl" > "$D/p1.log" 2>&1
made=$(grep -aoE 'made\([^)]*\)' "$D/p1.log" | head -1 | sed 's/^made(//; s/)$//')
check "process one made an instance and counted to two" "$(grep -c 'made(' "$D/p1.log")" "1"
check "process two finds it in the store and continues the count" \
  "$("$C" --embed "$S" run "$D/counters.pl" "instance_of('$made', named_counter), '$made'::next(N), '$made'::label(L), write(answer(N-L)), nl" 2>&1 | answer)" \
  "3-kept: 3"

if [ "$failures" -eq 0 ]; then echo "GREEN: cicili"; else echo "RED: $failures failure(s)"; exit 1; fi
