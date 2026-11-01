#!/usr/bin/env python3
"""Run one evaluation fixture with Codex in an isolated workspace.

The workspace and all run artifacts go to --out, which must be outside this
repository. The executor only receives the fixture files, the TASK.md text as
its prompt and, for the skills arm, a copy of the selected skills under
.agents/skills, taken from the working tree or from --skills-rev. Rubrics and
hidden checks are never copied into the workspace.

Codex runs with a temporary CODEX_HOME and HOME: the first holds only the login
and the model setting, the second is empty, so the user's memories, personal
skills (~/.codex/skills, ~/.agents/skills), AGENTS.md, plugins and MCP servers
reach neither arm. PATH is kept. --shared-home runs with the user's own homes.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "evals" / "fixtures"
HIDDEN = REPO / "evals" / "hidden-checks"
SKILLS = REPO / "skills"


def run(cmd: list[str], cwd: Path, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, check=True, text=True, capture_output=True, **kwargs)


def isolated_home(home: Path) -> None:
    """Fills home with the user's login and model, and nothing else from their Codex setup."""
    user_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    shutil.copy2(user_home / "auth.json", home / "auth.json")
    config = (user_home / "config.toml").read_text()
    model = re.search(r'^model\s*=\s*"[^"]*"', config, re.M)
    (home / "config.toml").write_text((model.group(0) + "\n" if model else "") + "\n[features]\nmemories = false\n")


def available_skills(rev: str | None) -> list[str]:
    if rev is None:
        return sorted(p.name for p in SKILLS.iterdir() if (p / "SKILL.md").exists())
    files = run(["git", "ls-tree", "-r", "--name-only", rev, "skills"], cwd=REPO).stdout.splitlines()
    return sorted(Path(f).parent.name for f in files if len(Path(f).parts) == 3 and Path(f).name == "SKILL.md")


def prepare_workspace(fixture: str, arm: str, skills: list[str], rev: str | None, workspace: Path) -> None:
    source = FIXTURES / fixture
    shutil.copytree(source, workspace)
    git_identity = ["-c", "user.name=eval", "-c", "user.email=eval@example.invalid"]
    setup = workspace / "setup.sh"
    if setup.exists():
        run(["bash", str(setup)], cwd=workspace)
    else:
        run(["git", "init", "-q"], cwd=workspace)
        run(["git", "add", "-A"], cwd=workspace)
        run(["git", *git_identity, "commit", "-q", "-m", f"fixture {fixture}"], cwd=workspace)
    exclude = workspace / ".git" / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    with exclude.open("a") as handle:
        # Keep installed skills and build outputs out of the reviewed diff.
        handle.write("/.agents/\n/build/\n/check\n*.o\n")
    if arm == "skills":
        target = workspace / ".agents" / "skills"
        target.mkdir(parents=True)
        if rev is None:
            for name in skills:
                shutil.copytree(SKILLS / name, target / name)
        else:
            archive = subprocess.run(["git", "archive", rev, *(f"skills/{name}" for name in skills)],
                                     cwd=REPO, check=True, capture_output=True).stdout
            subprocess.run(["tar", "-x", "-C", str(target.parent)], input=archive, check=True)


def collect_diff(workspace: Path) -> bytes:
    run(["git", "add", "-A"], cwd=workspace)
    # Bytes, because imported legacy sources are not always UTF-8.
    return subprocess.run(["git", "diff", "--cached", "HEAD"], cwd=workspace, check=True, capture_output=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("fixture", help="directory name under evals/fixtures")
    parser.add_argument("--arm", choices=["skills", "control"], required=True)
    parser.add_argument("--out", type=Path, required=True, help="run directory parent, outside the repository")
    parser.add_argument("--trial", type=int, default=1)
    parser.add_argument("--skills", default="all", help="comma-separated skill names, or 'all'")
    parser.add_argument("--skills-rev", help="install the skills as of this commit instead of the working tree")
    parser.add_argument("--effort", help="model_reasoning_effort override, for example high")
    parser.add_argument("--model", help="model override")
    parser.add_argument("--cxx", help="value of CXX in the executor's environment")
    parser.add_argument("--grade", action="store_true", help="run the fixture's hidden check afterwards")
    parser.add_argument("--dry-run", action="store_true", help="prepare the workspace without running Codex")
    parser.add_argument("--shared-home", action="store_true", help="run with the user's HOME and CODEX_HOME instead of temporary ones")
    args = parser.parse_args()

    if not (FIXTURES / args.fixture).is_dir():
        parser.error(f"unknown fixture: {args.fixture}")
    out = args.out.resolve()
    if out == REPO or REPO in out.parents:
        parser.error("--out must be outside the repository; run artifacts are not committed")
    if args.skills_rev and args.arm != "skills":
        parser.error("--skills-rev applies to the skills arm")
    rev = None
    if args.skills_rev:
        resolved = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{args.skills_rev}^{{commit}}"],
                                  cwd=REPO, text=True, capture_output=True)
        if resolved.returncode != 0:
            parser.error(f"unknown commit: {args.skills_rev}")
        rev = resolved.stdout.strip()
    available = available_skills(rev)
    skills = available if args.skills == "all" else [name.strip() for name in args.skills.split(",") if name.strip()]
    for name in skills:
        if name not in available:
            parser.error(f"unknown skill: {name}")

    arm = f"{args.arm}@{args.skills_rev}" if rev else args.arm
    run_dir = out / f"{args.fixture}-{arm}-{args.trial}"
    if run_dir.exists():
        parser.error(f"{run_dir} already exists; choose another --trial or remove it")
    workspace = run_dir / "workspace"
    run_dir.mkdir(parents=True)
    prepare_workspace(args.fixture, args.arm, skills if args.arm == "skills" else [], rev, workspace)
    if args.dry_run:
        print(workspace)
        return 0

    prompt = (workspace / "TASK.md").read_text()
    cmd = ["codex", "exec", "-C", str(workspace), "-s", "workspace-write", "--ephemeral", "--json",
           "-o", str(run_dir / "last_message.txt")]
    if args.effort:
        cmd += ["-c", f'model_reasoning_effort="{args.effort}"']
    if args.model:
        cmd += ["-m", args.model]
    cmd.append(prompt)
    env = dict(os.environ)
    if args.cxx:
        env["CXX"] = args.cxx

    with tempfile.TemporaryDirectory(prefix="codex-home-") as home:
        codex_env = dict(env)
        if not args.shared_home:
            isolated_home(Path(home))
            codex_env["CODEX_HOME"] = home
            codex_env["HOME"] = home
        started = time.time()
        with (run_dir / "events.jsonl").open("w") as events, (run_dir / "stderr.txt").open("w") as stderr:
            exit_code = subprocess.run(cmd, cwd=workspace, env=codex_env, stdout=events, stderr=stderr).returncode
        seconds = round(time.time() - started)
        refreshed = not args.shared_home and (Path(home) / "auth.json").read_bytes() != \
            Path(env.get("CODEX_HOME", Path.home() / ".codex"), "auth.json").read_bytes()
    if refreshed:
        print("warning: Codex refreshed the login inside the temporary CODEX_HOME; log in again if the "
              "user's session stops working", file=sys.stderr)
    (run_dir / "diff.patch").write_bytes(collect_diff(workspace))

    events_text = (run_dir / "events.jsonl").read_text()
    codex_version = subprocess.run(["codex", "--version"], text=True, capture_output=True).stdout.strip()
    metadata = {
        "fixture": args.fixture, "arm": arm, "trial": args.trial, "skills": skills if args.arm == "skills" else [],
        "exit_code": exit_code, "seconds": seconds, "codex": codex_version, "effort": args.effort,
        "model": args.model, "cxx": args.cxx, "codex_home": "shared" if args.shared_home else "isolated",
        "login_refreshed": refreshed,
        "skills_commit": rev or run(["git", "rev-parse", "HEAD"], cwd=REPO).stdout.strip(),
        "skills_modified": rev is None and bool(run(["git", "status", "--porcelain", "--", "skills"], cwd=REPO).stdout),
        "skill_files_read": sorted({name for name in skills if f".agents/skills/{name}/SKILL.md" in events_text}),
    }
    (run_dir / "run.json").write_text(json.dumps(metadata, indent=2) + "\n")

    check = HIDDEN / args.fixture / "check.sh"
    if args.grade and check.exists():
        # Checks may also grade the final message, for example whether it names what the fix covers.
        check_args = ["bash", str(check), str(workspace), str(run_dir / "last_message.txt")]
        result = subprocess.run(check_args, text=True, errors="replace", capture_output=True, env=env)
        (run_dir / "grade.txt").write_text(result.stdout + result.stderr)

    print(json.dumps(metadata))
    return 0


if __name__ == "__main__":
    sys.exit(main())
