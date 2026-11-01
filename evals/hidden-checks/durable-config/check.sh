#!/usr/bin/env bash
# Reviewer-only checks for the durable-config fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
# No pipefail: pipelines end in grep -q, which closes the pipe on the first match.
set -u
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# check.cc and the hidden test use fixed names under the temporary directory; graders run in parallel.
mkdir "$tmp/tmpdir" && export TMPDIR="$tmp/tmpdir/"
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
. "$common/gcc.sh"

diff -q "$here/fs.hpp.orig" "$ws/fs.hpp" >/dev/null && echo "PASS FileSystem interface unchanged" || echo "FAIL FileSystem interface changed"
cmp -s "$tmp/orig/posix_fs.hpp" "$ws/posix_fs.hpp" && echo "HIT posix_fs.hpp unchanged" || echo "MISS posix_fs.hpp changed"

# Behavior: a recording FileSystem injects failures into SaveConfig, under ASan/UBSan.
if $CXX -std=c++20 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w -I"$ws" \
    "$here/hidden_test.cc" -o "$tmp/hidden" 2>"$tmp/hidden.log"; then
  out=$(timeout 60 "$tmp/hidden" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL|HIT|MISS) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
    && echo "FAIL hidden test: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*' | cut -c1-140)"
  [ "$code" -le 1 ] || echo "FAIL hidden test exited $code"
else
  echo "FAIL hidden test does not compile: $(grep -m1 'error:' "$tmp/hidden.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# The project's check as AGENTS.md runs it, with clang and GCC; and the original check with the new header.
project_check() {  # project_check <label> <dir> <compiler>
  rm -rf "$tmp/build"; cp -R "$2" "$tmp/build"; rm -f "$tmp/build/check"
  if (cd "$tmp/build" && "$3" -std=c++20 -Wall -Wextra -pedantic -Werror check.cc -o check && timeout 60 ./check) >"$tmp/own.log" 2>&1; then
    echo "PASS [$(basename "$3")] $1"
  else
    echo "FAIL [$(basename "$3")] $1: $(grep -m1 -E 'error|Assertion|failed' "$tmp/own.log" | cut -c1-160)"
  fi
}
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && cp "$ws/config_store.hpp" "$tmp/mixed/"
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  project_check "check.cc from AGENTS.md" "$ws" "$compiler"
  project_check "original check.cc passes with the new config_store.hpp" "$tmp/mixed" "$compiler"
done
[ -n "$GXX" ] || echo "SKIP GCC builds (no GCC found; set GXX)"

# Tests: failure paths go through a FileSystem fake in test code, not through hooks in the product.
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
tests=$(echo "$changed" | grep -E '\.(cc|cpp|h|hpp)$' | grep -v -E '^(config_store|fs|posix_fs)\.hpp$')
(cd "$ws" && for f in $tests; do git diff -U0 "$root" -- "$f" | grep -a '^+[^+]'; done) >"$tmp/tests.diff"
grep -a -q -E ':\s*public\s+(project::)?(fs::)?FileSystem\b' "$tmp/tests.diff" \
  && echo "HIT tests substitute a FileSystem fake" || echo "MISS no test substitutes a FileSystem fake"
errors=$(grep -a -o -E 'errc::[a-z_]+|\bE[A-Z]{2,}\b' "$tmp/tests.diff" | sort -u | tr '\n' ' ')
echo "INFO errors the tests inject: ${errors:--}"
git -C "$ws" diff -U0 "$root" -- check.cc | grep -a -q '^-[^-]' && echo "MISS check.cc changes existing lines" || echo "HIT check.cc only gains code"
# Which failure paths the workspace's own check.cc detects: it passes against the reference
# SaveConfig and fails against the mutant that ignores that failure.
rm -rf "$tmp/mutants"; cp -R "$ws" "$tmp/mutants"; rm -f "$tmp/mutants/check"
cp "$here/mutant_config_store.hpp" "$tmp/mutants/config_store.hpp"
detected=""
for n in 0 1 2 3 4; do
  # The braces also silence the shell's report of an aborted test binary.
  if { (cd "$tmp/mutants" && $CXX -std=c++20 -w -DMUTANT=$n check.cc -o "check-$n" && timeout 60 "./check-$n") >/dev/null 2>&1; } 2>/dev/null; then
    [ "$n" -eq 0 ] || continue
  else
    [ "$n" -eq 0 ] && { detected=" not measured (own tests fail against the reference SaveConfig)"; break; }
    detected="$detected $(echo "write file-sync rename directory-sync" | cut -d' ' -f"$n")"
  fi
done
echo "INFO own tests detect ignored failures:${detected:- none}"

# The comment on SaveConfig states the new guarantee.
git -C "$ws" diff -U0 "$root" -- config_store.hpp | grep -a -E '^\+\s*//' | grep -q -i -E 'atomic|rename|temporar|crash|durab|原子|临时|崩溃|掉电' \
  && echo "HIT SaveConfig comment states the guarantee" || echo "MISS SaveConfig comment unchanged"

python3 "$here/shape.py" "$ws"
extra=$(echo "$changed" | grep -v -E '^(config_store\.hpp|check\.cc|README\.md|AGENTS\.md|check|.*\.o|.*\.dSYM/.*)$' \
  | grep -v -i -E '(test|fake|mock|stub)[^/]*\.(cc|cpp|h|hpp)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in config_store.hpp and tests" || echo "MISS scope: also changes $extra"
[ -f "$message" ] && python3 "$here/report.py" "$message"
python3 "$common/style.py" --workspace "$ws" --tests '^check\.cc$|fake|mock|stub'
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
