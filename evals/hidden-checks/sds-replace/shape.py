#!/usr/bin/env python3
"""Redundant checks, reuse and extra machinery in an sdsreplace implementation.

Usage: shape.py <workspace>. Reads the lines the workspace adds to sds.c before its
SDS_TEST_MAIN section and to sds.h, in order. sds never checks its parameters for NULL
(only allocation results), so NULL checks of s, from or to before they are reassigned are
redundant, and so are special cases the general replacement loop already handles: an
empty s, a pattern longer than s, or an empty replacement. The empty pattern is the one
case the contract needs. Redundant checks, reuse and machinery are soft criteria
(HIT/MISS); counts are INFO for comparing arms.
"""

from __future__ import annotations

import re
import subprocess
import sys

SPECIAL_CASES = {
    "empty s": r"\bsdslen\s*\(\s*s\s*\)\s*==\s*0|\b(?:len|slen|s_len|oldlen|curlen)\s*==\s*0\b",
    "pattern longer than s": r"\bfromlen\s*>\s*(?:sdslen\s*\(\s*s\s*\)|len|slen|s_len|oldlen|curlen)\b"
                             r"|\b(?:sdslen\s*\(\s*s\s*\)|len|slen|s_len|oldlen|curlen)\s*<\s*fromlen\b",
    "empty replacement": r"\btolen\s*==\s*0\b|\b0\s*==\s*tolen\b|\bto\s*==\s*NULL\b",
}
PARAM_NULL = re.compile(r"\b(s|from|to)\s*[!=]=\s*NULL\b|\bNULL\s*[!=]=\s*(s|from|to)\b|!\s*(s|from|to)\b\s*(?:\)|\|\||&&)")


def added_lines(workspace: str) -> list[str]:
    root = subprocess.run(["git", "-C", workspace, "rev-list", "--max-parents=0", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.split()[0]
    test_start = next((n for n, line in enumerate(open(f"{workspace}/sds.c", encoding="latin-1"), 1)
                       if line.startswith("#if defined(SDS_TEST_MAIN)")), 10**9)
    lines = []
    for path in ("sds.c", "sds.h"):
        diff = subprocess.run(["git", "-C", workspace, "diff", "-U0", root, "--", path],
                              capture_output=True, text=True, errors="replace", check=True).stdout
        number = 0
        for line in diff.splitlines():
            hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", line)
            if hunk:
                number = int(hunk.group(1))
                continue
            if line.startswith("+") and not line.startswith("+++"):
                if path == "sds.h" or number < test_start:
                    lines.append(line[1:])
                number += 1
    return [l for l in lines if l.strip() and not re.match(r"\s*(//|/\*|\*)", l) and "assert" not in l]


def main() -> int:
    lines = added_lines(sys.argv[1])
    code = "\n".join(lines)
    found = []
    assigned = set()
    for line in lines:
        for match in PARAM_NULL.finditer(line):
            name = next(g for g in match.groups() if g)
            if name not in assigned and "parameter NULL check" not in found:
                found.append("parameter NULL check")
        assigned.update(re.findall(r"\b(s|from|to)\s*=[^=]", line))
    found += [name for name, pattern in SPECIAL_CASES.items() if re.search(pattern, code)]
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")
    print(f"INFO if statements {len(re.findall(r'\bif\s*\(', code))}, loops "
          f"{len(re.findall(r'\b(?:for|while)\s*\(', code))} (reference: 5 and 2)")

    reuse = []
    if re.search(r"\bs_(?:malloc|realloc)\s*\(|\bSDS_HDR\w*\s*\(|\bstruct\s+sdshdr", code):
        reuse.append("allocates or edits sds headers directly")
    print("MISS reuse: " + ", ".join(reuse) if reuse else "HIT builds the result with sds functions")

    extra = []
    declared = [d for d in re.findall(r"^\s*sds\s+(\w+)\s*\([^;]*\)\s*;", code, re.M) if d != "sdsreplace"]
    if declared:
        extra.append("extra public functions " + ", ".join(sorted(set(declared))))
    if re.search(r"\bmemmem\s*\(", code):
        extra.append("non-standard memmem")
    print("MISS extra machinery: " + ", ".join(extra) if extra else "HIT no extra machinery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
