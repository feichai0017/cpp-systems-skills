#!/usr/bin/env bash
# Reviewer-only checks for the httplib-header-injection fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
# ServerTest listens on test.cc's fixed PORT 1234, so run one check at a time.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"

# Every client entry point that puts caller data into a header, observed on the wire.
if $CXX -std=c++11 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w -I"$ws" "$here/hidden_test.cc" \
    -pthread -o "$tmp/probe" 2>"$tmp/probe.log"; then
  out=$(timeout 120 "$tmp/probe" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
    && echo "FAIL probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^(]*')"
  [ "$code" -le 1 ] || echo "FAIL probe exited $code"
else
  echo "FAIL hidden test does not compile: $(grep -m1 'error:' "$tmp/probe.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# The offline suite from AGENTS.md still passes, and the project's tests cover the fix.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build/test" && $CXX -std=c++11 -I.. -I. test.cc include_httplib.cc gtest/gtest-all.cc gtest/gtest_main.cc \
    -pthread -o test && timeout 300 ./test --gtest_filter='ServerTest.*') >"$tmp/own.log" 2>&1; then
  echo "PASS ServerTest suite from AGENTS.md"
else
  echo "FAIL ServerTest suite from AGENTS.md: $(grep -m1 -E 'error:|FAILED' "$tmp/own.log" | cut -c1-160)"
fi
git -C "$ws" diff -U0 "$root" -- test/test.cc | grep -a '^+[^+]' | grep -q -E '\\r\\n|\\n|CRLF|crlf' \
  && echo "PASS test.cc covers header injection" || echo "FAIL test.cc does not test header injection"

# httplib supports C++11; compare diagnostics with the original under the test Makefile's flags.
. "$common/gcc.sh"
printf '#include "httplib.h"\nint main() { httplib::Client cli("localhost", 1); return cli.Get("/") ? 0 : 1; }\n' >"$tmp/use.cc"
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  "$@" -fsyntax-only -I"$dir" "$tmp/use.cc" 2>&1 | grep -E "(warning|error):" | sed -E 's/^.*httplib\.h:[0-9]+:[0-9]+: //' | sort
}
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  for flags in "-std=c++11 -Wall -Wextra -Wtype-limits -Wconversion -Wshadow" "-std=c++11 -fno-exceptions -DCPPHTTPLIB_NO_EXCEPTIONS -Wall -Wextra"; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$compiler" $flags) <(diagnostics "$ws" "$compiler" $flags))
    [ -z "$added" ] && echo "PASS [$name $flags] no new diagnostics" || echo "FAIL [$name $flags] new diagnostics: $(echo "$added" | head -1)"
  done
done

# The project already has detail::has_crlf and Request::set_header for this. Lines that only
# moved (removed and added unchanged, for example has_crlf placed before write_headers) are not new.
git -C "$ws" diff -U0 "$root" -- httplib.h | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- httplib.h | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
if echo "$new_code" | grep -q -E "== *'\\\\r'|== *'\\\\n'|find_first_of\(\"\\\\r\\\\n\"|find\('\\\\r'\)|find\('\\\\n'\)"; then
  echo "MISS CR/LF detection re-implemented instead of detail::has_crlf"
elif echo "$new_code" | grep -q -E 'has_crlf|set_header'; then echo "HIT reuses detail::has_crlf or set_header"
else echo "INFO no new CR/LF detection"; fi
api_changed=$(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -c -E '^\s*(Result|void|bool|inline Result|inline void|inline bool) [A-Za-z_:]+\(')
[ "$api_changed" -eq 0 ] && echo "HIT existing function signatures unchanged" || echo "MISS $api_changed existing function signatures changed"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(httplib\.h|test/test\.cc|README\.md)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in httplib.h, its test and README" || echo "MISS scope: also changes $extra"

# A fix at the serialization point covers every entry point without naming them, so the report is
# only recorded. Where the fix sits says how it reaches the entry points.
if [ -f "$message" ]; then
  named=$(for name in Put Patch Delete default bearer Headers; do grep -q -i "$name" "$message" && echo "$name"; done | tr '\n' ' ')
  echo "INFO report mentions: ${named:-none}"
fi
filtered_in=$(git -C "$ws" diff -U0 "$root" -- httplib.h | grep -a -E '^@@' | grep -o -E 'write_headers|write_request|send_with_content_provider|ClientImpl::[A-Za-z_]+' | sort -u | tr '\n' ' ')
echo "INFO hunks touch: ${filtered_in:-none}"
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
