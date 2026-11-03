#!/usr/bin/env bash
# Reviewer-only checks for the dconv-hex-output fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
# No pipefail: pipelines end in grep -q, which closes the pipe on the first match.
set -u
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"

# Behavior, linking the workspace's sources built with the same sanitizers.
if $CXX $san -std=c++11 -w -I"$ws" "$ws"/double-conversion/*.cc "$here/hidden_test.cc" -o "$tmp/probe" 2>"$tmp/probe.log"; then
  out=$(timeout 60 "$tmp/probe" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error|Assertion failed" \
    && echo "FAIL hex probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*\|Assertion failed.*' | cut -c1-140)"
  [ "$code" -le 1 ] || echo "FAIL hex probe exited $code"
else
  echo "FAIL hex probe does not compile: $(grep -m1 'error:' "$tmp/probe.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# The library is C++98 and warning-free with GCC and Clang: no new diagnostics in its sources.
. "$common/gcc.sh"
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  for src in "$dir"/double-conversion/*.cc; do "$@" -fsyntax-only -I"$dir" "$src" 2>&1; done \
    | grep -E "double-conversion/[a-z-]+\.(h|cc):[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*(double-conversion\/[a-z-]+\.(h|cc)):[0-9]+:[0-9]+: /\1: /' | sort -u
}
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  for flags in "-std=c++98 -pedantic -Wall -Wextra" "-std=c++11 -pedantic -Wall -Wextra -Wshadow -Wconversion"; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$compiler" $flags) <(diagnostics "$ws" "$compiler" $flags))
    [ -z "$added" ] && echo "PASS [$name $flags] no new diagnostics" || echo "FAIL [$name $flags] new diagnostics: $(echo "$added" | head -1 | cut -c1-160)"
  done
done
[ -n "$GXX" ] || echo "SKIP GCC builds (no GCC found; set GXX)"

# The project's tests as AGENTS.md runs them, and the original tests with the new sources.
project_test() {  # project_test <label> <source dir>
  local label="$1" src="$2"
  rm -rf "$tmp/build"; cp -R "$src" "$tmp/build"; rm -rf "$tmp/build/cmake-build"
  if (cd "$tmp/build" && cmake -S . -B cmake-build -DBUILD_TESTING=ON -DCMAKE_CXX_COMPILER="$CXX" \
      && cmake --build cmake-build -j8 && ctest --test-dir cmake-build --output-on-failure) >"$tmp/own.log" 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label: $(grep -m1 -E 'error:|Failed|FAILED|failed' "$tmp/own.log" | cut -c1-160)"
  fi
}
project_test "ctest from AGENTS.md" "$ws"
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && cp "$ws"/double-conversion/* "$tmp/mixed/double-conversion/"
project_test "original tests pass with the new sources" "$tmp/mixed"
git -C "$ws" diff -U0 "$root" -- test >"$tmp/test.diff"
grep -a '^+[^+]' "$tmp/test.diff" | grep -q 'ToHexadecimal' && echo "PASS tests cover ToHexadecimal" || echo "FAIL no test calls ToHexadecimal"
grep -a -q '^-[^-]' "$tmp/test.diff" && echo "MISS existing tests change lines" || echo "HIT existing tests only gain cases"

# The header documents every public method; the new one too.
grep -B3 -E '\bbool ToHexadecimal\(' "$ws/double-conversion/double-to-string.h" | grep -q -E '^\s*//' \
  && echo "HIT header documents ToHexadecimal" || echo "MISS header does not document ToHexadecimal"

# Redundant checks, reuse, machinery and size. Lines that only moved are not new code.
git -C "$ws" diff -U0 "$root" -- double-conversion | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- double-conversion | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
echo "$new_code" | python3 "$here/shape.py"
removed=$(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -v -E '^\s*$|^\s*(\*|//|/\*)' | grep -c .)
[ "$removed" -eq 0 ] && echo "HIT library changes only add code" || echo "MISS library changes $removed existing lines"

changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(double-conversion/double-to-string\.(h|cc)|test/cctest/.*|Changelog|README\.md|(cmake-)?build[^/]*/.*)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in double-to-string, its tests, Changelog and README" || echo "MISS scope: also changes $extra"
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
