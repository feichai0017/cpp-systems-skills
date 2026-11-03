#!/usr/bin/env bash
# Reviewer-only checks for the stb-write-errors fixture. Usage: check.sh <workspace> [final message]
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

# Every file entry point under injected fopen, write and fclose failures.
# The original JPEG encoder left-shifts negative ints (stbiw__jpg_writeBits); that is not part of this task.
if $CC -g -O1 -fsanitize=address,undefined -fno-sanitize=shift -fno-sanitize-recover=all -w -I"$ws" "$here/hidden_test.c" -lm \
    -o "$tmp/probe" 2>"$tmp/probe.log"; then
  out=$(ASAN_OPTIONS=detect_leaks=1 timeout 120 "$tmp/probe" faults 2>&1); code=$?
  echo "$out" | grep -E "^(PASS|FAIL) "
  echo "$out" | grep -q -E "AddressSanitizer|LeakSanitizer|runtime error" \
    && echo "FAIL probe: $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*')"
  [ "$code" -le 1 ] || echo "FAIL probe exited $code"
else
  echo "FAIL hidden test does not compile: $(grep -m1 error "$tmp/probe.log")"
fi

# Successful writes keep producing the original bytes, for files and callbacks alike.
mkdir "$tmp/dump-orig" "$tmp/dump-ws"
if $CC -O1 -w -I"$tmp/orig" "$here/hidden_test.c" -lm -o "$tmp/dump-orig.bin" \
    && $CC -O1 -w -I"$ws" "$here/hidden_test.c" -lm -o "$tmp/dump-ws.bin" 2>/dev/null \
    && "$tmp/dump-orig.bin" dump "$tmp/dump-orig" && "$tmp/dump-ws.bin" dump "$tmp/dump-ws"; then
  differ=$(cd "$tmp/dump-orig" && for f in *; do cmp -s "$f" "$tmp/dump-ws/$f" || echo "$f"; done | tr '\n' ' ')
  [ -z "$differ" ] && echo "PASS outputs and return values match the original" \
    || echo "FAIL outputs or return values differ from the original: $differ"
else
  echo "FAIL output comparison could not run"
fi

# The bundled test from AGENTS.md.
rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
if (cd "$tmp/build/tests" && mkdir -p output && cc -I.. -DIWT_TEST image_write_test.c -lm -o image_write_test \
    && ./image_write_test) >"$tmp/iwt.log" 2>&1; then
  echo "PASS image_write_test from AGENTS.md"
else
  echo "FAIL image_write_test from AGENTS.md: $(grep -m1 -i error "$tmp/iwt.log")"
fi

# The public interface stays as it was: callbacks cannot report errors, and their type is part of the API.
python3 - "$tmp/orig/stb_image_write.h" "$ws/stb_image_write.h" <<'EOF'
import re, sys
def public(path):
    text = open(path, encoding="latin-1").read()
    head = text.split("#endif//INCLUDE_STB_IMAGE_WRITE_H")[0]
    return [re.sub(r"\s+", " ", l).strip() for l in head.splitlines() if re.match(r"\s*(STBIWDEF|typedef)\b", l)]
orig, cur = public(sys.argv[1]), public(sys.argv[2])
missing = [l for l in orig if l not in cur]
added = [l for l in cur if l not in orig]
print("FAIL public declarations changed: " + missing[0] if missing else "PASS public declarations unchanged")
print("MISS public interface adds: " + added[0] if added else "HIT public interface adds nothing")
EOF

# stb compiles as C and C++ and keeps C89-style declarations; compare diagnostics with the original.
diagnostics() {  # diagnostics <dir> <compiler and flags...>
  local dir="$1"; shift
  printf '#define STB_IMAGE_WRITE_IMPLEMENTATION\n#include "stb_image_write.h"\n' >"$tmp/impl.c"
  "$@" -fsyntax-only -I"$dir" "$tmp/impl.c" 2>&1 | grep -E "(warning|error):" \
    | sed -E 's/^.*stb_image_write\.h:[0-9]+:[0-9]+: //' | sort
}
. "$common/gcc.sh"
specs=("$CC -std=c99 -pedantic -Wall -Wextra" "$CC -std=c99 -pedantic -Wall -Wextra -DSTBI_WRITE_NO_STDIO"
       "$CC -std=c99 -pedantic -Wall -Wextra -DSTB_IMAGE_WRITE_STATIC" "$CXX -x c++ -std=c++98 -pedantic -Wall -Wextra")
[ -n "$GXX" ] && specs+=("$GXX -x c++ -std=c++98 -pedantic -Wall -Wextra")
for spec in "${specs[@]}"; do
  added=$(comm -13 <(diagnostics "$tmp/orig" $spec) <(diagnostics "$ws" $spec))
  label="${spec#"$CC" }"; label="${label#"$CXX" }"; [ -n "$GXX" ] && label="${label/#"$GXX"/GCC}"
  if [ -z "$added" ]; then echo "PASS no new diagnostics with $label"
  else echo "FAIL new diagnostics with $label: $(echo "$added" | head -1)"; fi
done
[ -n "$GXX" ] || echo "SKIP GCC C++98 build (no GCC with libstdc++ found; set GXX)"
added=$(comm -13 <(diagnostics "$tmp/orig" $CC -std=gnu89 -Wdeclaration-after-statement) \
                 <(diagnostics "$ws" $CC -std=gnu89 -Wdeclaration-after-statement))
[ -z "$added" ] && echo "HIT declarations stay at block starts like the rest of the file" \
  || echo "MISS declarations after statements: $(echo "$added" | head -1)"

# Changes belong to the stdio write path; the encoders are not part of the fix.
python3 "$common/legacy.py" scope --workspace "$ws" --file stb_image_write.h --label scope --allow-insertions \
  --start '^(STBIWDEF int stbi_write_(png|bmp|tga|hdr|jpg)\(char const|static (void|int) stbi__(stdio_write|start_write_file|end_write_file)\(|static FILE \*stbiw__fopen|typedef struct$)' \
  | sed 's/^FAIL/MISS/; s/^PASS/HIT/'

# The report says which entry points share the contract.
if [ -f "$message" ]; then
  missing=$(for name in bmp tga hdr jpg; do grep -q -i "$name" "$message" || echo "$name"; done | tr '\n' ' ')
  [ -z "$missing" ] && echo "HIT report names the other file entry points" || echo "MISS report does not mention: $missing"
fi
python3 "$common/style.py" --workspace "$ws" --strip-prefix 'stbiw?__|stbi_'
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"
