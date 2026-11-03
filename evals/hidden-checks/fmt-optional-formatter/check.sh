#!/usr/bin/env bash
# Reviewer-only checks for the fmt-optional-formatter fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"

# One translation unit per family, in C++17 and C++20.
for family in basic specs strings nested wchar constraint; do
  for std in c++17 c++20; do
    bin="$tmp/$family-$std"
    if $CXX $san -std=$std -w -DFAMILY_$family -DFAMILY_NAME="$family" -I"$ws/include" "$here/hidden_test.cc" \
        -o "$bin" 2>"$bin.log"; then
      out=$(timeout 30 "$bin" 2>&1); code=$?
      echo "$out" | grep -E "^(PASS|FAIL|INFO) " | sed "s/^\([A-Z]*\) optional /\1 [$std] optional /; s/^INFO /INFO [$std] /"
      echo "$out" | grep -q -E "AddressSanitizer|runtime error" && echo "FAIL [$std] optional $family: sanitizer report"
      [ "$code" -le 1 ] || echo "FAIL [$std] optional $family: probe exited $code"
    else
      echo "FAIL [$std] optional $family: does not compile: $(grep -m1 'error:' "$bin.log" | sed -E 's/^.*error: //' | cut -c1-160)"
    fi
  done
done

# Formatters that already existed keep their output.
for side in orig ws; do
  dir="$tmp/orig"; [ "$side" = ws ] && dir="$ws"
  $CXX -std=c++17 -w -DFAMILY_golden -I"$dir/include" "$here/hidden_test.cc" -o "$tmp/golden-$side" 2>/dev/null \
    && "$tmp/golden-$side" >"$tmp/golden-$side.txt" 2>&1
done
if [ -s "$tmp/golden-orig.txt" ] && cmp -s "$tmp/golden-orig.txt" "$tmp/golden-ws.txt"; then
  echo "PASS variant, monostate and thread::id formatting unchanged"
else
  echo "FAIL existing formatters changed: $(diff "$tmp/golden-orig.txt" "$tmp/golden-ws.txt" 2>&1 | grep -m1 '^[<>]')"
fi
printf '#define FMT_HEADER_ONLY\n#include "fmt/std.h"\n#include "fmt/xchar.h"\n#include <variant>\nint main() { return fmt::format(L"{}", std::variant<int>(1)).empty(); }\n' >"$tmp/wvariant.cc"
$CXX -std=c++17 -w -I"$ws/include" "$tmp/wvariant.cc" -o "$tmp/wvariant" 2>/dev/null \
  && echo "INFO std::variant now formats with wchar_t (it does not compile in the original)"

# fmt supports C++11: std.h still compiles below C++17, and adds no diagnostics in any mode.
printf '#define FMT_HEADER_ONLY\n#include "fmt/std.h"\n#include <thread>\nint main() { return fmt::format("{}", std::this_thread::get_id()).empty(); }\n' >"$tmp/plain.cc"
. "$common/gcc.sh"
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  "$@" -fsyntax-only -I"$dir/include" "$tmp/plain.cc" 2>&1 | grep -E "(warning|error):" | sed -E 's/^.*\/(fmt\/[a-z-]+\.h):[0-9]+:[0-9]+: /\1: /' | sort
}
for std in c++11 c++14 c++17 c++20; do
  for compiler in "$CXX" ${GXX:+"$GXX"}; do
    name="$(basename "$compiler")"
    added=$(comm -13 <(diagnostics "$tmp/orig" "$compiler" -std=$std -Wall -Wextra -pedantic) \
                     <(diagnostics "$ws" "$compiler" -std=$std -Wall -Wextra -pedantic))
    [ -z "$added" ] && echo "PASS [$name $std] std.h adds no diagnostics" || echo "FAIL [$name $std] std.h: $(echo "$added" | head -1)"
  done
done
warn=$($CXX -std=c++17 -Wall -Wextra -pedantic -DFAMILY_nested -DFAMILY_NAME=nested -I"$ws/include" -fsyntax-only "$here/hidden_test.cc" 2>&1 \
  | grep -E "std\.h:[0-9]+:[0-9]+: warning" | head -1)
[ -z "$warn" ] && echo "PASS optional formatter instantiates without warnings" || echo "FAIL optional formatter warns: $warn"

# The project's own test, as AGENTS.md builds it.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"; rm -rf "$tmp/build/build"
if (cd "$tmp/build" && cmake -S . -B build -DFMT_TEST=ON -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_COMPILER="$CXX" \
    && cmake --build build --target std-test -j8 && ./build/bin/std-test) >"$tmp/own.log" 2>&1; then
  echo "PASS std-test from AGENTS.md"
else
  echo "FAIL std-test from AGENTS.md: $(grep -m1 -E 'error|FAILED' "$tmp/own.log" | cut -c1-160)"
fi
git -C "$ws" diff -U0 "$root" -- test/std-test.cc | grep -a '^+[^+]' | grep -q "optional" \
  && echo "PASS std-test.cc covers std::optional" || echo "FAIL std-test.cc does not test std::optional"

# Quoting reuses fmt's debug format (ranges.h) or the escaping helpers that std::variant uses.
new_code=$(git -C "$ws" diff -U0 "$root" -- include/fmt/std.h | grep -a '^+[^+]')
echo "$new_code" | grep -q -E 'set_debug_format|write_variant_alternative|write_escaped_(string|char)' \
  && echo "HIT quoting reuses fmt's debug format or escaping helpers" || echo "MISS quoting re-implemented"
git -C "$ws" diff --quiet "$root" -- doc && echo "MISS doc/api.rst does not list std::optional" \
  || echo "HIT documentation updated"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(include/fmt/std\.h|test/std-test\.cc|doc/|ChangeLog)' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in std.h, its test and documentation" || echo "MISS scope: also changes $extra"

if [ -f "$message" ]; then
  grep -q -E 'wchar|C\+\+11|C\+\+14' "$message" && echo "HIT report states character types or C++11 coverage" \
    || echo "MISS report does not mention wchar_t or C++11"
fi
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
