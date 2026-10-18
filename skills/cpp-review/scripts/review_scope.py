#!/usr/bin/env python3
"""Describe a Git review scope without fetching, staging, or choosing a base."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys

if __name__ == "__main__" and sys.version_info < (3, 10):
    sys.exit("review_scope: Python 3.10 or newer is required")


class ScopeError(Exception):
    pass


def git(repo, *args):
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", str(repo), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        raise ScopeError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout.decode("utf-8", "surrogateescape")


def resolve(repo, ref):
    return git(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}").strip()


def paths(repo, *args):
    return [path for path in git(repo, *args).split("\0") if path]


def layer(repo, name, args):
    prefix = ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--ignore-submodules=none"]
    return {
        "name": name,
        "paths": paths(repo, *prefix, "--name-only", "-z", *args, "--"),
        "patch_command": shlex.join(
            ["git", "--no-optional-locks", "-C", str(repo), *prefix, "--binary", *args, "--"]
        ),
    }


def build_scope(repo, scope, base=None, head="HEAD"):
    if scope not in {"all", "branch", "worktree"}:
        raise ScopeError("unknown scope")
    if scope in {"all", "branch"} and not base:
        raise ScopeError("--base is required for branch/all; no default base is inferred")
    if scope == "worktree" and (base is not None or head != "HEAD"):
        raise ScopeError("worktree scope only accepts the current HEAD and no --base")

    root = Path(git(repo, "rev-parse", "--show-toplevel").rstrip("\n"))
    current = resolve(root, "HEAD")
    selected = resolve(root, head)
    if scope == "all" and selected != current:
        raise ScopeError("all scope requires --head to resolve to the current HEAD")

    report = {
        "repository": str(root),
        "scope": scope,
        "head_ref": head,
        "head_commit": selected,
        "current_head_commit": current,
        "layers": [],
        "notes": [
            "This is a scope inventory, not a completed review or an atomic filesystem snapshot.",
            "Renames are listed as old and new paths so neither side is lost.",
            "Untracked contents and nested submodule diffs require separate inspection.",
        ],
    }

    if scope in {"branch", "all"}:
        base_commit = resolve(root, base)
        common = git(root, "merge-base", "--all", base_commit, selected).splitlines()
        if len(common) != 1:
            raise ScopeError("a unique merge base is required; clarify the review range")
        report.update(base_ref=base, base_commit=base_commit, merge_base=common[0])
        report["layers"].append(layer(root, "committed", [common[0], selected]))

    if scope in {"worktree", "all"}:
        conflicts = paths(root, "diff", "--name-only", "--diff-filter=U", "-z", "--")
        report["unmerged_paths"] = conflicts
        report["layers"].append(layer(root, "staged", ["--cached", current]))
        report["layers"].append(layer(root, "unstaged", []))
        report["layers"].append({
            "name": "untracked",
            "paths": paths(root, "ls-files", "--others", "--exclude-standard", "-z", "--"),
            "patch_command": None,
        })
        if conflicts:
            report["notes"].append("Unmerged paths exist; staged/unstaged output is not a resolved patch.")

    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="worktree to inspect")
    parser.add_argument("--scope", choices=["all", "branch", "worktree"], default="all")
    parser.add_argument("--base", help="explicit PR/MR base or chosen baseline")
    parser.add_argument("--head", default="HEAD", help="commit/ref; non-current heads need branch scope")
    args = parser.parse_args()
    try:
        report = build_scope(args.repo, args.scope, args.base, args.head)
    except (ScopeError, OSError) as error:
        print(f"review_scope: {error}", file=sys.stderr)
        return 2
    # ASCII escaping preserves arbitrary filesystem names as valid JSON.
    print(json.dumps(report, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
