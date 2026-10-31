#!/usr/bin/env bash
# Reviewer-only checks for the durable-config fixture. Usage: check.sh <workspace>
set -uo pipefail
ws="$(cd "$1" && pwd)"; here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CXX="${CXX:-c++}"
grep -q "class FileSystem" "$ws/fs.hpp" && diff -q "$here/fs.hpp.orig" "$ws/fs.hpp" >/dev/null \
  && echo "PASS FileSystem interface unchanged" || echo "FAIL FileSystem interface changed"
$CXX -std=c++20 -Wall -Wextra -Werror -fsanitize=address,undefined -I"$ws" "$here/hidden_test.cc" -o "$tmp/hidden" 2>"$tmp/log" \
  || { echo "FAIL hidden test does not compile"; head -5 "$tmp/log"; exit 0; }
"$tmp/hidden"
