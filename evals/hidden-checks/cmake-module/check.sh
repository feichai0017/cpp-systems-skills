#!/usr/bin/env bash
# Reviewer-only checks for the cmake-module fixture. Usage: check.sh <workspace>
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"

echo "--- structure"
python3 - "$ws" <<'PY'
import pathlib, re, sys
ws = pathlib.Path(sys.argv[1])
cm = (ws / "CMakeLists.txt").read_text()
def report(ok, what): print(("PASS " if ok else "FAIL ") + what)
headers = [p for p in (ws / "include").rglob("*.h*") if "ReadRecords" in p.read_text()]
report(any(p.parent == ws / "include/kvstore/storage" for p in headers), "public header under include/kvstore/storage")
report(all('checksum/' not in p.read_text() for p in headers), "public header does not expose the internal checksum header")
impl = [p for p in (ws / "src").rglob("*.cc") if "ReadRecords" in p.read_text()]
report(any(p.parent == ws / "src/storage" for p in impl), "implementation under src/storage")
for bad in ["include_directories(", "link_libraries(", "link_directories(", "file(GLOB", "CMAKE_CXX_FLAGS", "add_definitions("]:
    if re.search(r"(?<![_a-z])" + re.escape(bad), cm):
        report(False, f"no directory-wide or flag edits ({bad})")
blocks = re.findall(r"target_link_libraries\(\s*kvstore_storage\b(.*?)\)", cm, re.S)
keyword = None
for block in blocks:
    current = None
    for token in block.split():
        if token in ("PUBLIC", "PRIVATE", "INTERFACE"):
            current = token
        elif token == "kvstore_checksum":
            keyword = current
report(keyword == "PRIVATE", f"kvstore_checksum linked PRIVATE to kvstore_storage (found {keyword})")
dup = [p for p in ws.rglob("*.*") if p.suffix in (".h", ".hpp", ".cc", ".cpp") and "src/checksum" not in str(p)
       and ".agents" not in p.parts and re.search(r"0x[eE][dD][bB]88320", p.read_text())]
report(not dup, "reuses the existing CRC32 instead of reimplementing it")
PY

echo "--- build, ctest"
cmake -S "$ws" -B "$tmp/plain" -G Ninja >/dev/null 2>&1 && cmake --build "$tmp/plain" >/dev/null 2>&1 \
  && echo "PASS project builds" || echo "FAIL project builds"
tests=$(ctest --test-dir "$tmp/plain" -N 2>/dev/null | grep -c "Test *#")
[ "$tests" -gt 1 ] && echo "PASS new test registered with ctest ($tests tests)" || echo "FAIL new test registered ($tests tests)"
ctest --test-dir "$tmp/plain" >/dev/null 2>&1 && echo "PASS ctest" || echo "FAIL ctest"

echo "--- hidden behavior under ASan/UBSan"
san="-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
cmake -S "$ws" -B "$tmp/san" -G Ninja -DCMAKE_CXX_FLAGS="$san" >/dev/null 2>&1 && cmake --build "$tmp/san" >/dev/null 2>&1 || { echo "FAIL sanitizer build"; exit 0; }
header=$(grep -rl "ReadRecords" "$ws/include" | head -1)
libs=$(find "$tmp/san" -name 'libkvstore_storage.a' -o -name 'libkvstore_checksum.a' | sort -r | tr '\n' ' ')
$CXX -std=c++20 $san -DRECORDS_HEADER="\"$header\"" -I"$ws/include" -I"$ws/src" "$here/hidden_test.cc" $libs -o "$tmp/hidden" 2>"$tmp/compile.log" \
  || { echo "FAIL hidden test does not compile against the API"; head -5 "$tmp/compile.log"; exit 0; }
"$tmp/hidden" 2>&1 | tail -12
