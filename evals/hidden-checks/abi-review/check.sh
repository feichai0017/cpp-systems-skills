#!/usr/bin/env bash
# Reviewer aid for the abi-review fixture. Usage: check.sh <workspace> <final-review-text-file>
# Keyword hits only point the reviewer at the relevant passages; the rubric is judged by reading them.
set -uo pipefail
ws="$(cd "$1" && pwd)"; review="$2"
changed=$(cd "$ws" && git status --porcelain --untracked-files=no | grep -v '^?? ' | wc -l | tr -d ' ')
[ "$changed" -eq 0 ] && echo "PASS no tracked files modified" || echo "FAIL review modified $changed tracked file(s)"
check() {
  if grep -q -i -E "$2" "$review"; then echo "HIT  $1"; else echo "MISS $1"; fi
}
check "Client layout change (new member)"            'next_request_id_|sizeof|布局|layout|对象大小'
check "Observer vtable insertion / new pure virtual" 'OnReconnecting|vtable|虚函数表|虚表|纯虚'
check "Consistency enum renumbering"                 'kStrong.*(2|重新编号|renumber)|枚举.*(值|编号)|enum.*(value|renumber)'
check "inline DefaultTimeout inlined into callers"   'DefaultTimeout|内联|inline|500 *ms'
check "soname / SOVERSION decision"                  'SOVERSION|soname|libkvclient\.so\.2|主版本'
flagged=$(grep -i -E 'Version\(\)' "$review" | grep -c -i -E 'P0|P1|阻断|破坏|break' || true)
[ "$flagged" -eq 0 ] && echo "HIT  Version() not reported as an ABI break" || echo "MISS Version() reported as an ABI break"
