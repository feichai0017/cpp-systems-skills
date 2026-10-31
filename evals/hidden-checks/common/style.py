#!/usr/bin/env python3
"""Size and naming signals for a workspace's source changes against the imported commit.

Reports, for files that are not tests: added lines, new functions, added null guards,
and new names that start with a defensive verb (ensure, try, maybe, safe, checked,
validate, do, handle, process) or are long. Only the prefix rule is graded (HIT/MISS);
the rest is INFO for comparing arms.
"""

from __future__ import annotations

import argparse
import re
import subprocess

KEYWORDS = {"if", "while", "for", "switch", "return", "sizeof", "else", "case", "do", "defined", "catch"}
DEFENSIVE = re.compile(r"^(?:[Ee]nsure|[Tt]ry|[Mm]aybe|[Ss]afe|[Cc]hecked|[Vv]alidate|[Dd]o|[Hh]andle|[Pp]rocess)(?:_|[A-Z0-9]|$)")
FUNCTION = re.compile(r"^(?!\s*(?:return|else|if|while|for|switch)\b)[\w:<>*&\s]*?\b([A-Za-z_]\w*)\s*\([^;]*$")
VARIABLE = re.compile(r"\b(?:bool|char|int|long|short|unsigned|signed|float|double|size_t|auto|void|"
                      r"[A-Z][A-Za-z0-9_]*|std::\w+(?:<[^;>]*>)?)\s*[*&]*\s+([A-Za-z_]\w*)\s*(?=[=;,\[)])")
NULL_GUARD = re.compile(r"\bif\s*\(\s*!\s*[A-Za-z_][\w.\->]*\s*(\)|\|\||&&)|(==|!=)\s*(NULL|nullptr)\b")


def git(workspace: str, *args: str) -> str:
    return subprocess.run(["git", "-C", workspace, *args], capture_output=True, check=True).stdout.decode("latin-1")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--strip-prefix", default="", help="regex of the project's symbol prefix, removed before naming checks")
    parser.add_argument("--long", type=int, default=24, help="names at least this long are listed")
    args = parser.parse_args()

    root = git(args.workspace, "rev-list", "--max-parents=0", "HEAD").split()[0]
    # The runner stages new files before grading, so they appear in this diff.
    diff = git(args.workspace, "diff", "-U0", root, "--", ".", ":(exclude).agents")
    added, functions, names, guards = 0, [], set(), 0
    for chunk in re.split(r"^diff --git ", diff, flags=re.M)[1:]:
        path = chunk.split("\n", 1)[0].split(" b/")[-1]
        if re.search(r"test", path, re.I) or not re.search(r"\.(c|cc|cpp|cxx|h|hh|hpp)$", path):
            continue
        removed = "\n".join(l[1:] for l in chunk.splitlines() if l.startswith("-") and not l.startswith("---"))
        for line in (l[1:] for l in chunk.splitlines() if l.startswith("+") and not l.startswith("+++")):
            if not line.strip() or re.match(r"\s*(//|/\*|\*|#)", line):
                continue
            added += 1
            guards += bool(NULL_GUARD.search(line))
            match = FUNCTION.match(line)
            if match and match.group(1) not in KEYWORDS and not line.startswith((" ", "\t")):
                if not re.search(r"\b%s\s*\(" % re.escape(match.group(1)), removed):
                    functions.append(match.group(1))
            for name in [m.group(1) for m in VARIABLE.finditer(line)] + functions[-1:]:
                if name not in KEYWORDS and not re.search(r"\b%s\b" % re.escape(name), removed):
                    names.add(name)
    # Names the original repository already uses anywhere follow its convention, not the change.
    names = {name for name in names
             if subprocess.run(["git", "-C", args.workspace, "grep", "-q", "-w", "-F", name, root, "--"],
                               capture_output=True).returncode != 0}
    functions = [name for name in functions if name in names]
    stripped = {name: re.sub(r"^(%s)" % args.strip_prefix, "", name) if args.strip_prefix else name for name in names}
    defensive = sorted(name for name, bare in stripped.items() if DEFENSIVE.match(bare))
    long_names = sorted(name for name, bare in stripped.items() if len(bare) >= args.long)
    print(f"INFO source lines added (excluding tests): {added}")
    print(f"INFO new functions ({len(set(functions))}): {', '.join(sorted(set(functions))) or 'none'}")
    print(f"INFO added null guards: {guards}")
    print(f"INFO long new names: {', '.join(long_names) or 'none'}")
    print("MISS new names with defensive verb prefixes: " + ", ".join(defensive) if defensive
          else "HIT new names without defensive verb prefixes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
