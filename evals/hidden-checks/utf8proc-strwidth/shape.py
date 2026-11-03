#!/usr/bin/env python3
"""Redundant checks, reuse and extra machinery in a utf8proc_strwidth implementation.

Reads the new code of utf8proc.{c,h} on stdin (added lines, moved lines removed). The task
states no preconditions, and utf8proc's signals are mixed: utf8proc_decompose accepts a
NULL buffer to query a size, but utf8proc_iterate and the other string readers dereference
str without checking it. A NULL check of str, a special case for strlen == 0 (the loop
handles it), re-validating a codepoint utf8proc_iterate already accepted, a negative
utf8proc_charwidth check (it returns 0, 1 or 2) and overflow checks on a width bounded by
the input are redundant. Redundant checks, reuse and machinery are soft criteria (HIT/MISS);
counts are INFO for comparing arms.
"""

from __future__ import annotations

import re
import sys


def main() -> int:
    code = "\n".join(line for line in sys.stdin.read().splitlines()
                     if line.strip() and not re.match(r"\s*(//|/\*|\*)", line) and "assert" not in line)
    found = []
    if re.search(r"\bstr\s*[!=]=\s*NULL\b|\bNULL\s*[!=]=\s*str\b|!\s*str\b\s*(?:\)|\|\||&&)", code):
        found.append("str NULL check")
    if re.search(r"\bstrlen\s*==\s*0\b|\b0\s*==\s*strlen\b|!\s*strlen\b", code):
        found.append("zero-length special case")
    codepoints = set(re.findall(r"utf8proc_iterate\s*\([^;]*?&\s*(\w+)\s*\)", code))
    if re.search(r"\butf8proc_codepoint_valid\s*\(", code) or any(
            re.search(rf"\b{re.escape(v)}\s*(?:<\s*0|==\s*-1|<=\s*-1)", code) for v in codepoints):
        found.append("codepoint re-validated after utf8proc_iterate")
    widths = set(re.findall(r"(\w+)\s*=\s*utf8proc_charwidth\s*\(", code))
    if re.search(r"utf8proc_charwidth\s*\([^)]*\)\s*<\s*0", code) or any(
            re.search(rf"\b{re.escape(v)}\s*<\s*0", code) for v in widths):
        found.append("negative width check")
    if re.search(r"\b(?:UTF8PROC_)?SSIZE_MAX\b|\bPTRDIFF_MAX\b|\bINTPTR_MAX\b", code):
        found.append("overflow check on the width")
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")
    print(f"INFO if statements {len(re.findall(r'\bif\s*\(', code))}, loops "
          f"{len(re.findall(r'\b(?:for|while)\s*\(', code))} (reference: 2 and 1)")
    reuse = []
    if not re.search(r"\butf8proc_iterate\s*\(", code):
        reuse.append("decodes UTF-8 without utf8proc_iterate")
    print("MISS reuse: " + ", ".join(reuse) if reuse else "HIT reads codepoints with utf8proc_iterate")
    extra = []
    if re.search(r"grapheme|ambiguous", code, re.I):
        extra.append("grapheme or ambiguous-width handling")
    if re.search(r"\b(?:malloc|calloc|realloc)\s*\(", code):
        extra.append("allocates")
    declared = sorted(set(re.findall(r"UTF8PROC_DLLEXPORT\s+[\w\s\*]+?\b(utf8proc_\w+)\s*\([^;{]*\)\s*;", code)) - {"utf8proc_strwidth"})
    if declared:
        extra.append("extra public functions " + ", ".join(declared))
    print("MISS extra machinery: " + ", ".join(extra) if extra else "HIT no extra machinery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
