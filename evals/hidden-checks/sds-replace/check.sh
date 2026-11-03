#!/usr/bin/env bash
# Reviewer-only checks for the sds-replace fixture. Usage: check.sh <workspace> [final message]
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

# Behavior with a counting allocator: sds.c includes "sdsalloc.h" from its own directory, so the
# probe builds copies of sds.c and sds.h next to the reviewer's allocator.
mkdir "$tmp/probe" && cp "$ws/sds.c" "$ws/sds.h" "$here/sdsalloc.h" "$tmp/probe/"
if $CC $san -std=c99 -w -I"$tmp/probe" "$tmp/probe/sds.c" "$here/hidden_test.c" -o "$tmp/probe/run" 2>"$tmp/probe.log"; then
  out=$(timeout 120 "$tmp/probe/run" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL|HIT|MISS) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error|Assertion failed" \
    && echo "FAIL replace probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*\|Assertion failed.*' | cut -c1-140)"
  [ "$code" -le 1 ] || echo "FAIL replace probe exited $code"
else
  echo "FAIL replace probe does not compile: $(grep -m1 'error:' "$tmp/probe.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# sds is C99: no new diagnostics in sds.c with clang and GCC, with or without the tests.
. "$common/gcc.sh"
GCC_C="${GXX:+${GXX/g++/gcc}}"
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  "$@" -fsyntax-only -I"$dir" "$dir/sds.c" 2>&1 | grep -E "sds\.[ch]:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*(sds\.[ch]):[0-9]+:[0-9]+: /\1: /' | sort -u
}
for compiler in "$CC" ${GCC_C:+"$GCC_C"}; do
  name="$(basename "$compiler")"
  for flags in "-std=c99 -pedantic -Wall -Wextra" "-std=c99 -pedantic -Wall -Wextra -DSDS_TEST_MAIN"; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$compiler" $flags) <(diagnostics "$ws" "$compiler" $flags))
    [ -z "$added" ] && echo "PASS [$name $flags] no new diagnostics" || echo "FAIL [$name $flags] new diagnostics: $(echo "$added" | head -1 | cut -c1-160)"
  done
done
[ -n "$GCC_C" ] || echo "SKIP GCC builds (no GCC found; set GXX)"

# The project's tests as AGENTS.md runs them; they live in sds.c under SDS_TEST_MAIN.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"; rm -f "$tmp/build/sds-test"
if (cd "$tmp/build" && make CC="$CC" && timeout 60 ./sds-test) >"$tmp/own.log" 2>&1; then
  echo "PASS sds-test from AGENTS.md"
else
  echo "FAIL sds-test from AGENTS.md: $(grep -m1 -E 'FAILED|error|WARNING' "$tmp/own.log" | cut -c1-160)"
fi
git -C "$ws" diff -U0 "$root" -- sds.c >"$tmp/sds.diff"
grep -a -E '^\+.*test_cond\(' "$tmp/sds.diff" | grep -q -i 'replace' \
  && echo "PASS tests cover sdsreplace" || echo "FAIL no test_cond covers sdsreplace"
removed=$(grep -a '^-[^-]' "$tmp/sds.diff" | cut -c2- | grep -v -E '^\s*$|^\s*(\*|//|/\*)' | grep -c .)
[ "$removed" -eq 0 ] && echo "HIT sds.c changes only add code" || echo "MISS sds.c changes $removed existing lines"
grep -q -E '^sds sdsreplace\(' "$ws/sds.h" && echo "PASS sds.h declares sdsreplace" || echo "FAIL sds.h does not declare sdsreplace"

# Redundant checks, reuse and machinery.
python3 "$here/shape.py" "$ws"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(sds\.[ch]|README\.md|Changelog)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in sds.c, sds.h, README and Changelog" || echo "MISS scope: also changes $extra"
git -C "$ws" diff -U0 "$root" -- README.md | grep -a '^+[^+]' | grep -q 'sdsreplace' \
  && echo "HIT README documents sdsreplace" || echo "MISS README does not document sdsreplace"
[ -f "$message" ] && python3 "$here/report.py" "$message"
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
