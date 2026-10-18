#!/usr/bin/env python3
"""Validate skill packaging, local links and Codex UI metadata (not model behavior)."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

if __name__ == "__main__" and sys.version_info < (3, 10):
    sys.exit("validate: Python 3.10 or newer is required")

import yaml


ROOT = Path(__file__).resolve().parents[1]


def validate(root):
    errors = []
    skills = sorted((root / "skills").glob("*/SKILL.md"))
    if not skills:
        errors.append("no skills found")
    for entry in skills:
        label = str(entry.relative_to(root))
        content = entry.read_text(encoding="utf-8")
        parts = content.split("---\n", 2)
        if len(parts) != 3 or parts[0]:
            errors.append(f"{label}: frontmatter delimiters are missing")
            continue
        try:
            metadata = yaml.safe_load(parts[1])
        except yaml.YAMLError as error:
            errors.append(f"{label}: {error}")
            continue
        if not isinstance(metadata, dict):
            errors.append(f"{label}: frontmatter must be a mapping")
            continue
        name = metadata.get("name", "")
        if not isinstance(name, str) or name != entry.parent.name or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
            errors.append(f"{label}: invalid or mismatched name")
        description = metadata.get("description", "")
        if not isinstance(description, str) or not description.strip() or len(description) > 1024 or "<" in description or ">" in description:
            errors.append(f"{label}: invalid description")
        if not parts[2].strip():
            errors.append(f"{label}: empty skill body")
        if len(content.splitlines()) > 200:
            errors.append(f"{label}: entrypoint exceeds this collection's 200-line budget")
        try:
            config = yaml.safe_load((entry.parent / "agents" / "openai.yaml").read_text(encoding="utf-8"))
            policy = config.get("policy") if isinstance(config, dict) else None
            if not isinstance(policy, dict) or policy.get("allow_implicit_invocation") is not True:
                errors.append(f"{label}: collection skills must explicitly allow implicit invocation")
            interface = config["interface"]
            if not isinstance(interface.get("display_name"), str) or not interface["display_name"].strip():
                errors.append(f"{label}: missing display name")
            short = interface.get("short_description", "")
            if not isinstance(short, str) or not 25 <= len(short) <= 64:
                errors.append(f"{label}: UI description must contain 25-64 characters")
            prompt = interface.get("default_prompt", "")
            if not isinstance(prompt, str) or f"${name}" not in prompt:
                errors.append(f"{label}: UI prompt must invoke the skill")
        except (OSError, yaml.YAMLError, TypeError, KeyError) as error:
            errors.append(f"{label}: invalid UI metadata: {error}")

    for doc in sorted(root.rglob("*.md")):
        relative = doc.relative_to(root)
        if any(part.startswith(".") for part in relative.parts):
            continue
        # Only this directory is copied when a skill is installed on its own.
        link_root = root
        if len(relative.parts) >= 3 and relative.parts[0] == "skills":
            link_root = root / relative.parts[0] / relative.parts[1]
        text = doc.read_text(encoding="utf-8")
        # Links in these authored documents use plain Markdown link destinations.
        for target in re.findall(r"\[[^\]]+\]\(([^\s)]+)\)", text):
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith("#"):
                continue
            path = (doc.parent / unquote(parsed.path)).resolve()
            if not path.is_relative_to(link_root.resolve()):
                errors.append(f"{relative}: local link leaves package boundary: {target}")
            elif not path.exists():
                errors.append(f"{relative}: broken local link: {target}")
        if re.search(r"^\s*\[(?:TODO|TBD):", text, re.MULTILINE):
            errors.append(f"{doc.relative_to(root)}: unfinished scaffold placeholder")
    return errors, len(skills)


if __name__ == "__main__":
    failures, count = validate(ROOT)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print(f"Validated {count} skill packages and local Markdown links.")
