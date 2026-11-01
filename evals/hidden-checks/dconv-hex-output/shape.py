#!/usr/bin/env python3
"""Redundant checks, reuse and extra machinery in a ToHexadecimal implementation.

Reads the new code of double-to-string.{h,cc} on stdin (added lines, moved lines removed).
The task states no preconditions; double-conversion's public methods never check their
StringBuilder pointer, StringBuilder asserts its own capacity, and Double's fields bound
the exponent and the hex digits. Checks of those, and special values tested more than
once, are redundant. Redundant checks, reuse and machinery are soft criteria (HIT/MISS);
counts are INFO for comparing arms.
"""

from __future__ import annotations

import re
import sys

REDUNDANT = {
    "null builder check": r"\b\w*builder\w*\s*[!=]=\s*(?:NULL|nullptr|DOUBLE_CONVERSION_NULLPTR|0)\b"
                          r"|(?:NULL|nullptr|DOUBLE_CONVERSION_NULLPTR)\s*[!=]=\s*\w*builder\b|!\s*\w*builder\w*\s*\)",
    "builder capacity check": r"position\(\)\s*(?:[+<>]|>=|<=)|\bsize_?\s*-\s*\w*position|kMaxHexLength\s*[<>]",
    # The exponent of a finite double and a 4-bit digit cannot leave their ranges.
    "impossible range check": r"\b\w*exp\w*\s*(?:<|>|<=|>=)\s*-?(?:102[0-9]|107[0-9]|204[0-9])\b"
                              r"|\b(?:digit|nibble)\w*\s*(?:>|>=)\s*1[56]\b",
}

SPECIAL = r"\bIsSpecial\s*\(|\bIsNan\s*\(|\bIsInfinite\s*\(|\bstd::isnan\b|\bstd::isinf\b|\bisnan\s*\(|\bisinf\s*\(|\bstd::isfinite\b|\bvalue\s*!=\s*value\b"


def main() -> int:
    code = "\n".join(line for line in sys.stdin.read().splitlines()
                     if line.strip() and not re.match(r"\s*(//|/\*|\*)", line))
    # The project states internal invariants with DOUBLE_CONVERSION_ASSERT; those are not checks.
    checks = "\n".join(line for line in code.splitlines() if "ASSERT" not in line)
    found = [name for name, pattern in REDUNDANT.items() if re.search(pattern, checks, re.M)]
    special = len(re.findall(SPECIAL, code))
    if special > 1:
        found.append(f"special values tested {special} times")
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")
    print(f"INFO if statements {len(re.findall(r'\bif\s*\(', code))}, loops "
          f"{len(re.findall(r'\b(?:for|while)\s*\(', code))} (reference: 6 and 3)")

    reuse = []
    if not re.search(r"\bHandleSpecialValues\s*\(", code):
        reuse.append("special values not through HandleSpecialValues")
    if re.search(r"\b(?:infinity|nan)_symbol_\b", code):
        reuse.append("uses the symbols directly")
    if re.search(r"\bmemcpy\s*\(|\breinterpret_cast\s*<|\bunion\b", code):
        reuse.append("reads the bits without Double")
    print("MISS reuse: " + ", ".join(reuse) if reuse else "HIT reuses HandleSpecialValues and Double")

    extra = []
    if re.search(r"\b(?:s?n?printf|ostringstream|stringstream|std::string|to_string)\b", code):
        extra.append("formats through the C or C++ library")
    if re.search(r"^\s*template\s*<", code, re.M):
        extra.append("templates")
    methods = sorted(set(re.findall(r"\bbool\s+(To\w+)\s*\(", code)) - {"ToHexadecimal"})
    if methods:
        extra.append("extra public methods " + ", ".join(methods))
    print("MISS extra machinery: " + ", ".join(extra) if extra else "HIT no extra machinery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
