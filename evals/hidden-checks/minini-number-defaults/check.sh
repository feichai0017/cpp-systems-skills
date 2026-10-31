#!/usr/bin/env bash
# Reviewer-only checks for the minini-number-defaults fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer; CC defaults to the C compiler next to a clang++ CXX.
# The imported original is taken from the workspace's root commit.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
case "$CXX" in *clang++) CC="${CC:-${CXX%++}}" ;; *) CC="${CC:-cc}" ;; esac
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"
added_lines() { git -C "$ws" diff -U0 "$root" -- "$@" | grep -a '^+[^+]'; }

# ini_getl and ini_getf: whole-value conversion in range, DefValue otherwise. One process per family,
# so undefined behavior in one getter does not hide the other.
if $CC $san -w -I"$ws/dev" "$ws/dev/minIni.c" "$here/hidden_test.c" -o "$tmp/probe" 2>"$tmp/probe.log"; then
  for family in getl getf; do
    mkdir -p "$tmp/$family"
    out=$(ASAN_OPTIONS=detect_leaks=1 timeout 60 "$tmp/probe" "$family" "$tmp/$family" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL|INFO) "
    echo "$out" | grep -q -E "AddressSanitizer|LeakSanitizer|runtime error" \
      && echo "FAIL $family conversion: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^(]*')"
    [ "$code" -le 1 ] || echo "FAIL $family probe exited $code"
  done
else
  echo "FAIL hidden test does not compile: $(grep -m1 error "$tmp/probe.log")"
fi

# The C++ class shares the contract; geti narrows to int.
if $CC $san -w -I"$ws/dev" -c "$ws/dev/minIni.c" -o "$tmp/minIni.o" 2>/dev/null \
    && $CXX $san -std=c++98 -w -I"$ws/dev" "$here/hidden_wrapper.cpp" "$tmp/minIni.o" -o "$tmp/wrapper" 2>"$tmp/wrapper.log"; then
  mkdir -p "$tmp/wrapper-dir"
  out=$(ASAN_OPTIONS=detect_leaks=1 timeout 60 "$tmp/wrapper" "$tmp/wrapper-dir" 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL) "
  echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
    && echo "FAIL wrapper probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^(]*')"
  [ "$code" -le 1 ] || echo "FAIL wrapper probe exited $code"
else
  echo "FAIL C++ wrapper probe does not build: $(grep -m1 error "$tmp/wrapper.log")"
fi

# ini_getbool (documented first-character rule), ini_gets, enumeration, browse and the writers are unchanged.
mkdir "$tmp/golden-orig" "$tmp/golden-ws"
if $CC -w -I"$tmp/orig/dev" "$tmp/orig/dev/minIni.c" "$here/hidden_test.c" -o "$tmp/golden-orig.bin" \
    && $CC -w -I"$ws/dev" "$ws/dev/minIni.c" "$here/hidden_test.c" -o "$tmp/golden-ws.bin" 2>/dev/null; then
  "$tmp/golden-orig.bin" golden "$tmp/golden-orig" >"$tmp/golden-orig.txt" 2>&1
  "$tmp/golden-ws.bin" golden "$tmp/golden-ws" >"$tmp/golden-ws.txt" 2>&1
  first=$(diff "$tmp/golden-orig.txt" "$tmp/golden-ws.txt" | grep -m1 '^[<>]')
  if ! grep -q '^getbool k0=' "$tmp/golden-orig.txt"; then echo "FAIL golden comparison produced no output"
  elif [ -z "$first" ]; then echo "PASS ini_getbool, ini_gets, enumeration and writers unchanged"
  else echo "FAIL APIs outside the fix changed: $first"; fi
else
  echo "FAIL golden comparison could not be built"
fi

# The workspace's own tests, as AGENTS.md runs them.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build/dev" && cc -o test test.c minIni.c && ./test \
    && cc -c minIni.c -o minIni.o && c++ -o test2 test2.cc minIni.o && ./test2) >"$tmp/own.log" 2>&1; then
  echo "PASS project tests from AGENTS.md"
else
  echo "FAIL project tests from AGENTS.md: $(grep -m1 -i -E 'error|assert' "$tmp/own.log")"
fi
tests=$( { added_lines dev/test.c dev/test2.cc; (cd "$ws" && git ls-files --others --exclude-standard -- dev | grep -E '\.(c|cc|cpp)$' | xargs cat 2>/dev/null); } \
  | grep -c -E 'getl|getf|geti')
[ "$tests" -gt 0 ] && echo "PASS tests exercise the numeric getters" || echo "FAIL no test exercises the numeric getters"

# minIni targets embedded C compilers: no new diagnostics in C89 under its configuration macros,
# none when the glue has no INI_REAL, and the header's C++ class stays C++98.
. "$common/gcc.sh"
c_diag() { "$@" 2>&1 | grep -E "(warning|error):" | sed -E 's/^.*(minIni|minGlue)\.(c|h):[0-9]+:[0-9]+: //' | sort; }
for config in "" "-DINI_READONLY" "-DNDEBUG -DINI_NOBROWSE -DPORTABLE_STRNICMP" "-DINI_ANSIONLY"; do
  label="${config:-default options}"
  added=$(comm -13 <(c_diag $CC -std=c89 -pedantic -Wall -Wextra $config -fsyntax-only "$tmp/orig/dev/minIni.c") \
                   <(c_diag $CC -std=c89 -pedantic -Wall -Wextra $config -fsyntax-only "$ws/dev/minIni.c"))
  [ -z "$added" ] && echo "PASS [$label] minIni.c adds no C89 diagnostics" || echo "FAIL [$label] minIni.c in C89: $(echo "$added" | head -1)"
done
for side in orig ws; do
  dir="$tmp/orig/dev"; [ "$side" = ws ] && dir="$ws/dev"
  mkdir -p "$tmp/noreal-$side"; cp "$dir"/*.h "$dir/minIni.c" "$tmp/noreal-$side/"
  grep -v -E 'INI_REAL|ini_ftoa|ini_atof' "$dir/minGlue.h" >"$tmp/noreal-$side/minGlue.h"
done
added=$(comm -13 <(c_diag $CC -std=c89 -pedantic -Wall -Wextra -fsyntax-only "$tmp/noreal-orig/minIni.c") \
                 <(c_diag $CC -std=c89 -pedantic -Wall -Wextra -fsyntax-only "$tmp/noreal-ws/minIni.c"))
[ -z "$added" ] && echo "PASS [glue without INI_REAL] minIni.c adds no diagnostics" \
  || echo "FAIL [glue without INI_REAL] minIni.c: $(echo "$added" | head -1)"
printf '#include "minIni.h"\nint main() { minIni ini("x.ini"); return ini.geti("s", "k"); }\n' >"$tmp/class.cpp"
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  added=$(comm -13 <(c_diag "$compiler" -std=c++98 -pedantic -Wall -Wextra -I"$tmp/orig/dev" -fsyntax-only "$tmp/class.cpp") \
                   <(c_diag "$compiler" -std=c++98 -pedantic -Wall -Wextra -I"$ws/dev" -fsyntax-only "$tmp/class.cpp"))
  [ -z "$added" ] && echo "PASS [$name] minIni.h class stays C++98" || echo "FAIL [$name] minIni.h beyond C++98: $(echo "$added" | head -1)"
done
added=$(comm -13 <(c_diag "$CXX" -x c++ -std=c++98 -Wall -Wextra -fsyntax-only "$tmp/orig/dev/minIni.c") \
                 <(c_diag "$CXX" -x c++ -std=c++98 -Wall -Wextra -fsyntax-only "$ws/dev/minIni.c"))
[ -z "$added" ] && echo "PASS minIni.c still compiles as C++ without new diagnostics" \
  || echo "FAIL minIni.c as C++: $(echo "$added" | head -1)"

# README: "minIni uses limited stack space and does not use dynamic memory (malloc and friends) at all."
added_lines dev/minIni.c | grep -q -E '\b(malloc|calloc|realloc|free)[[:space:]]*\(' \
  && echo "FAIL minIni.c now uses dynamic memory" || echo "PASS minIni.c still avoids dynamic memory"
# TCHAR builds map string functions through the _t* names; char-only calls break them.
direct=$(added_lines dev/minIni.c | grep -v -E '^\+[[:space:]]*#[[:space:]]*define' \
  | grep -o -E '\b(strtol|strtoul|strtod|strtof|isspace|isdigit|isxdigit|isalpha|strlen|strchr|toupper|tolower)[[:space:]]*\(' | sort -u | tr -d '( ' | tr '\n' ' ')
[ -z "$direct" ] && echo "HIT new code uses the TCHAR mappings" || echo "MISS new code calls char-only functions: $direct"
python3 - "$ws/dev/minIni.c" <<'EOF'
import re, sys
text = open(sys.argv[1], encoding="latin-1").read()
m = re.search(r"^INI_REAL ini_getf\(.*?^\}", text, re.S | re.M)
print("HIT ini_getf converts through the glue's ini_atof" if m and "ini_atof" in m.group(0)
      else "MISS ini_getf bypasses the glue's ini_atof")
EOF
git -C "$ws" diff --quiet "$root" -- dev/wxMinIni.h && echo "MISS wxMinIni::geti left unchanged" \
  || echo "HIT wxMinIni.h updated alongside minIni.h"

python3 "$common/legacy.py" scope --workspace "$ws" --file dev/minIni.c --label scope --allow-insertions \
  --start '^(/\*\* ini_get[lf]\(\)|#if !defined __T \|\| defined INI_ANSIONLY)' --end '^(\}|#endif)' | sed 's/^FAIL/MISS/; s/^PASS/HIT/'
python3 "$common/legacy.py" scope --workspace "$ws" --file dev/minIni.h --label scope --allow-insertions \
  --start '^\s+(long getl|int geti|INI_REAL getf)\(' --end '\}\s*$' | sed 's/^FAIL/MISS/; s/^PASS/HIT/'

if [ -f "$message" ]; then
  missing=$(for name in getf geti; do grep -q "$name" "$message" || echo "$name"; done | tr '\n' ' ')
  [ -z "$missing" ] && echo "HIT report names the sibling getters" || echo "MISS report does not mention: $missing"
  grep -q -i -E 'minIni\.pdf|manual|手册|文档' "$message" && echo "HIT report notes the documented DefValue contract" \
    || echo "MISS report does not mention the manual's DefValue description"
fi
# minIni.c already has skipleading and skiptrailing for this.
new_code=$(added_lines dev/minIni.c)
if echo "$new_code" | grep -q -E "\\b(isspace|_istspace|iswspace)[[:space:]]*\\(|== *' '"; then echo "MISS whitespace handling re-implemented instead of skipleading/skiptrailing"
elif echo "$new_code" | grep -q -E 'skipleading|skiptrailing'; then echo "HIT whitespace handling reuses skipleading/skiptrailing"
else echo "INFO no new whitespace handling"; fi
python3 "$common/style.py" --workspace "$ws" --strip-prefix 'ini_'
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"
