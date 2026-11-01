#!/usr/bin/env python3
"""Redundant checks, conventions, extra machinery and test hooks in a SaveConfig fix.

Usage: shape.py <workspace>. Reads the code lines the workspace adds to config_store.hpp.
Failures arrive as std::error_code and OpenResult::error, so testing the fd besides the
error, special cases for empty text or path, and one fact tested by two conditions are
redundant. File access outside FileSystem breaks the project convention. The callers
(config_store.hpp and check.cc) save one file at a time, and a fixed temporary name opened
with kWriteTruncate already replaces a crash leftover, so unique temporary names (counters,
pids, random or clock values, name search loops) and retry loops are machinery no caller
needs. Test-only switches in the product header are hooks. Soft criteria (HIT/MISS);
counts are INFO for comparing arms.
"""

from __future__ import annotations

import re
import subprocess
import sys

REDUNDANT = {
    "fd tested besides the error": r"\.fd\s*(?:<|<=|==|!=|>=|>)\s*-?\d|\bfd\s*<\s*0\b",
    "empty text or path special case": r"\b(?:text|path)\s*\.\s*(?:empty\s*\(\)|size\s*\(\)\s*==\s*0)",
    "one fact tested twice": r"!\s*([\w.]+)\s*\|\|\s*\1\s*!=|\b([\w.]+)\s*&&\s*\2\s*==",
}
OUTSIDE = (r"std::(?:ofstream|ifstream|fstream)\b|\bfopen\s*\(|::(?:open|write|fsync|fdatasync|rename|unlink|close)\s*\("
           r"|std::filesystem::(?:exists|remove\w*|rename|create_\w+|status|is_\w+|temp_directory_path)\b"
           r"|std::(?:rename|remove)\s*\(")
NAMES = (r"getpid|\brand\s*\(|random|mt19937|std::chrono|\btime\s*\(|std::atomic"
         r"|to_string\s*\(\s*\w*(?:id|count|attempt|suffix|index|serial)\w*\s*\)")
LOOP = r"\b(?:for|while)\s*\(|\bdo\s*\{"
HOOKS = (r"#\s*if(?:def|ndef)?\b[^\n]*TEST|\bstd::function\b|\b\w*(?:fail|inject)\w*\s*=\s*(?:true|false|\d)"
         r"|failpoint|\bfault_\w+")


def added_code(workspace: str, path: str) -> list[str]:
    root = subprocess.run(["git", "-C", workspace, "rev-list", "--max-parents=0", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.split()[0]
    diff = subprocess.run(["git", "-C", workspace, "diff", "-U0", root, "--", path],
                          capture_output=True, text=True, errors="replace", check=True).stdout
    lines = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
    return [l for l in lines if l.strip() and not re.match(r"\s*(//|/\*|\*)", l)]


def main() -> int:
    lines = added_code(sys.argv[1], "config_store.hpp")
    code = "\n".join(lines)
    found = [name for name, pattern in REDUNDANT.items() if re.search(pattern, code)]
    print("MISS redundant checks: " + ", ".join(found) if found else "HIT no redundant checks")

    outside = re.search(OUTSIDE, code)
    print("MISS file access outside FileSystem: " + outside.group(0) if outside
          else "HIT all file access goes through FileSystem")

    extra = []
    if re.search(NAMES, code):
        extra.append("unique temporary names")
    if re.search(LOOP, code):
        extra.append("loops (name search or retries)")
    print("MISS extra machinery: " + ", ".join(extra) if extra else "HIT no extra machinery")

    hooks = re.search(HOOKS, code)
    print("MISS adds a test hook to config_store.hpp: " + hooks.group(0) if hooks else "HIT no test hooks in config_store.hpp")

    helpers = [n for n in re.findall(r"^\s*(?:inline\s+|static\s+)*[\w:<>]+[\s*&]+(\w+)\s*\([^;]*\)\s*(?:const\s*)?\{?\s*$",
                                     code, re.M) if n not in ("SaveConfig", "LoadConfig")]
    full = open(f"{sys.argv[1]}/config_store.hpp", encoding="utf-8", errors="replace").read()
    uses = ", ".join(f"{n}({len(re.findall(rf'\b{n}\s*\(', full)) - 1})" for n in dict.fromkeys(helpers))
    print(f"INFO helper functions (calls): {uses or '-'}; classes "
          f"{len(re.findall(r'^\s*(?:class|struct)\s+\w+', code, re.M))}, lambdas {len(re.findall(r'\[[&=]?\]\s*\(', code))}")
    print(f"INFO config_store.hpp adds {len(lines)} code lines (reference: 15); if statements "
          f"{len(re.findall(r'\bif\s*\(', code))}, Remove calls {len(re.findall(r'\.Remove\s*\(', code))} (reference: 4 and 1)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
