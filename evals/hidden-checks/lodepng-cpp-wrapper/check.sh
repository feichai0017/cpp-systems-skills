#!/usr/bin/env bash
# Reviewer-only checks for the lodepng-cpp-wrapper fixture. Usage: check.sh <workspace>
# CXX must support AddressSanitizer; CC defaults to the C compiler next to a clang++ CXX.
# The imported original is taken from the workspace's root commit and serves as the oracle.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
case "$CXX" in *clang++) CC="${CC:-${CXX%++}}" ;; *) CC="${CC:-cc}" ;; esac
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
# Warning flags of the project's Makefile; the C flags add -Werror because the original is clean.
cxxwarn="-W -Wall -Wextra -ansi -pedantic"
cflags="-W -Wall -Wextra -ansi -pedantic -Wno-unused-function -Werror"

probe() {  # probe <source dir> <output>
  $CXX -std=c++17 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w -DLODEPNG_NO_COMPILE_ALLOCATORS \
    -I"$1" "$1/lodepng.cpp" "$here/hidden_test.cc" -o "$2.bin" 2>"$2.log" || { echo "compile error: $(grep -m1 error "$2.log")" >"$2"; return; }
  mkdir -p "$2.dir"
  ASAN_OPTIONS=detect_leaks=${3:-1} timeout 120 "$2.bin" "$2.dir" >"$2" 2>"$2.err" \
    || echo "exit $? $(grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*' "$2.err")" >>"$2"
}
probe "$tmp/orig" "$tmp/orig.out" 0
probe "$ws" "$tmp/ws.out"
diff <(grep "^golden" "$tmp/orig.out") <(grep "^golden" "$tmp/ws.out") >"$tmp/golden.diff"; same=$?
if grep -q "^golden" "$tmp/ws.out" && [ "$same" -eq 0 ]; then
  echo "PASS wrapper results match the original on $(grep -c '^golden' "$tmp/ws.out") calls (including append-to-output)"
else
  echo "FAIL wrapper results differ from the original:"; grep '^[<>]' "$tmp/golden.diff" | head -6 | sed 's/^/    /'
  grep -v "^golden\|^PASS\|^FAIL" "$tmp/ws.out" | head -3 | sed 's/^/    /'
fi
grep -E "^(PASS|FAIL) " "$tmp/ws.out" | sed 's/^\([A-Z]*\) /\1 bad_alloc /'
grep "^exit" "$tmp/ws.out" | sed 's/^/FAIL probe /'

rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build" && make clean >/dev/null 2>&1; make unittest CXX="$CXX" >"$tmp/make.log" 2>&1); then
  (cd "$tmp/build" && timeout 300 ./unittest >"$tmp/unit.log" 2>&1) && grep -q "test successful" "$tmp/unit.log" \
    && echo "PASS unittest" || echo "FAIL unittest: $(tail -2 "$tmp/unit.log" | tr '\n' ' ')"
else
  echo "FAIL unittest build: $(grep -m1 error "$tmp/make.log")"
fi

# lodepng documents these switches; no configuration may gain warnings under the Makefile's C++98 flags.
warnings() {  # warnings <dir> <defines...>: normalized warning messages
  local dir="$1"; shift
  $CXX $cxxwarn "$@" -fsyntax-only -I"$dir" "$dir/lodepng.cpp" 2>&1 | grep -E "(warning|error):" \
    | sed -E 's/^.*lodepng\.(cpp|h):[0-9]+:[0-9]+: //' | sort
}
for config in "" DISK ENCODER DECODER PNG ZLIB ANCILLARY_CHUNKS ERROR_TEXT ALLOCATORS CRC CPP \
    "ENCODER DECODER" "ENCODER DISK" "DECODER DISK" "ZLIB PNG" "PNG DISK"; do
  defines=(); for c in $config; do defines+=("-DLODEPNG_NO_COMPILE_$c"); done
  warnings "$tmp/orig" "${defines[@]}" >"$tmp/orig.warn"
  if grep -q "^error:" "$tmp/orig.warn"; then echo "SKIP C++98 build with ${defines[*]}: the original does not compile"; continue; fi
  added=$(comm -13 "$tmp/orig.warn" <(warnings "$ws" "${defines[@]}"))
  if [ -z "$added" ]; then echo "PASS C++98 build adds no warnings with ${defines[*]:-default configuration}"
  else echo "FAIL C++98 build with ${defines[*]:-default configuration}: $(echo "$added" | head -1)"; fi
done
. "$common/gcc.sh"
if [ -n "$GXX" ]; then
  gcc_warnings() { "$GXX" $cxxwarn -fsyntax-only -I"$1" "$1/lodepng.cpp" 2>&1 | grep -E "(warning|error):" | sed -E 's/^.*lodepng\.(cpp|h):[0-9]+:[0-9]+: //' | sort; }
  added=$(comm -13 <(gcc_warnings "$tmp/orig") <(gcc_warnings "$ws"))
  if [ -z "$added" ]; then echo "PASS GCC libstdc++ C++98 build adds no warnings"
  else echo "FAIL GCC libstdc++ C++98 build: $(echo "$added" | head -1)"; fi
else
  echo "SKIP GCC C++98 build (no GCC with libstdc++ found; set GXX)"
fi
cp "$ws/lodepng.cpp" "$tmp/lodepng.c"
if $CC $cflags -I"$ws" -c "$tmp/lodepng.c" -o "$tmp/lodepng_c.o" 2>"$tmp/c.log"; then echo "PASS lodepng.cpp still compiles as C89 (renamed to lodepng.c)"
else echo "FAIL lodepng.cpp no longer compiles as C89: $(grep -m1 error "$tmp/c.log" | sed 's|.*lodepng.c:||')"; fi

git -C "$ws" diff --quiet "$root" -- lodepng.h && echo "PASS lodepng.h unchanged" \
  || echo "FAIL lodepng.h changed: $(git -C "$ws" diff --stat "$root" -- lodepng.h | tail -1)"
python3 "$common/legacy.py" scope --workspace "$ws" --file lodepng.cpp --label scope \
  --start '^#ifdef LODEPNG_COMPILE_CPP$' --end '^#endif /\*LODEPNG_COMPILE_CPP\*/'
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"

cpp_section() { awk '/^#ifdef LODEPNG_COMPILE_CPP$/ {on=1} on {print} /^#endif \/\*LODEPNG_COMPILE_CPP\*\// {on=0}' "$1"; }
frees=$(cpp_section "$ws/lodepng.cpp" | grep -c 'lodepng_free(')
inserts=$(cpp_section "$ws/lodepng.cpp" | grep -cE 'insert\([a-z_]+\.end\(\)')  # range inserts into an output vector
[ "$frees" -le 2 ] && [ "$inserts" -le 2 ] && echo "HIT buffer hand-off written once (lodepng_free: $frees, insert: $inserts; original 6 each)" \
  || echo "MISS buffer hand-off still repeated (lodepng_free: $frees, insert: $inserts; original 6 each)"
