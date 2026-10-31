#!/usr/bin/env bash
# Reviewer-only checks for the coro-lifetime fixture. Usage: check.sh <workspace>
# Set CXX to a compiler whose AddressSanitizer works on this host.
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
diff -q "$here/async.hpp.orig" "$ws/async.hpp" >/dev/null && echo "PASS async.hpp unchanged" || echo "FAIL async.hpp changed"
for test in visible hidden; do
  src="$ws/check.cc"; [ "$test" = hidden ] && src="$here/hidden_test.cc"
  $CXX -std=c++20 -Wall -Wextra -Werror -g -fsanitize=address -I"$ws" "$src" -o "$tmp/$test" 2>"$tmp/log" \
    || { echo "FAIL $test does not compile"; head -5 "$tmp/log"; continue; }
  out=$(timeout 30 "$tmp/$test" 2>&1); code=$?
  report=$(echo "$out" | grep -o -m1 "AddressSanitizer: [a-z-]*")
  [ "$code" -eq 0 ] && echo "PASS $test under ASan" || echo "FAIL $test under ASan (exit $code${report:+, $report})"
  [ "$test" = hidden ] && echo "$out" | grep -E "^(PASS|FAIL) " | sed 's/^/  /'
done
