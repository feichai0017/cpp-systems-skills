#!/usr/bin/env python3
"""Shared reviewer checks for fixtures imported from real legacy repositories.

includes: compares the headers that project files include directly, using the
compiler's -H trace, and fails on new C++ library headers.
scope: fails when a file's diff against the imported commit changes existing
lines outside the allowed regions.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

C_COMPATIBLE = {"cassert", "cctype", "cerrno", "cfloat", "climits", "clocale", "cmath", "csetjmp", "csignal",
                "cstdarg", "cstddef", "cstdio", "cstdlib", "cstring", "ctime", "new"}


def direct_system_includes(cxx: str, root: Path, source: str, flags: list[str]) -> set[str]:
    result = subprocess.run([cxx, "-H", "-fsyntax-only", f"-I{root}", *flags, str(root / source)],
                            text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"{source} does not compile: {result.stderr.strip().splitlines()[:3]}")
    root_text = str(root.resolve())
    stack = [str((root / source).resolve())]
    found: set[str] = set()
    for line in result.stderr.splitlines():
        match = re.match(r"^(\.+) (.+)$", line)
        if not match:
            continue
        depth, path = len(match.group(1)), os.path.realpath(match.group(2))
        del stack[depth:]
        parent = stack[depth - 1] if depth - 1 < len(stack) else ""
        if parent.startswith(root_text) and not path.startswith(root_text):
            found.add(os.path.basename(path))
        stack.append(path)
    return found


def check_includes(args: argparse.Namespace) -> None:
    flags = args.flag or []
    for source in args.sources:
        try:
            original = direct_system_includes(args.cxx, Path(args.original), source, flags)
            current = direct_system_includes(args.cxx, Path(args.workspace), source, flags)
        except RuntimeError as error:
            print(f"FAIL {args.label}: {error}")
            continue
        added = sorted(name for name in current - original if not name.endswith(".h") and name not in C_COMPATIBLE)
        if added:
            print(f"FAIL {args.label}: {source} now includes C++ library headers {', '.join(added)}")
        else:
            print(f"PASS {args.label}: {source} includes no new C++ library headers")


def git(workspace: str, *cmd: str) -> str:
    return subprocess.run(["git", "-C", workspace, *cmd], text=True, capture_output=True, check=True).stdout


def allowed_regions(lines: list[str], start: str | None, end: str) -> list[tuple[int, int]]:
    regions = []
    if not start:
        return regions
    for index, line in enumerate(lines):
        if re.search(start, line):
            for stop in range(index + 1, len(lines)):
                if re.search(end, lines[stop]):
                    regions.append((index + 1, stop + 1))
                    break
    return regions


def check_scope(args: argparse.Namespace) -> None:
    root = git(args.workspace, "rev-list", "--max-parents=0", "HEAD").split()[0]
    original = git(args.workspace, "show", f"{root}:{args.file}").splitlines()
    regions = allowed_regions(original, args.start, args.end)
    diff = git(args.workspace, "diff", "-U0", root, "--", args.file)
    offending = []
    for match in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@", diff, re.M):
        first, count = int(match.group(1)), int(match.group(2) if match.group(2) is not None else 1)
        if count == 0:
            if not args.allow_insertions and not any(lo <= first <= hi for lo, hi in regions):
                offending.append(f"insertion after line {first}")
            continue
        last = first + count - 1
        if not any(lo <= first and last <= hi for lo, hi in regions):
            offending.append(f"lines {first}-{last} ({original[first - 1].strip()[:50]!r})")
    if offending:
        print(f"FAIL {args.label}: {args.file} changes existing code outside the task: {'; '.join(offending[:5])}")
    else:
        print(f"PASS {args.label}: {args.file} changes stay within the task")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    includes = sub.add_parser("includes")
    includes.add_argument("--cxx", required=True)
    includes.add_argument("--original", required=True)
    includes.add_argument("--workspace", required=True)
    includes.add_argument("--label", required=True)
    includes.add_argument("--flag", action="append")
    includes.add_argument("sources", nargs="+")
    scope = sub.add_parser("scope")
    scope.add_argument("--workspace", required=True)
    scope.add_argument("--file", required=True)
    scope.add_argument("--label", required=True)
    scope.add_argument("--start", help="regex of the first line of an allowed region")
    scope.add_argument("--end", default=r"^}", help="regex of the last line of an allowed region")
    scope.add_argument("--allow-insertions", action="store_true", help="accept pure insertions anywhere")
    args = parser.parse_args()
    if args.command == "includes":
        check_includes(args)
    else:
        check_scope(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
