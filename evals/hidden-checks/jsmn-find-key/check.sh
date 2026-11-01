#!/usr/bin/env bash
# Reviewer-only checks for the jsmn-find-key fixture. Usage: check.sh <workspace> [final message]
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
configs=("default:" "strict:-DJSMN_STRICT" "links:-DJSMN_PARENT_LINKS" "strict-links:-DJSMN_STRICT -DJSMN_PARENT_LINKS")

# Behavior in every configuration, with token arrays of exactly count entries, as C and as C++.
probe() {  # probe <label> <compiler and flags...>
  local label="$1"; shift
  if "$@" $san -w -I"$ws" "$here/hidden_test.c" -o "$tmp/probe" 2>"$tmp/probe.log"; then
    out=$(timeout 30 "$tmp/probe" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL) " | sed "s/^\([A-Z]*\) find/\1 [$label] find/"
    echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
      && echo "FAIL [$label] find: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*')"
    [ "$code" -le 1 ] || echo "FAIL [$label] find: probe exited $code"
  else
    echo "FAIL [$label] find: does not compile: $(grep -m1 'error:' "$tmp/probe.log" | sed -E 's/^.*error: //' | cut -c1-160)"
  fi
}
for config in "${configs[@]}"; do probe "${config%%:*}" $CC -std=c99 ${config#*:}; done
probe "c++" $CXX -x c++ -std=c++11

# The header's build modes: declarations only (JSMN_HEADER) with the implementation in another
# translation unit, and everything static (JSMN_STATIC).
printf '#define JSMN_HEADER\n#include "jsmn.h"\n#include <string.h>\nint main(void) {\n  const char *js = "{\\"a\\":1}";\n  jsmntok_t t[3];\n  jsmn_parser p;\n  jsmn_init(&p);\n  return jsmn_find(js, t, jsmn_parse(&p, js, strlen(js), t, 3), 0, "a") == 2 ? 0 : 1;\n}\n' >"$tmp/use.c"
printf '#include "jsmn.h"\n' >"$tmp/impl.c"
if $CC -std=c89 -w -I"$ws" "$tmp/use.c" "$tmp/impl.c" -o "$tmp/split" 2>"$tmp/split.log" && "$tmp/split"; then
  echo "PASS JSMN_HEADER declaration links with the implementation"
else
  echo "FAIL JSMN_HEADER build: $(grep -m1 -E 'error' "$tmp/split.log" | cut -c1-160)"
fi
sed 's/#define JSMN_HEADER/#define JSMN_STATIC/' "$tmp/use.c" >"$tmp/static.c"
if $CC -std=c89 -w -I"$ws" "$tmp/static.c" -o "$tmp/static" 2>"$tmp/static.log" && "$tmp/static"; then
  echo "PASS JSMN_STATIC build"
else
  echo "FAIL JSMN_STATIC build: $(grep -m1 -E 'error' "$tmp/static.log" | cut -c1-160)"
fi

# jsmn is C89 and is included from C++: nothing new for existing users, and the new code itself
# compiles cleanly, with clang and GCC.
printf '#include "jsmn.h"\n#include <string.h>\nint main(void) {\n  jsmntok_t t[4];\n  jsmn_parser p;\n  jsmn_init(&p);\n  return jsmn_parse(&p, "{}", 2, t, 4);\n}\n' >"$tmp/plain.c"
. "$common/gcc.sh"
GCC_C="${GXX:+${GXX/g++/gcc}}"
diagnostics() {  # diagnostics <dir> <source> <compiler and flags...>
  local dir="$1" src="$2"; shift 2
  "$@" -fsyntax-only -I"$dir" "$src" 2>&1 | grep -E "jsmn\.h:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*jsmn\.h:[0-9]+:[0-9]+: //' | sort -u
}
specs=("$CC -std=c89 -pedantic -Wall -Wextra -Wdeclaration-after-statement" "$CC -std=c99 -pedantic -Wall -Wextra -Wconversion"
       "$CXX -x c++ -std=c++11 -pedantic -Wall -Wextra")
[ -n "$GCC_C" ] && specs+=("$GCC_C -std=c89 -pedantic -Wall -Wextra -Wdeclaration-after-statement")
[ -n "$GXX" ] && specs+=("$GXX -x c++ -std=c++11 -pedantic -Wall -Wextra")
for spec in "${specs[@]}"; do
  label=$(echo "$spec" | sed -E 's|^[^ ]*/||')
  added=$(comm -13 <(diagnostics "$tmp/orig" "$tmp/plain.c" $spec) <(diagnostics "$ws" "$tmp/plain.c" $spec))
  [ -z "$added" ] && echo "PASS [$label] header adds no diagnostics" || echo "FAIL [$label] header: $(echo "$added" | head -1)"
  if $spec -fsyntax-only -UJSMN_HEADER -I"$ws" "$tmp/use.c" >/dev/null 2>&1; then
    found=$(diagnostics "$ws" "$tmp/use.c" $spec -UJSMN_HEADER | grep -v "unused")
    [ -z "$found" ] && echo "PASS [$label] jsmn_find compiles without warnings" || echo "FAIL [$label] jsmn_find: $(echo "$found" | head -1)"
  else
    echo "FAIL [$label] jsmn_find does not compile: $($spec -fsyntax-only -UJSMN_HEADER -I"$ws" "$tmp/use.c" 2>&1 | grep -m1 'error:' | cut -c1-140)"
  fi
done
[ -n "$GCC_C" ] || echo "SKIP GCC builds (no GCC found; set GXX)"

# The project's tests from AGENTS.md in all four configurations, and the original tests.
if (cd "$ws" && make test CC="$CC") >"$tmp/own.log" 2>&1; then
  echo "PASS make test from AGENTS.md"
else
  echo "FAIL make test from AGENTS.md: $(grep -m1 -E 'FAILED|error' "$tmp/own.log" | cut -c1-160)"
fi
rm -f "$ws"/test/test_default "$ws"/test/test_strict "$ws"/test/test_links "$ws"/test/test_strict_links
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && cp "$ws/jsmn.h" "$tmp/mixed/"
(cd "$tmp/mixed" && make test CC="$CC") >"$tmp/mixed.log" 2>&1 \
  && echo "PASS original tests pass with the new header" \
  || echo "FAIL original tests with the new header: $(grep -m1 -E 'FAILED|error' "$tmp/mixed.log" | cut -c1-160)"
git -C "$ws" diff -U0 "$root" -- test >"$tmp/test.diff"
grep -a '^+[^+]' "$tmp/test.diff" | grep -q 'jsmn_find' && echo "PASS tests cover jsmn_find" || echo "FAIL no test calls jsmn_find"
grep -a -q '^-[^-]' "$tmp/test.diff" && echo "MISS existing tests change lines" || echo "HIT existing tests only gain cases"

# Redundant checks, machinery and size. Lines that only moved are not new code.
git -C "$ws" diff -U0 "$root" -- jsmn.h | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- jsmn.h | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
echo "$new_code" | python3 "$here/shape.py"
removed=$(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -v -E '^\s*$|^\s*(\*|//|/\*)' | grep -c .)
[ "$removed" -eq 0 ] && echo "HIT header changes only add code" || echo "MISS header changes $removed existing lines"

changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(jsmn\.h|test/.*|README\.md|example/.*|(cmake-)?build[^/]*/.*)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in jsmn.h, tests, examples and README" || echo "MISS scope: also changes $extra"
git -C "$ws" diff -U0 "$root" -- README.md | grep -a '^+[^+]' | grep -q 'jsmn_find' \
  && echo "HIT README documents jsmn_find" || echo "MISS README does not document jsmn_find"
python3 "$common/style.py" --workspace "$ws" --strip-prefix 'jsmn_'
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
