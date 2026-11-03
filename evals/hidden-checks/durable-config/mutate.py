#!/usr/bin/env python3
"""Reviewer-only: rewrites the FileSystem calls of one step so that their errors are ignored.

Usage: mutate.py <config_store.hpp> <write|file-sync|rename|directory-sync>. Each call of
the step becomes (call, std::error_code{}): the step still runs but reports success. A Sync
whose argument names a directory (dir, directory, parent) is the directory sync; when none
does, the last of several Sync calls is. Prints the mutated header, or exits 2 when the step
has no call. The workspace's own tests detect the step's failure path when they fail
against the mutant.
"""

from __future__ import annotations

import re
import sys

METHOD = {"write": "Write", "file-sync": "Sync", "rename": "Rename", "directory-sync": "Sync"}


def calls(source: str, method: str) -> list[tuple[int, int, str]]:
    """(start, end, argument text) of each `receiver.method(...)` call."""
    found = []
    for match in re.finditer(rf"\b[A-Za-z_][\w.]*(?:->[\w.]+)*\s*(?:\.|->)\s*{method}\s*\(", source):
        depth = 0
        for end in range(match.end() - 1, len(source)):
            depth += {"(": 1, ")": -1}.get(source[end], 0)
            if depth == 0:
                found.append((match.start(), end + 1, source[match.end():end]))
                break
    return found


def main() -> int:
    source = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    step = sys.argv[2]
    found = calls(source, METHOD[step])
    if METHOD[step] == "Sync":
        directory = [c for c in found if re.search(r"dir|parent", c[2], re.I)]
        if not directory and len(found) > 1:
            directory = found[-1:]
        found = directory if step == "directory-sync" else [c for c in found if c not in directory]
    if not found:
        return 2
    for start, end, _ in sorted(found, reverse=True):
        source = source[:start] + f"({source[start:end]}, std::error_code{{}})" + source[end:]
    sys.stdout.write(source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
