#!/usr/bin/env bash
# Reviewer-only checks for the inih-parse-string fixture. Usage: check.sh <workspace>
# CXX must support AddressSanitizer; CC defaults to the C compiler next to a clang++ CXX.
# The imported original is taken from the workspace's root commit.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
case "$CXX" in *clang++) CC="${CC:-${CXX%++}}" ;; *) CC="${CC:-cc}" ;; esac
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"
configs=("" "-DINI_ALLOW_MULTILINE=0" "-DINI_STOP_ON_FIRST_ERROR=1" "-DINI_USE_STACK=0" "-DINI_ALLOW_BOM=0" "-DINI_MAX_LINE=20")

# ini_parse_string must reproduce ini_parse_file under every documented option.
for config in "${configs[@]}"; do
  label="${config:-default options}"
  if $CC $san -w $config -I"$ws" "$ws/ini.c" "$here/hidden_test.c" -o "$tmp/probe" 2>"$tmp/probe.log"; then
    mkdir -p "$tmp/scratch"
    out=$(ASAN_OPTIONS=detect_leaks=1 timeout 60 "$tmp/probe" "$tmp/scratch" "$tmp/orig/tests" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL) " | sed "s|^\([A-Z]*\) |\1 [$label] |"
    echo "$out" | grep "^MISMATCH" | head -2 | sed 's/^/    /'
    echo "$out" | grep -q -E "AddressSanitizer|LeakSanitizer|runtime error" \
      && echo "FAIL [$label] probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*')"
    [ "$code" -le 1 ] || echo "FAIL [$label] probe exited $code"
  else
    echo "FAIL [$label] hidden test does not compile: $(grep -m1 error "$tmp/probe.log")"
  fi
done

# ini_parse and ini_parse_file keep the original results: the original unit test against the original baselines.
for spec in "multi:" "single:-DINI_ALLOW_MULTILINE=0" "stop_on_first_error:-DINI_STOP_ON_FIRST_ERROR=1"; do
  name="${spec%%:*}"; flags="${spec#*:}"
  if (cd "$tmp/orig/tests" && $CC -w $flags -I"$ws" "$ws/ini.c" unittest.c -o "$tmp/unittest" 2>"$tmp/unit.log" \
      && "$tmp/unittest" | diff --strip-trailing-cr - "baseline_$name.txt" >/dev/null); then
    echo "PASS original unit test still matches baseline_$name.txt"
  else
    echo "FAIL original unit test differs from baseline_$name.txt"
  fi
done

# The workspace's own tests, as AGENTS.md runs them.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build/tests" \
    && $CC -w -I.. ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_multi.txt >/dev/null \
    && $CC -w -I.. -DINI_ALLOW_MULTILINE=0 ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_single.txt >/dev/null \
    && $CC -w -I.. -DINI_STOP_ON_FIRST_ERROR=1 ../ini.c unittest.c -o unittest && ./unittest | diff --strip-trailing-cr - baseline_stop_on_first_error.txt >/dev/null \
    && cd ../cpp && $CC -w -I.. -c ../ini.c -o ini.o && $CXX -w -I.. INIReader.cpp INIReaderTest.cpp ini.o -o INIReaderTest && ./INIReaderTest >/dev/null) 2>"$tmp/own.log"; then
  echo "PASS project tests from AGENTS.md"
else
  echo "FAIL project tests from AGENTS.md: $(grep -m1 -i error "$tmp/own.log")"
fi
grep -rl "ini_parse_string" "$ws/tests" "$ws/cpp" --include='*.c' --include='*.cpp' 2>/dev/null | grep -q -v "INIReader.cpp" \
  && echo "PASS tests exercise ini_parse_string" || echo "FAIL no test exercises ini_parse_string"

# C++ wrapper: a string-based constructor must not capture the existing file-name forms.
$CC -w -I"$ws" -c "$ws/ini.c" -o "$tmp/ini.o" 2>/dev/null
if $CXX -w -I"$ws/cpp" -I"$ws" -DTEST_INI="\"$ws/examples/test.ini\"" "$here/reader_test.cpp" "$ws/cpp/INIReader.cpp" \
    "$tmp/ini.o" -o "$tmp/reader" 2>"$tmp/reader.log"; then
  "$tmp/reader" | grep -E "^(PASS|FAIL) "
else
  echo "FAIL INIReader does not build with the C object: $(grep -m1 error "$tmp/reader.log")"
fi
grep -q "ini_parse_string" "$ws/cpp/INIReader.cpp" && echo "PASS INIReader can parse a string through ini_parse_string" \
  || echo "FAIL INIReader does not use ini_parse_string"

# ini.c stays C: no new warnings under C99 -pedantic, plus the C89 dialect the file is written in.
. "$common/gcc.sh"
c_diag() { "$@" 2>&1 | grep -E "(warning|error):" | sed -E 's/^.*ini\.(c|h):[0-9]+:[0-9]+: //' | sort; }
for config in "${configs[@]}"; do
  label="${config:-default options}"
  added=$(comm -13 <(c_diag $CC -std=c99 -pedantic -Wall -Wextra $config -fsyntax-only "$tmp/orig/ini.c") \
                   <(c_diag $CC -std=c99 -pedantic -Wall -Wextra $config -fsyntax-only "$ws/ini.c"))
  [ -z "$added" ] && echo "PASS [$label] ini.c builds as C99 without new warnings" || echo "FAIL [$label] ini.c as C99: $(echo "$added" | head -1)"
  if $CC -std=c89 -pedantic -Wall -Wextra -Werror $config -fsyntax-only "$ws/ini.c" 2>"$tmp/c89.log"; then
    echo "HIT [$label] ini.c keeps the C89 dialect"
  else
    echo "MISS [$label] ini.c is no longer C89: $(grep -m1 -E 'error' "$tmp/c89.log" | sed -E 's/^.*ini\.c:[0-9]+:[0-9]+: //')"
  fi
done
printf '#include "ini.h"\nint h(void* u, const char* s, const char* n, const char* v) { (void)u; (void)s; (void)n; (void)v; return 1; }\nint main() { return ini_parse_string("a=1", h, 0); }\n' >"$tmp/cxx_caller.cpp"
$CXX -I"$ws" "$tmp/cxx_caller.cpp" "$tmp/ini.o" -o "$tmp/cxx_caller" 2>/dev/null && "$tmp/cxx_caller" \
  && echo "PASS ini_parse_string is callable from C++ (extern \"C\")" || echo "FAIL ini_parse_string is not callable from C++"
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  added=$(comm -13 <(c_diag "$compiler" -std=c++98 -pedantic -Wall -Wextra -I"$tmp/orig" -fsyntax-only "$tmp/orig/cpp/INIReader.cpp") \
                   <(c_diag "$compiler" -std=c++98 -pedantic -Wall -Wextra -I"$ws" -fsyntax-only "$ws/cpp/INIReader.cpp"))
  [ -z "$added" ] && echo "HIT [$name] INIReader.cpp stays C++98" || echo "MISS [$name] INIReader.cpp beyond C++98: $(echo "$added" | head -1)"
done

python3 - "$tmp/orig/ini.c" "$ws/ini.c" <<'EOF'
import re, sys
def body(text, name):
    m = re.search(r"^[^\n]*\b%s\([^)]*\)\s*\n\{.*?^\}" % re.escape(name), text, re.S | re.M)
    return m.group(0) if m else None
orig, cur = (open(p, encoding="latin-1").read() for p in sys.argv[1:3])
changed = [n for n in ("rstrip", "lskip", "find_char_or_comment", "strncpy0", "ini_parse") if body(orig, n) != body(cur, n)]
print("FAIL scope: ini.c changes unrelated functions: " + ", ".join(changed) if changed else "PASS scope: ini.c keeps unrelated functions unchanged")
EOF
python3 "$common/legacy.py" scope --workspace "$ws" --file ini.h --label scope --allow-insertions | sed 's/^FAIL/MISS/; s/^PASS/HIT/'
# inih targets embedded systems; a string must not be parsed through a file.
grep -n -E "\b(tmpfile|fmemopen|open_memstream|mkstemp|tmpnam)\b" "$ws/ini.c" >/dev/null \
  && echo "FAIL ini_parse_string goes through a temporary or memory-backed FILE" \
  || echo "PASS ini_parse_string reads the string directly"
loops=$(grep -c "find_char_or_comment(start, '=')" "$ws/ini.c")
[ "$loops" -le 1 ] && echo "HIT parse loop written once" || echo "MISS parse loop duplicated ($loops copies)"
awk '/ini_parse_string/ && prev ~ /\*\// {found=1} {if ($0 !~ /^[ \t]*$/) prev=$0} END {exit !found}' "$ws/ini.h" \
  && echo "HIT ini_parse_string documented like its neighbors" || echo "MISS ini_parse_string lacks a header comment"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"
