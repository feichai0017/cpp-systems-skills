#!/usr/bin/env bash
# Reviewer-only checks for the tinyxml-path-lookup fixture. Usage: check.sh <workspace>
# CXX must support AddressSanitizer.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
sources="tinyxml.cpp tinyxmlparser.cpp tinyxmlerror.cpp tinystr.cpp"
files=(); for f in $sources; do files+=("$ws/$f"); done
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"

for mode in plain stl; do
  flags=""; [ "$mode" = stl ] && flags="-DTIXML_USE_STL"
  if $CXX -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all -w $flags -I"$ws" "${files[@]}" \
      "$here/hidden_test.cc" -o "$tmp/probe-$mode" 2>"$tmp/probe.log"; then
    out=$(ASAN_OPTIONS=detect_leaks=1 timeout 60 "$tmp/probe-$mode" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL|HIT|MISS) " | sed "s/^\([A-Z]*\) /\1 [$mode] /"
    [ "$code" -eq 0 ] || echo "FAIL [$mode] probe exited $code $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|LeakSanitizer\|runtime error: [^:]*')"
  else
    echo "FAIL [$mode] hidden test does not compile: $(grep -m1 error "$tmp/probe.log")"
  fi
done

# TinyXML offers a std::string form next to const char* lookups when STL is enabled.
printf '#include "tinyxml.h"\n#include <string>\nconst TiXmlElement* f(const TiXmlNode& n) { return n.FirstChildElementByPath(std::string("a/b")); }\n' >"$tmp/overload.cc"
$CXX -DTIXML_USE_STL -fsyntax-only -I"$ws" "$tmp/overload.cc" 2>/dev/null \
  && echo "HIT std::string overload under TIXML_USE_STL, like FirstChildElement" \
  || echo "MISS no std::string overload under TIXML_USE_STL"

for mode in plain stl; do
  rm -rf "$tmp/build"; cp -R "$ws" "$tmp/build"
  stl=NO; base=109; [ "$mode" = stl ] && { stl=YES; base=137; }
  if (cd "$tmp/build" && make clean >/dev/null 2>&1; make CXX="$CXX" LD="$CXX" TINYXML_USE_STL=$stl >"$tmp/make.log" 2>&1); then
    result=$(cd "$tmp/build" && timeout 60 ./xmltest 2>&1 | grep -E "^Pass [0-9]+, Fail [0-9]+")
    pass=$(echo "$result" | sed -E 's/Pass ([0-9]+).*/\1/'); fail=$(echo "$result" | sed -E 's/.*Fail ([0-9]+)/\1/')
    if [ -n "$result" ] && [ "$fail" = 0 ] && [ "$pass" -gt "$base" ]; then echo "PASS [$mode] xmltest adds passing tests: $result (was $base)"
    else echo "FAIL [$mode] xmltest: ${result:-no summary} (was $base)"; fi
  else
    echo "FAIL [$mode] Makefile build: $(grep -m1 error "$tmp/make.log")"
  fi
done
grep -q "FirstChildElementByPath" "$ws/xmltest.cpp" && echo "PASS xmltest.cpp exercises FirstChildElementByPath" \
  || echo "FAIL xmltest.cpp has no FirstChildElementByPath test"

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

for f in tinyxml.cpp tinyxml.h; do
  python3 "$common/legacy.py" scope --workspace "$ws" --file "$f" --label scope --allow-insertions
done
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u | tr '\n' ' ')
echo "INFO changed files: ${changed:-none}"

# TinyXML documents each public member with a Doxygen comment directly above it.
awk '/FirstChildElementByPath/ && prev ~ /\/\/\/|\*\/|\/\*\*/ {found=1} {if ($0 !~ /^[ \t]*$/) prev=$0} END {exit !found}' "$ws/tinyxml.h" \
  && echo "HIT declaration carries a Doxygen comment like its neighbors" || echo "MISS declaration lacks a Doxygen comment"
