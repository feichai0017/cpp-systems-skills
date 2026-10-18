#!/usr/bin/env python3
"""Copy selected local skills into a skill directory; never overwrite a destination."""

import argparse
from pathlib import Path
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]


def install(source, destination, selected=None, dry_run=False):
    available = {p.name: p for p in sorted(source.iterdir()) if (p / "SKILL.md").is_file()}
    names = list(dict.fromkeys(selected)) if selected else list(available)
    if not names:
        raise ValueError("no skills found")
    unknown = set(names) - set(available)
    if unknown:
        raise ValueError("unknown skills: " + ", ".join(sorted(unknown)))
    destination = destination.expanduser().resolve()
    if destination.is_relative_to(source.resolve()):
        raise ValueError("destination must be outside the source skills directory")
    if destination.exists() and not destination.is_dir():
        raise ValueError(f"destination is not a directory: {destination}")
    for name in names:
        target = destination / name
        if target.exists() or target.is_symlink():
            raise ValueError(f"destination already exists; nothing copied: {target}")
        origin = available[name]
        if origin.is_symlink() or any(p.is_symlink() for p in origin.rglob("*")):
            raise ValueError(f"source contains a symlink: {origin}")
    if not dry_run:
        destination.mkdir(parents=True, exist_ok=True)
        for name in names:
            shutil.copytree(
                available[name], destination / name,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
    return [destination / name for name in names]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, required=True, help="e.g. ~/.codex/skills")
    parser.add_argument("--skill", action="append", help="repeat to select skills; defaults to all")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        installed = install(ROOT / "skills", args.dest, args.skill, args.dry_run)
    except (ValueError, OSError) as error:
        print(f"install: {error}", file=sys.stderr)
        return 2
    for path in installed:
        print(f"{'Would install' if args.dry_run else 'Installed'}: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
