#!/usr/bin/env bash
# Reviewer-only checks for the utf8proc-strwidth fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer; CC defaults to the C compiler next to a clang++ CXX.
# The imported original is taken from the workspace's root commit.
# No pipefail: pipelines end in grep -q, which closes the pipe on the first match.
set -u
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
case "$CXX" in *clang++) CC="${CC:-${CXX%++}}" ;; *) CC="${CC:-cc}" ;; esac
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"

# Behavior; utf8proc.c includes its data table, so it is the only source to build.
if $CC $san -std=c99 -w -I"$ws" "$ws/utf8proc.c" "$here/hidden_test.c" -o "$tmp/probe" 2>"$tmp/probe.log"; then
  out=$(timeout 120 "$tmp/probe" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
    && echo "FAIL strwidth probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*' | cut -c1-140)"
  [ "$code" -le 1 ] || echo "FAIL strwidth probe exited $code"
else
  echo "FAIL strwidth probe does not compile: $(grep -m1 'error:' "$tmp/probe.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# utf8proc is C99 and warning-free with clang and GCC.
. "$common/gcc.sh"
GCC_C="${GXX:+${GXX/g++/gcc}}"
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  "$@" -fsyntax-only -I"$dir" "$dir/utf8proc.c" 2>&1 | grep -E "utf8proc\.[ch]:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*(utf8proc\.[ch]):[0-9]+:[0-9]+: /\1: /' | sort -u
}
for compiler in "$CC" ${GCC_C:+"$GCC_C"}; do
  name="$(basename "$compiler")"
  for flags in "-std=c99 -pedantic -Wall -Wextra" "-std=c11 -pedantic -Wall -Wextra -Wconversion"; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$compiler" $flags) <(diagnostics "$ws" "$compiler" $flags))
    [ -z "$added" ] && echo "PASS [$name $flags] no new diagnostics" || echo "FAIL [$name $flags] new diagnostics: $(echo "$added" | head -1 | cut -c1-160)"
  done
done
[ -n "$GCC_C" ] || echo "SKIP GCC builds (no GCC found; set GXX)"

# The offline tests from AGENTS.md, plus any test the change adds to the Makefile.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
tests="test/charwidth test/misc test/valid test/iterate test/custom"
grep -q '^test/strwidth:' "$tmp/build/Makefile" && tests="$tests test/strwidth"
if (cd "$tmp/build" && make clean && make CC="$CC" $tests && for t in $tests; do ./$t || exit 1; done) >"$tmp/own.log" 2>&1; then
  echo "PASS offline tests from AGENTS.md"
else
  echo "FAIL offline tests from AGENTS.md: $(grep -m1 -E 'error|FAIL|failed' "$tmp/own.log" | cut -c1-160)"
fi
git -C "$ws" diff -U0 "$root" -- test >"$tmp/test.diff"; git -C "$ws" ls-files --others --exclude-standard -- test >"$tmp/test.new"
if grep -a '^+[^+]' "$tmp/test.diff" | grep -q 'utf8proc_strwidth' \
   || { [ -s "$tmp/test.new" ] && (cd "$ws" && grep -q 'utf8proc_strwidth' $(cat "$tmp/test.new")); }; then
  echo "PASS tests cover utf8proc_strwidth"
else
  echo "FAIL no test calls utf8proc_strwidth"
fi
grep -a -q '^-[^-]' "$tmp/test.diff" && echo "MISS existing tests change lines" || echo "HIT existing tests only gain cases"
grep -B8 -E 'utf8proc_strwidth\(' "$ws/utf8proc.h" | grep -q -E '^\s*/\*\*' \
  && echo "HIT utf8proc.h documents utf8proc_strwidth" || echo "MISS utf8proc.h does not document utf8proc_strwidth"

# Redundant checks, reuse and machinery. Lines that only moved are not new code.
git -C "$ws" diff -U0 "$root" -- utf8proc.c utf8proc.h | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- utf8proc.c utf8proc.h | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
comm -13 "$tmp/removed.txt" "$tmp/added.txt" | python3 "$here/shape.py"
removed=$(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -v -E '^\s*$|^\s*(\*|//|/\*)' | grep -c .)
[ "$removed" -eq 0 ] && echo "HIT library changes only add code" || echo "MISS library changes $removed existing lines"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(utf8proc\.[ch]|test/.*|Makefile|CMakeLists\.txt|NEWS\.md|README\.md|MANIFEST)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in utf8proc.c/h, tests, build files and docs" || echo "MISS scope: also changes $extra"
python3 "$common/style.py" --workspace "$ws" --strip-prefix 'utf8proc_'
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
