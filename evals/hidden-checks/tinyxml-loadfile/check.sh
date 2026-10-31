#!/usr/bin/env bash
# Reviewer-only checks for the tinyxml-loadfile fixture. Usage: check.sh <workspace>
# CXX must support AddressSanitizer. The imported original is taken from the
# workspace's root commit and serves as the behavior oracle.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
sources="tinyxml.cpp tinyxmlparser.cpp tinyxmlerror.cpp tinystr.cpp"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"

probe() {  # probe <source dir> <output> <extra flags...>
  local dir="$1" out="$2"; shift 2
  local files=(); for f in $sources; do files+=("$dir/$f"); done
  $CXX -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w "$@" -I"$dir" "${files[@]}" \
    "$here/hidden_test.cc" -o "$out.bin" 2>"$out.log" || { echo "compile error: $(head -3 "$out.log")" >"$out"; return; }
  mkdir -p "$out.dir"
  ASAN_OPTIONS=detect_leaks=1 timeout 60 "$out.bin" "$out.dir" >"$out" 2>"$out.err" || echo "exit $? $(grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*' "$out.err")" >>"$out"
}

for mode in plain stl; do
  flags=""; [ "$mode" = stl ] && flags="-DTIXML_USE_STL"
  probe "$tmp/orig" "$tmp/orig-$mode" $flags
  probe "$ws" "$tmp/ws-$mode" $flags
  diff <(grep "^golden" "$tmp/orig-$mode") <(grep "^golden" "$tmp/ws-$mode") >"$tmp/golden-$mode.diff"; same=$?
  if grep -q "^golden" "$tmp/ws-$mode" && [ "$same" -eq 0 ]; then
    echo "PASS [$mode] LoadFile keeps the original results on $(grep -c '^golden' "$tmp/ws-$mode") inputs"
  else
    echo "FAIL [$mode] LoadFile results differ from the original:"; grep '^[<>]' "$tmp/golden-$mode.diff" | head -6 | sed 's/^/    /'
    grep -v "^golden\|^rule" "$tmp/ws-$mode" | head -3 | sed 's/^/    /'
  fi
  while read -r line; do
    case "$line" in
      *": ok "*) echo "PASS [$mode] ${line%% (*}" ;;
      *) echo "FAIL [$mode] ${line}" ;;
    esac
  done < <(grep "^rule" "$tmp/ws-$mode" | sed 's/^rule /fault /')
  grep -q "^exit" "$tmp/ws-$mode" && echo "FAIL [$mode] probe $(grep '^exit' "$tmp/ws-$mode")"
done

# The project's own test program, built in a copy so the workspace stays untouched.
for mode in plain stl; do
  rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
  stl=NO; base=109; [ "$mode" = stl ] && { stl=YES; base=137; }
  if (cd "$tmp/build" && make clean >/dev/null 2>&1; make CXX="$CXX" LD="$CXX" TINYXML_USE_STL=$stl >"$tmp/make.log" 2>&1); then
    result=$(cd "$tmp/build" && timeout 60 ./xmltest 2>&1 | grep -E "^Pass [0-9]+, Fail [0-9]+")
    pass=$(echo "$result" | sed -E 's/Pass ([0-9]+).*/\1/'); fail=$(echo "$result" | sed -E 's/.*Fail ([0-9]+)/\1/')
    if [ -n "$result" ] && [ "$fail" = 0 ] && [ "$pass" -ge "$base" ]; then echo "PASS [$mode] xmltest: $result"
    else echo "FAIL [$mode] xmltest: ${result:-no summary}"; fi
  else
    echo "FAIL [$mode] Makefile build: $(grep -m1 error "$tmp/make.log")"
  fi
done

# Documented portability: C++98 compilers, no exceptions or RTTI, no STL headers when STL is off.
for mode in plain stl; do
  flags=""; [ "$mode" = stl ] && flags="-DTIXML_USE_STL"
  for spec in "-std=c++98 -pedantic-errors" "-fno-exceptions -fno-rtti"; do
    bad=""; : >"$tmp/std.log"
    for f in $sources; do $CXX $spec $flags -fsyntax-only -I"$ws" "$ws/$f" 2>>"$tmp/std.log" || bad="$bad $f"; done
    if [ -z "$bad" ]; then echo "PASS [$mode] compiles with $spec"
    else echo "FAIL [$mode] does not compile with $spec:$bad $(grep -m1 error "$tmp/std.log")"; fi
  done
done
. "$common/gcc.sh"
if [ -n "$GXX" ]; then
  for mode in plain stl; do
    flags=""; [ "$mode" = stl ] && flags="-DTIXML_USE_STL"
    bad=""; : >"$tmp/gcc.log"
    for f in $sources; do "$GXX" -std=c++98 -pedantic-errors $flags -fsyntax-only -I"$ws" "$ws/$f" 2>>"$tmp/gcc.log" || bad="$bad $f"; done
    if [ -z "$bad" ]; then echo "PASS [$mode] compiles with GCC libstdc++ -std=c++98"
    else echo "FAIL [$mode] does not compile with GCC libstdc++ -std=c++98:$bad $(grep -m1 error "$tmp/gcc.log" | sed 's|.*/||')"; fi
  done
else
  echo "SKIP GCC C++98 build (no GCC with libstdc++ found; set GXX)"
fi
python3 "$common/legacy.py" includes --cxx "$CXX" --original "$tmp/orig" --workspace "$ws" --label "[plain] no-STL build" $sources

python3 "$common/legacy.py" scope --workspace "$ws" --file tinyxml.cpp --label scope \
  --start '^bool TiXmlDocument::LoadFile\(' --allow-insertions
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"
git -C "$ws" diff --quiet "$root" -- tinyxml.h || echo "INFO tinyxml.h changed: $(git -C "$ws" diff --stat "$root" -- tinyxml.h | tail -1)"

# Manual frees in the loader: the original releases the buffer on two separate paths.
orig_deletes=$(grep -c 'delete *\[\]' "$tmp/orig/tinyxml.cpp"); ws_deletes=$(grep -c 'delete *\[\]' "$ws/tinyxml.cpp")
[ "$ws_deletes" -lt "$orig_deletes" ] && echo "HIT buffer release no longer repeated per error path" \
  || echo "MISS buffer release still repeated per error path ($ws_deletes 'delete []' vs $orig_deletes)"
