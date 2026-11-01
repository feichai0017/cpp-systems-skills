#!/usr/bin/env python3
"""Redundant checks and extra machinery in a jsmn_find implementation.

Reads the new code of jsmn.h on stdin (added lines, moved lines removed). The task
states what the caller guarantees: js and tokens come from one successful jsmn_parse,
count is its result, 0 <= object < count and key is NUL-terminated. Checks of those
conditions are redundant; the two checks the contract needs are the object type and
a key without a value. Redundant checks and extra machinery are graded as soft
criteria (HIT/MISS); counts are INFO for comparing arms.
"""

from __future__ import annotations

import re
import sys

POINTERS = r"(?:js|json|tokens|toks?|token|key|name|str|s)"
REDUNDANT = {
    "null pointer check": rf"\b{POINTERS}\s*[!=]=\s*(?:NULL|0|nullptr)\b|(?:NULL|nullptr)\s*[!=]=\s*{POINTERS}\b"
                          rf"|if\s*\(\s*!\s*{POINTERS}\s*(?:\)|\|\||&&)|\|\|\s*!\s*{POINTERS}\s*(?:\)|\|\|)",
    "count check": r"\b(?:count|num_tokens|ntok\w*)\s*(?:<=?|==)\s*[01]\b|(?<![+-] )(?<![+-])\b[01]\s*>=?\s*(?:count|num_tokens)\b",
    "object index range check": r"\bobject\s*(?:<\s*0|>=?\s*count)|\bcount\s*<=?\s*object\b|\bobject\s*\+\s*1\s*>=?\s*count",
    "token offset sanity check": r"\.(?:start|end)\s*<\s*0\b|\.end\s*<=?\s*[\w\[\]\.>()+-]*\.start\b",
    # A key with size > 0 has its value at the next index, inside the object; size == 0 says
    # there is none. Testing the next index against count or the object's end again is redundant.
    "value token re-checked against count or object end": r"\+\s*1\s*>=?\s*count\b|\bcount\s*<=?\s*\w+\s*\+\s*1\b"
                                                          r"|\+\s*1\]\s*(?:\.|->)start\s*>=?",
    "undefined token check": r"JSMN_UNDEFINED",
    "negative size check": r"\.size\s*<\s*0\b|\.size\s*<=\s*-",
    "empty key special case": r"if\s*\(\s*(?:\*key|key\[0\])\s*==\s*'\\0'\s*\)|strlen\s*\(\s*key\s*\)\s*==\s*0",
}


def main() -> int:
    code = "\n".join(line for line in sys.stdin.read().splitlines()
                     if line.strip() and not re.match(r"\s*(//|/\*|\*)", line))
    found = [name for name, pattern in REDUNDANT.items() if re.search(pattern, code, re.M)]
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")
    ifs = len(re.findall(r"\bif\s*\(", code))
    loops = len(re.findall(r"\b(?:for|while)\s*\(", code))
    print(f"INFO if statements {ifs}, loops {loops} (reference: 4 and 3)")
    extra = []
    if re.search(r"\b(?:malloc|calloc|realloc)\s*\(", code):
        extra.append("allocates")
    if "JSMN_PARENT_LINKS" in code:
        extra.append("separate parent-links path")
    api = [m for m in re.findall(r"JSMN_API\s+[\w\s\*]+?\b(\w+)\s*\(", code) if m != "jsmn_find"]
    if api:
        extra.append("extra public functions " + ", ".join(sorted(set(api))))
    print("MISS extra machinery: " + ", ".join(extra) if extra else "HIT no extra machinery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
