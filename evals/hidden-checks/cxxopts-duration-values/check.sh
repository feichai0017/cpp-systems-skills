#!/usr/bin/env bash
# Reviewer-only checks for the cxxopts-duration-values fixture. Usage: check.sh <workspace> [final message]
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
# The warnings cxxopts_enable_warnings() turns into errors for the project's own build.
project_warnings="-Wall -Wextra -Wshadow -Weffc++ -Wsign-compare -Wwrite-strings -Wpointer-arith -Winit-self -Wconversion -Wno-sign-conversion"

# One translation unit per family. The project targets C++11; std::optional needs C++17;
# CXXOPTS_NO_REGEX switches the integer parser to its non-regex implementation.
probe() {  # probe <label> <family> <flags...>
  local label="$1" family="$2"; shift 2
  local bin="$tmp/$family-${label// /_}"
  if $CXX $san -w -DFAMILY_$family "$@" -I"$ws/include" "$here/hidden_test.cc" -o "$bin" 2>"$bin.log"; then
    out=$(timeout 30 "$bin" 2>&1); code=$?
    echo "$out" | grep -E "^(PASS|FAIL) " | sed "s/^\([A-Z]*\) duration /\1 [$label] duration /"
    echo "$out" | grep -q -E "AddressSanitizer|runtime error" \
      && echo "FAIL [$label] duration $family: $(echo "$out" | grep -o -m1 'runtime error: .*\|AddressSanitizer: [a-z-]*' | cut -c1-140)"
    [ "$code" -le 1 ] || echo "FAIL [$label] duration $family: probe exited $code"
  else
    echo "FAIL [$label] duration $family: does not compile: $(grep -m1 'error:' "$bin.log" | sed -E 's/^.*error: //' | cut -c1-160)"
  fi
}
for family in units exact range floating syntax usage; do probe c++11 $family -std=c++11; done
probe c++17 optional -std=c++17
for family in units range syntax; do probe "c++11 no-regex" $family -std=c++11 -DCXXOPTS_NO_REGEX; done

# Header diagnostics: nothing new for existing users, in every mode and with both standard libraries.
printf '#include <cxxopts.hpp>\nint main(int argc, char** argv) {\n  cxxopts::Options o("p");\n  o.add_options()("n", "", cxxopts::value<int>());\n  return o.parse(argc, argv)["n"].count() ? 0 : 1;\n}\n' >"$tmp/plain.cc"
. "$common/gcc.sh"
diagnostics() {  # diagnostics <dir> <source> <compiler and flags...>
  local dir="$1" src="$2"; shift 2
  "$@" -fsyntax-only -I"$dir/include" "$src" 2>&1 | grep -E "cxxopts\.hpp:[0-9]+:[0-9]+: (warning|error):" \
    | sed -E 's/^.*cxxopts\.hpp:[0-9]+:[0-9]+: //' | sort -u
}
for compiler in "$CXX" ${GXX:+"$GXX"}; do
  name="$(basename "$compiler")"
  for std in c++11 c++14 c++17 c++20; do
    added=$(comm -13 <(diagnostics "$tmp/orig" "$tmp/plain.cc" "$compiler" -std=$std -pedantic $project_warnings) \
                     <(diagnostics "$ws" "$tmp/plain.cc" "$compiler" -std=$std -pedantic $project_warnings))
    [ -z "$added" ] && echo "PASS [$name $std] header adds no diagnostics" || echo "FAIL [$name $std] header: $(echo "$added" | head -1)"
  done
done

# Instantiating the duration parser adds no warnings under the project's own flags: the standard
# typedefs and duration<double> are graded, other counts (short, int32 nanoseconds, unsigned,
# a 1/30 s period, float) are recorded.
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

# CXXOPTS_NO_EXCEPTIONS builds keep compiling (errors print and exit instead of throwing).
printf '#define CXXOPTS_NO_EXCEPTIONS\n#include <cxxopts.hpp>\n#include <chrono>\nint main(int argc, char** argv) {\n  cxxopts::Options o("p");\n  o.add_options()("t", "", cxxopts::value<std::chrono::milliseconds>()->default_value("2s"))\n    ("d", "", cxxopts::value<std::chrono::duration<double>>()->default_value("1.5s"));\n  auto r = o.parse(argc, argv);\n  return r["t"].as<std::chrono::milliseconds>().count() == 2000 && r["d"].as<std::chrono::duration<double>>().count() == 1.5 ? 0 : 1;\n}\n' >"$tmp/noexc.cc"
if $CXX -std=c++11 -fno-exceptions -w -I"$ws/include" "$tmp/noexc.cc" -o "$tmp/noexc" 2>"$tmp/noexc.log" && "$tmp/noexc"; then
  echo "PASS CXXOPTS_NO_EXCEPTIONS build parses durations"
else
  echo "FAIL CXXOPTS_NO_EXCEPTIONS build: $(grep -m1 'error:' "$tmp/noexc.log" | sed -E 's/^.*error: //' | cut -c1-160)"
fi

# The project's tests as AGENTS.md builds them (warnings are errors there), in C++11 and C++17,
# and the original test file against the new header.
project_test() {  # project_test <label> <source dir> <cmake args...>
  local label="$1" src="$2"; shift 2
  rm -rf "$tmp/build"; cp -R "$src" "$tmp/build"; rm -rf "$tmp/build/build"
  if (cd "$tmp/build" && cmake -S . -B build -DCXXOPTS_BUILD_TESTS=ON -DCMAKE_CXX_COMPILER="$CXX" "$@" \
      && cmake --build build --target options_test -j8 && ./build/test/options_test) >"$tmp/own.log" 2>&1; then
    echo "PASS $label"
  else
    echo "FAIL $label: $(grep -m1 -E 'error|FAILED|failed' "$tmp/own.log" | cut -c1-160)"
  fi
}
project_test "options_test from AGENTS.md (C++11)" "$ws"
project_test "options_test from AGENTS.md (C++17)" "$ws" -DCXXOPTS_CXX_STANDARD=17
mkdir "$tmp/mixed" && cp -R "$tmp/orig/." "$tmp/mixed" && cp "$ws/include/cxxopts.hpp" "$tmp/mixed/include/"
project_test "original options.cpp passes with the new header (C++17)" "$tmp/mixed" -DCXXOPTS_CXX_STANDARD=17
git -C "$ws" diff -U0 "$root" -- test/options.cpp | grep -a '^+[^+]' | grep -q -E 'chrono|duration|milliseconds|seconds' \
  && echo "PASS options.cpp covers duration values" || echo "FAIL options.cpp does not test duration values"
git -C "$ws" diff -U0 "$root" -- test/options.cpp | grep -a -q '^-[^-]' \
  && echo "MISS options.cpp changes existing lines" || echo "HIT options.cpp only adds tests"

# Reuse: the count is read by the project's own parse_value for Rep, and errors are the project's.
# Lines that only moved (removed and added unchanged) are not new code.
git -C "$ws" diff -U0 "$root" -- include/cxxopts.hpp | grep -a '^-[^-]' | cut -c2- | sort >"$tmp/removed.txt"
git -C "$ws" diff -U0 "$root" -- include/cxxopts.hpp | grep -a '^+[^+]' | cut -c2- | sort >"$tmp/added.txt"
new_code=$(comm -13 "$tmp/removed.txt" "$tmp/added.txt")
if echo "$new_code" | grep -q -E 'std::sto(i|l|ll|ul|ull|f|d|ld)\b|\bstrto(l|ll|ul|ull|d|f|ld|imax|umax)\b|from_chars|std::regex|regex_match|sscanf|\b(std::)?(i)?stringstream\b'; then
  echo "MISS count parsing re-implemented: $(echo "$new_code" | grep -m1 -o -E 'std::sto[a-z]*|strto[a-z]*|from_chars|std::regex|regex_match|sscanf|\b(std::)?(i)?stringstream\b')"
elif echo "$new_code" | grep -v -E 'const std::string ?& ?\w+, ?std::chrono' | grep -q -E '\b(parse_value|integer_parser|stringstream_parser)\('; then
  echo "HIT count parsed by the existing parse_value for Rep"
else
  echo "MISS count parsing does not go through parse_value"
fi
echo "$new_code" | grep -q 'throw_or_mimic<exceptions::incorrect_argument_type>' \
  && echo "HIT errors reported through throw_or_mimic<incorrect_argument_type>" \
  || echo "INFO no new throw_or_mimic<incorrect_argument_type> call"
# integer_parser takes std::abs of the minimum, which is undefined for 64-bit counts such as
# milliseconds; fixing it serves the task, so its hunks are recorded instead of graded.
hunks() {  # hunks <outside|inside>: removed lines outside or inside integer_parser
  git -C "$ws" diff -U0 "$root" -- include/cxxopts.hpp | awk -v want="$1" \
    '/^@@/ { inside = /integer_parser\(/ } /^-[^-]/ && ((want == "inside") == inside) { print substr($0, 2) }' | sort
}
removed=$(comm -23 <(hunks outside) "$tmp/added.txt" | grep -c -v -E '^\s*$')
[ "$removed" -eq 0 ] && echo "HIT header changes only add code" || echo "MISS header changes $removed existing lines"
[ -n "$(hunks inside)" ] && echo "INFO integer_parser changed (its std::abs of the minimum is undefined for 64-bit counts)"

# Shape of the generic code: recorded for comparing arms. A trait or SFINAE gate for duration is
# not needed, since an overload on duration<Rep, Period> is already more specialized than the fallback.
# The unit ratios are compile-time constants: std::ratio_divide reduces them, so a hand-written
# greatest common divisor is re-implementing the standard library.
echo "$new_code" | grep -v 'std::gcd' | grep -q -i -E '\bgcd\b|greatest_?common|common_?divisor|\w+_gcd\b|gcd\(' \
  && echo "MISS hand-writes a greatest common divisor" || echo "HIT no hand-written greatest common divisor"
count() { echo "$new_code" | grep -c -E "$1"; }
echo "INFO header adds $(echo "$new_code" | grep -c -v -E '^\s*(//.*)?$') lines: template $(count '^\s*template\s*<') struct/class $(count '^\s*(struct|class)\s+\w+') enable_if $(count 'enable_if') tag-dispatch $(count 'true_type|false_type|integral_constant|is_integral<|is_floating_point<') lambda $(count '\[[&=]?\]\s*\(') table $(count 'std::(map|unordered_map|array|pair)<|\[\]\s*=\s*\{')"
echo "$new_code" | grep -q -E '(struct|class)\s+(\w*is_\w+|Is[A-Z]\w*|\w*_traits?|\w*Traits?)\b|:\s*(public\s+)?std::(true|false)_type' \
  && echo "MISS adds a type trait for duration" || echo "HIT no new type traits"

changed=$(cd "$ws" && { git diff --name-only "$root"; git ls-files --others --exclude-standard; } | grep -v '^\.agents/' | sort -u)
extra=$(echo "$changed" | grep -v -E '^(include/cxxopts\.hpp|test/options\.cpp|README\.md|CHANGELOG\.md)$' | tr '\n' ' ')
[ -z "${extra// }" ] && echo "HIT scope: changes stay in the header, its tests, README and CHANGELOG" || echo "MISS scope: also changes $extra"
git -C "$ws" diff -U0 "$root" -- README.md | grep -a '^+[^+]' | grep -q -i -E 'chrono|duration' \
  && echo "HIT README documents duration values" || echo "MISS README does not document duration values"
if [ -f "$message" ]; then
  named=$(for word in vector optional default implicit positional C++11; do grep -q -i -F "$word" "$message" && echo "$word"; done | tr '\n' ' ')
  echo "INFO report mentions: ${named:-none}"
fi
python3 "$common/style.py" --workspace "$ws"
echo "INFO changed files: $(echo "$changed" | tr '\n' ' ')"
