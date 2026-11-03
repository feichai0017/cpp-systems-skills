#!/usr/bin/env bash
# Reviewer-only checks for the tinyxml2-strict-numbers fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the root commit.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"

if $CXX -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w -I"$ws" "$ws/tinyxml2.cpp" \
    "$here/hidden_test.cc" -o "$tmp/probe" 2>"$tmp/probe.log"; then
  out=$(ASAN_OPTIONS=detect_leaks=1 timeout 60 "$tmp/probe" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL|INFO) "
  echo "$out" | grep -q -E "AddressSanitizer|LeakSanitizer|runtime error" \
    && echo "FAIL probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*')"
  [ "$code" -eq 0 ] || [ "$code" -eq 1 ] || echo "FAIL probe exited $code"
else
  echo "FAIL hidden test does not compile: $(grep -m1 error "$tmp/probe.log")"
fi

rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build" && $CXX -o xmltest xmltest.cpp tinyxml2.cpp >"$tmp/build.log" 2>&1); then
  result=$(cd "$tmp/build" && timeout 120 ./xmltest 2>&1 | grep -E "^Pass [0-9]+, Fail [0-9]+")
  pass=$(echo "$result" | sed -E 's/Pass ([0-9]+).*/\1/'); fail=$(echo "$result" | sed -E 's/.*Fail ([0-9]+)/\1/')
  if [ -n "$result" ] && [ "$fail" = 0 ] && [ "$pass" -gt 128 ]; then echo "PASS xmltest adds passing tests: $result (was 128)"
  else echo "FAIL xmltest: ${result:-no summary} (was 128)"; fi
else
  echo "FAIL xmltest build: $(grep -m1 error "$tmp/build.log")"
fi
# Only the "2.0" contract test (its assertions and the iVal declaration it reads) may change.
contract_lines='double as int|int iVal, result;'
contract=$(git -C "$ws" diff -U0 "$root" -- xmltest.cpp | grep -a '^-[^-]' | grep -c -E "$contract_lines")
deleted=$(git -C "$ws" diff -U0 "$root" -- xmltest.cpp | grep -a '^-[^-]' | grep -v -c -E "$contract_lines")
[ "$deleted" -eq 0 ] && echo "PASS xmltest.cpp keeps its existing lines" \
  || echo "FAIL xmltest.cpp changes $deleted existing lines"
[ "$contract" -eq 0 ] || echo "INFO xmltest.cpp changes the \"double as int\" contract test ($contract lines)"
if [ "$contract" -ne 0 ] && [ -f "${2:-}" ]; then
  grep -q -E '(^|[^.0-9])2\.0([^.0-9]|$)' "$2" && echo "HIT report states the \"2.0\" contract change" \
    || echo "MISS report does not state the \"2.0\" contract change"
fi

# The readme: "It does not rely on exceptions, RTTI, or the STL." Code targets C++98.
diagnostics() {  # diagnostics <compiler and flags...> <dir>: normalized diagnostics for tinyxml2.cpp
  local dir="${*: -1}"; set -- "${@:1:$#-1}"
  "$@" -fsyntax-only -I"$dir" "$dir/tinyxml2.cpp" 2>&1 | grep -E "(warning|error):" \
    | sed -E 's/^.*tinyxml2\.(cpp|h):[0-9]+:[0-9]+: //' | sort
}
. "$common/gcc.sh"
specs=("$CXX -std=c++98 -pedantic-errors -Wall -Wextra" "$CXX -fno-exceptions -fno-rtti -Wall -Wextra")
[ -n "$GXX" ] && specs+=("$GXX -std=c++98 -pedantic-errors -Wall -Wextra")
for spec in "${specs[@]}"; do
  added=$(comm -13 <(diagnostics $spec "$tmp/orig") <(diagnostics $spec "$ws"))
  label="${spec#"$CXX" }"; [ -n "$GXX" ] && label="${label/#"$GXX"/GCC}"
  if [ -z "$added" ]; then echo "PASS no new diagnostics with $label"
  else echo "FAIL new diagnostics with $label: $(echo "$added" | head -1)"; fi
done
[ -n "$GXX" ] || echo "SKIP GCC C++98 build (no GCC with libstdc++ found; set GXX)"
python3 "$common/legacy.py" includes --cxx "$CXX" --original "$tmp/orig" --workspace "$ws" --label "no-STL build" tinyxml2.cpp

python3 "$common/legacy.py" scope --workspace "$ws" --file tinyxml2.cpp --label scope \
  --start '^bool XMLUtil::To(Int|Unsigned|Bool|Float|Double)\(' --allow-insertions
python3 "$common/legacy.py" scope --workspace "$ws" --file tinyxml2.h --label scope --allow-insertions
# The project already has XMLUtil::SkipWhiteSpace and XMLUtil::IsWhiteSpace for this.
new_code=$(git -C "$ws" diff -U0 "$root" -- tinyxml2.cpp | grep -a '^+[^+]')
if echo "$new_code" | grep -q -E '\bisspace[[:space:]]*\('; then echo "MISS whitespace handling re-implemented instead of XMLUtil::SkipWhiteSpace"
elif echo "$new_code" | grep -q -E 'SkipWhiteSpace|IsWhiteSpace[[:space:]]*\('; then echo "HIT whitespace handling reuses XMLUtil::SkipWhiteSpace"
else echo "INFO no new whitespace handling"; fi
python3 "$common/style.py" --workspace "$ws"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"
