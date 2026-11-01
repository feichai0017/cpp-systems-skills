#!/usr/bin/env bash
# Reviewer-only checks for the args-duration-values fixture. Usage: check.sh <workspace> [final message]
# CXX must support AddressSanitizer. The imported original is taken from the workspace's root commit.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"; common="$here/../common"
message="${2:-}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
root="$(git -C "$ws" rev-list --max-parents=0 HEAD)"
mkdir "$tmp/orig" && git -C "$ws" archive "$root" | tar -x -C "$tmp/orig"
san="-g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all"
# The project's test flags (args_configure_test) plus the hardening warnings CMake adds by default.
project_warnings="-Wall -Wextra -pedantic -Wshadow -Wunused-parameter -Wconversion -Wsign-conversion -Wnull-dereference -Wformat=2 -Wcast-align -Wunused"

# One translation unit per family, in the project's C++11.
probe() {  # probe <label> <family> <flags...>
  local label="$1" family="$2"; shift 2
  local bin="$tmp/$family-${label// /_}"
  if $CXX $san -w -std=c++11 -DFAMILY_$family "$@" -I"$ws" "$here/hidden_test.cc" -o "$bin" 2>"$bin.log"; then
    out=$(timeout 30 "$bin" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL|HIT|MISS) " | sed -E "s/^([A-Z]+) duration /\1 [$label] duration /"
    echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
      && echo "FAIL [$label] duration $family: $(echo "$out" | grep -o -m1 'runtime error: .*\|AddressSanitizer: [a-z-]*' | cut -c1-140)"
    [ "$code" -le 1 ] || echo "FAIL [$label] duration $family: probe exited $code"
  else
    echo "FAIL [$label] duration $family: does not compile: $(grep -m1 'error:' "$bin.log" | sed -E 's/^.*error: //' | cut -c1-160)"
  fi
}
for family in units exact range floating syntax usage; do probe c++11 $family; done
probe c++11 count_syntax
probe "c++11 ARGS_NOEXCEPT" noexcept -DARGS_NOEXCEPT -fno-exceptions

# Header diagnostics: nothing new for existing users, in every mode and with both standard libraries.
printf '#include <args.hxx>\nint main(int argc, char** argv) {\n  args::ArgumentParser p("p");\n  args::ValueFlag<int> n(p, "N", "", {"n"});\n  p.ParseCLI(argc, argv);\n  return args::get(n);\n}\n' >"$tmp/plain.cc"
. "$common/gcc.sh"
diagnostics() {  # diagnostics <dir> <source> <compiler and flags...>
  local dir="$1" src="$2"; shift 2
  "$@" -fsyntax-only -I"$dir" "$src" 2>&1 | grep -E "args\.hxx:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*args\.hxx:[0-9]+:[0-9]+: //' | sort -u
}
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  for std in c++11 c++14 c++17 c++20; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$tmp/plain.cc" "$compiler" -std=$std $project_warnings) \
                     <(diagnostics "$ws" "$tmp/plain.cc" "$compiler" -std=$std $project_warnings))
    [ -z "$added" ] && echo "PASS [$name $std] header adds no diagnostics" || echo "FAIL [$name $std] header: $(echo "$added" | head -1)"
  done
done

# Instantiating the duration reader adds no warnings under the project's flags: the standard
# typedefs are graded, other counts (short, int32 nanoseconds, unsigned, a 1/30 s period, float)
# are recorded.
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  base=$(diagnostics "$ws" "$tmp/plain.cc" "$compiler" -std=c++11 $project_warnings)
  for family in units exact range floating; do
    added=$(comm -13 <(echo "$base") <(diagnostics "$ws" "$here/hidden_test.cc" "$compiler" -std=c++11 $project_warnings -DFAMILY_$family))
    case $family in units) kind=PASS; bad=FAIL ;; *) kind=HIT; bad=MISS ;; esac
    [ -z "$added" ] && echo "$kind [$name] $family instantiation adds no warnings" \
      || echo "$bad [$name] $family instantiation warns: $(echo "$added" | head -1 | cut -c1-160)"
  done
done

# The project's tests as AGENTS.md builds them (each test/<name>.cxx with warnings as errors),
# and the original tests against the new header.
project_test() {  # project_test <label> <source dir>
  local label="$1" src="$2"
  rm -rf "$tmp/build"; cp -R "$src" "$tmp/build"; rm -rf "$tmp/build/build"
  if (cd "$tmp/build" && cmake -S . -B build -DCMAKE_CXX_COMPILER="$CXX" -DARGS_BUILD_EXAMPLE=OFF \
      && cmake --build build -j8 && ctest --test-dir build --output-on-failure -j8) >"$tmp/own.log" 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label: $(grep -m1 -E 'error:|Failed|FAILED' "$tmp/own.log" | cut -c1-160)"
  fi
}
project_test "tests from AGENTS.md" "$ws"
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && cp "$ws/args.hxx" "$tmp/mixed/"
project_test "original tests pass with the new header" "$tmp/mixed"
changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
tests=$(echo "$changed" | grep -E '^test/.*\.(cxx|hxx)$')
if [ -n "$tests" ] && (cd "$ws" && cat $tests) | grep -q -E 'chrono|duration|milliseconds'; then
  echo "PASS tests cover duration values"
else
  echo "FAIL no test covers duration values"
fi
git -C "$ws" diff -U0 "$root" -- test | grep -a -q '^-[^-]' && echo "MISS existing tests change lines" || echo "HIT existing tests only gain cases"

# Reuse: the count is read by the existing ParseNumericValue (or operator()) for Rep, which already
# defines the accepted syntax. Lines that only moved (removed and added unchanged) are not new code.
git -C "$ws" diff -U0 "$root" -- args.hxx | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- args.hxx | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
if echo "$new_code" | grep -q -E 'std::sto(i|l|ll|ul|ull|f|d|ld)\b|\bstrto(l|ll|ul|ull|d|f|ld|imax|umax)\b|from_chars|std::regex|regex_match|sscanf|\b(i|o)?stringstream\b'; then
  echo "MISS count parsing re-implemented: $(echo "$new_code" | grep -m1 -o -E 'std::sto[a-z]*|strto[a-z]*|from_chars|std::regex|regex_match|sscanf|\b(i|o)?stringstream\b')"
elif echo "$new_code" | grep -v -E 'const std::string ?& ?\w+, ?std::chrono' | grep -q -E '\bParseNumericValue\(|\(\*this\)\(|\breader\('; then
  echo "HIT count parsed by the existing ParseNumericValue for Rep"
else
  echo "MISS count parsing does not go through ParseNumericValue"
fi
removed=$(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -c -v -E '^\s*$')
[ "$removed" -eq 0 ] && echo "HIT header changes only add code" \
  || echo "MISS header changes $removed existing lines: $(comm -23 "$tmp/removed.txt" "$tmp/added.txt" | grep -v -E '^\s*$' | head -1 | sed -E 's/^\s+//' | cut -c1-100)"

# Shape of the generic code. The unit ratios are compile-time constants: std::ratio_divide reduces
# them, so a hand-written greatest common divisor is re-implementing the standard library.
echo "$new_code" | grep -v 'std::gcd' | grep -q -i -E '\bgcd\b|greatest_?common|common_?divisor|\w+_gcd\b|gcd\(' \
  && echo "MISS hand-writes a greatest common divisor" || echo "HIT no hand-written greatest common divisor"
count() { echo "$new_code" | grep -c -E "$1"; }
echo "INFO header adds $(echo "$new_code" | grep -c -v -E '^\s*(//.*)?$') lines: template $(count '^\s*template\s*<') struct/class $(count '^\s*(struct|class)\s+\w+') enable_if $(count 'enable_if') tag-dispatch $(count 'true_type|false_type|integral_constant|is_integral<|is_floating_point<') ratio_divide $(count 'ratio_divide') table $(count 'std::(map|unordered_map|array|pair)<|\[\]\s*=\s*\{')"
echo "$new_code" | grep -q -E '(struct|class)\s+\w*(is_|_trait|Trait)\w*|:\s*(public\s+)?std::(true|false)_type' \
  && echo "MISS adds a type trait for duration" || echo "HIT no new type traits"

extra=$(echo "$changed" | grep -v -E '^(args\.hxx|test/.*|README\.md|CHANGELOG|meson\.build)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in the header, tests, README, CHANGELOG and meson.build" || echo "MISS scope: also changes $extra"
git -C "$ws" diff -U0 "$root" -- README.md | grep -a '^+[^+]' | grep -q -i -E 'chrono|duration' \
  && echo "HIT README documents duration values" || echo "MISS README does not document duration values"
if [ -f "$message" ]; then
  named=$(for word in NOEXCEPT ValueFlagList Positional Nargs README C++11; do grep -q -i -F "$word" "$message" && echo "$word"; done | tr '\n' ' ')
  echo "INFO report mentions: ${named:-none}"
fi
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
