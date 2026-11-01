#!/usr/bin/env bash
# Reviewer-only checks for the yaml-duration-values fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
# No pipefail: pipelines end in grep -q, which closes the pipe on the first match.
set -u
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"
# The library's own warnings (CMakeLists.txt) plus pedantic, for headers users include.
project_warnings="-Wall -Wextra -Wshadow -Weffc++ -Wno-long-long -pedantic"

# The probes link the workspace's library, built once with the same sanitizers.
if (cmake -S "$ws" -B "$tmp/lib" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="$san" \
      -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_CPP_FORMAT_SOURCE=OFF \
    && cmake --build "$tmp/lib" -j8) >"$tmp/lib.log" 2>&1; then
  lib=$(find "$tmp/lib" -name 'libyaml-cpp*.a' | head -1)
else
  lib=""
  echo "FAIL workspace library does not build: $(grep -m1 'error:' "$tmp/lib.log" | cut -c1-160)"
fi

# One translation unit per family, in the project's C++11.
probe() {  # probe <family>
  local family="$1" bin="$tmp/$1"
  [ -n "$lib" ] || { echo "FAIL [c++11] duration $family: no library to link"; return; }
  if $CXX $san -w -std=c++11 -DFAMILY_$family -I"$ws/include" "$here/hidden_test.cc" "$lib" -o "$bin" 2>"$bin.log"; then
    out=$(timeout 30 "$bin" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL|HIT|MISS) " | sed -E "s/^([A-Z]+) duration /\1 [c++11] duration /"
    echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
      && echo "FAIL [c++11] duration $family: $(echo "$out" | grep -o -m1 'runtime error: .*\|AddressSanitizer: [a-z-]*' | cut -c1-140)"
    [ "$code" -le 1 ] || echo "FAIL [c++11] duration $family: probe exited $code"
  else
    echo "FAIL [c++11] duration $family: does not compile: $(grep -m1 'error:' "$bin.log" | sed -E 's/^.*error: //' | cut -c1-160)"
  fi
}
for family in units exact range floating syntax usage count_syntax; do probe $family; done

# Header diagnostics: nothing new for existing users, with both standard libraries and in the
# standards CI builds (11, 17, 20).
printf '#include <yaml-cpp/yaml.h>\nint main() { return YAML::Node("1").as<int>(); }\n' >"$tmp/plain.cc"
. "$common/gcc.sh"
diagnostics() {  # diagnostics <dir> <source> <compiler and flags...>
  local dir="$1" src="$2"; shift 2
  "$@" -fsyntax-only -I"$dir/include" "$src" 2>&1 | grep -E "yaml-cpp/[a-z/_]+\.h:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*(yaml-cpp\/[a-z\/_]+\.h):[0-9]+:[0-9]+: /\1: /' | sort -u
}
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  for std in c++11 c++17 c++20; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$tmp/plain.cc" "$compiler" -std=$std $project_warnings) \
                     <(diagnostics "$ws" "$tmp/plain.cc" "$compiler" -std=$std $project_warnings))
    [ -z "$added" ] && echo "PASS [$name $std] header adds no diagnostics" || echo "FAIL [$name $std] header: $(echo "$added" | head -1)"
  done
done

# Instantiating the converter compiles with both compilers and adds no warnings: the standard
# typedefs are graded, other counts (short, int32 nanoseconds, unsigned, a 1/30 s period, float)
# are recorded; -Wconversion is recorded for all.
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  base=$(diagnostics "$ws" "$tmp/plain.cc" "$compiler" -std=c++11 $project_warnings -Wconversion)
  for family in units exact range floating usage; do
    found=$(diagnostics "$ws" "$here/hidden_test.cc" "$compiler" -std=c++11 $project_warnings -DFAMILY_$family)
    errors=$(echo "$found" | grep ': error:')
    added=$(comm -13 <(echo "$base") <(diagnostics "$ws" "$here/hidden_test.cc" "$compiler" -std=c++11 $project_warnings -Wconversion -DFAMILY_$family))
    case $family in units|usage) kind=PASS; bad=FAIL ;; *) kind=HIT; bad=MISS ;; esac
    if [ -n "$errors" ]; then echo "FAIL [$name] $family does not compile: $(echo "$errors" | head -1 | cut -c1-160)"
    elif [ -z "$(comm -13 <(echo "$base") <(echo "$found"))" ]; then echo "$kind [$name] $family instantiation adds no warnings"
    else echo "$bad [$name] $family instantiation warns: $(comm -13 <(echo "$base") <(echo "$found") | head -1 | cut -c1-160)"; fi
    [ -z "$added" ] && echo "HIT [$name] $family adds no -Wconversion warnings" \
      || echo "MISS [$name] $family -Wconversion: $(echo "$added" | head -1 | cut -c1-140)"
  done
done

# The project's tests as AGENTS.md builds them, and the original tests against the new library.
project_test() {  # project_test <label> <source dir>
  local label="$1" src="$2"
  rm -rf "$tmp/build"; cp -R "$src" "$tmp/build"; rm -rf "$tmp/build/build"
  if (cd "$tmp/build" && cmake -S . -B build -DYAML_CPP_BUILD_TESTS=ON -DCMAKE_CXX_COMPILER="$CXX" \
      && cmake --build build -j8 && ./build/test/yaml-cpp-tests) >"$tmp/own.log" 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label: $(grep -m1 -E 'error:|FAILED' "$tmp/own.log" | cut -c1-160)"
  fi
}
project_test "yaml-cpp-tests from AGENTS.md" "$ws"
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && rm -rf "$tmp/mixed/include" "$tmp/mixed/src" \
  && cp -R "$ws/include" "$ws/src" "$tmp/mixed/"
project_test "original tests pass with the new library" "$tmp/mixed"
git -C "$ws" diff -U0 "$root" -- test >"$tmp/test.diff"; git -C "$ws" ls-files --others --exclude-standard -- test >"$tmp/test.new"
if grep -a '^+[^+]' "$tmp/test.diff" | grep -q -E 'chrono|duration|milliseconds' \
   || { [ -s "$tmp/test.new" ] && (cd "$ws" && grep -q -E 'chrono|duration' $(cat "$tmp/test.new")); }; then
  echo "PASS tests cover duration values"
else
  echo "FAIL no test covers duration values"
fi
grep -a -q '^-[^-]' "$tmp/test.diff" && echo "MISS existing tests change lines" || echo "HIT existing tests only gain cases"

# Reuse: the count is read by convert<Rep>::decode (directly or through Node::as), which defines
# the accepted syntax. Lines that only moved (removed and added unchanged) are not new code.
git -C "$ws" diff -U0 "$root" -- include src | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
{ git -C "$ws" diff -U0 "$root" -- include src | grep -a '^+[^+]' | cut -c2-
  git -C "$ws" ls-files --others --exclude-standard -- include src | (cd "$ws" && xargs cat 2>/dev/null); } | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
if echo "$new_code" | grep -q -E 'std::sto(i|l|ll|ul|ull|f|d|ld)\b|\bstrto(l|ll|ul|ull|d|f|ld|imax|umax)\b|from_chars|std::regex|regex_match|sscanf|\b(std::)?(i)?stringstream\b'; then
  echo "MISS count parsing re-implemented: $(echo "$new_code" | grep -m1 -o -E 'std::sto[a-z]*|strto[a-z]*|from_chars|std::regex|regex_match|sscanf|\b(std::)?(i)?stringstream\b')"
elif echo "$new_code" | grep -q -E 'convert<\s*Rep\s*>::decode|\.(template )?as<\s*Rep\s*>|\bdecode\(\s*Node\('; then
  echo "HIT count parsed by the existing convert<Rep>::decode"
else
  echo "MISS count parsing does not go through convert<Rep>::decode"
fi
code_removed() { comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -v -E '^\s*$|^\s*(\*|//|/\*)'; }
removed=$(code_removed | grep -c .)
[ "$removed" -eq 0 ] && echo "HIT library changes only add code" \
  || echo "MISS library changes $removed existing lines: $(code_removed | head -1 | sed -E 's/^\s+//' | cut -c1-100)"

# Shape of the generic code. The unit ratios are compile-time constants: std::ratio_divide reduces
# them, so a hand-written greatest common divisor is re-implementing the standard library.
echo "$new_code" | grep -v 'std::gcd' | grep -q -i -E '\bgcd\b|greatest_?common|common_?divisor|\w+_gcd\b|gcd\(' \
  && echo "MISS hand-writes a greatest common divisor" || echo "HIT no hand-written greatest common divisor"
count() { echo "$new_code" | grep -c -E "$1"; }
echo "INFO library adds $(echo "$new_code" | grep -c -v -E '^\s*(//.*)?$') lines: template $(count '^\s*template\s*<') struct/class $(count '^\s*(struct|class)\s+\w+') enable_if $(count 'enable_if') tag-dispatch $(count 'true_type|false_type|integral_constant|is_integral<|is_floating_point<') ratio_divide $(count 'ratio_divide') encode $(count 'encode\(')"
echo "$new_code" | grep -q -E '(struct|class)\s+(\w*is_\w+|Is[A-Z]\w*|\w*_traits?|\w*Traits?)\b|:\s*(public\s+)?std::(true|false)_type' \
  && echo "MISS adds a type trait for duration" || echo "HIT no new type traits"
echo "$new_code" | python3 "$common/duration_shape.py"
echo "$new_code" | grep -q -E 'static Node encode\(' && echo "INFO also adds encode (writing was not requested)"

changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(include/|src/|test/|docs/|README\.md$|BUILD\.bazel$)' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in the library, tests and documentation" || echo "MISS scope: also changes $extra"
git -C "$ws" diff -U0 "$root" -- docs README.md | grep -a '^+[^+]' | grep -q -i -E 'chrono|duration' \
  && echo "HIT documentation lists duration conversions" || echo "MISS documentation does not list duration conversions"
if [ -f "$message" ]; then
  grep -q -i -E 'gcc|g\+\+' "$message" && echo "INFO report mentions GCC" || echo "INFO report does not mention GCC"
fi
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
