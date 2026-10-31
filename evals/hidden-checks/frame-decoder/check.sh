#!/usr/bin/env bash
# Reviewer-only checks for the frame-decoder fixture. Usage: check.sh <workspace>
# CXX must support AddressSanitizer; the fuzz step also needs Clang's -fsanitize=fuzzer.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
san="-fsanitize=address,undefined -fno-sanitize-recover=all"
export ASAN_OPTIONS="max_allocation_size_mb=16:allocator_may_return_null=0"
grep -n "reinterpret_cast" "$ws/decoder.hpp" >/dev/null && echo "FAIL decoder still reinterprets raw bytes as a struct" || echo "PASS no reinterpret_cast of wire bytes"
$CXX -std=c++20 -Wall -Wextra -Werror -g $san -I"$ws" "$here/hidden_test.cc" -o "$tmp/hidden" 2>"$tmp/log" \
  || { echo "FAIL hidden test does not compile"; head -5 "$tmp/log"; exit 0; }
out=$(timeout 60 "$tmp/hidden" 2>&1); code=$?
echo "$out" | grep -E "^(PASS|FAIL) |hidden decoder" | sed 's/^/  /'
[ "$code" -eq 0 ] || echo "FAIL hidden test exited $code $(echo "$out" | grep -o -m1 'AddressSanitizer: [a-z-]*\|runtime error: [^:]*')"
if $CXX -std=c++20 -g -O1 -fsanitize=fuzzer,address,undefined -I"$ws" "$here/fuzz_decoder.cc" -o "$tmp/fuzz" 2>/dev/null; then
  (cd "$tmp" && timeout 60 ./fuzz -max_total_time=20 -rss_limit_mb=512 >fuzz.log 2>&1) && echo "PASS 20s fuzzing found no crash" \
    || echo "FAIL fuzzing: $(grep -o -m1 'ERROR: [A-Za-z]*Sanitizer: [a-z-]*\|out-of-memory\|runtime error: [^:]*' "$tmp/fuzz.log")"
else
  echo "SKIP fuzzing (compiler lacks -fsanitize=fuzzer)"
fi
