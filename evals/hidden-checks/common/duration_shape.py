#!/usr/bin/env python3
"""Redundant checks and extra machinery in a std::chrono::duration value parser.

Reads the new code of a duration fixture on stdin (added lines, moved lines removed) and
reports checks that the contract or the reused parser already makes unnecessary, and
machinery the task does not need. Redundant checks are graded as one soft criterion
(HIT/MISS); the machinery is INFO for comparing arms.
"""

from __future__ import annotations

import re
import sys

# Checks whose condition is already settled elsewhere.
REDUNDANT = {
    # The reused count parser and the unit match already reject empty text.
    "empty-text check": r"\.empty\(\)|\.(?:size|length)\(\)\s*==\s*0|==\s*\"\"",
    # std::ratio keeps its denominator positive and duration requires a positive period.
    # A remainder compared with zero (count % R::den != 0) is the exactness test, not a sign check.
    "ratio or period sign check": r"(?<![%*/] )(?<![%*/])\b[A-Za-z_]\w*::(?:num|den)\s*(?:==|!=|<=|<|>)\s*0\b"
                                  r"|\b(?:num|den)\w*\s*==\s*0\b",
    # duration already requires an arithmetic Rep; asserting it again only rejects emulated types.
    "Rep arithmetic assertion": r"is_arithmetic\s*<",
    # Every arithmetic Rep has numeric_limits.
    "numeric_limits specialization check": r"\bis_(?:specialized|bounded)\b",
    # The reused parser decides what a count looks like; scanning first is validate-then-parse.
    "count pre-scan before parsing": r"\b(?:std::)?is(?:digit|space|alpha|alnum)\s*\(|find_first_(?:not_)?of|find_last_(?:not_)?of|\b(?:all|any|none)_of\s*\(",
    # duration<bool> is not a duration anyone writes.
    "bool count handling": r"is_same\s*<\s*Rep\s*,\s*bool\s*>|is_same\s*<\s*bool\s*,\s*Rep\s*>",
}

MACHINERY = {
    "unit enum": r"\benum\s+(?:class\s+)?\w*",
    "runtime ratio table": r"\{\s*\"(?:ns|us|ms|min|s|h)\"\s*,",
    "overflow helper": r"__builtin_\w+_overflow|\b\w*(?:[Mm]ul|[Mm]ultiply)\w*[Oo]verflow\w*\b|\b(?:[Cc]hecked|[Ss]afe)_?[Mm]ul\w*",
    "unsigned magnitude arithmetic": r"\b(?:magnitude|Magnitude)\b|make_unsigned",
    "std::intmax_t arithmetic": r"\b(?:std::)?u?intmax_t\b",
}


def main() -> int:
    code = "\n".join(line for line in sys.stdin.read().splitlines()
                     if line.strip() and not re.match(r"\s*(//|/\*|\*)", line))
    found = [name for name, pattern in REDUNDANT.items() if re.search(pattern, code)]
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")
    used = [name for name, pattern in MACHINERY.items() if re.search(pattern, code)]
    print(f"INFO extra machinery ({len(used)}): {', '.join(used) or 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
