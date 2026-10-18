import importlib.util
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
SCOPE = ROOT / "skills" / "cpp-review" / "scripts" / "review_scope.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


installer = load_module("installer", ROOT / "scripts" / "install.py")
validator = load_module("validator", ROOT / "scripts" / "validate.py")


class ReviewScopeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo with spaces"
        self.repo.mkdir()
        self.git("init")
        self.git("symbolic-ref", "HEAD", "refs/heads/main")
        self.git("config", "user.name", "Scope Test")
        self.git("config", "user.email", "scope@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.write("same.cc", "int base = 0;\n")
        self.commit("base")
        self.git("checkout", "-b", "stack-parent")
        self.write("parent.cc", "int parent = 1;\n")
        self.commit("lower layer")
        self.git("checkout", "-b", "feature")
        self.write("same.cc", "int committed = 1;\n")
        self.write("branch.cc", "int branch = 1;\n")
        self.commit("current layer")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True).stdout

    def write(self, name, content):
        (self.repo / name).write_text(content, encoding="utf-8")

    def commit(self, message):
        self.git("add", "--all")
        self.git("commit", "-m", message)

    def run_scope(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(SCOPE), "--repo", str(self.repo), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 2, result.stderr)
        return json.loads(result.stdout) if ok else result.stderr

    def test_stacked_diff_and_every_local_layer_are_preserved(self):
        self.write("same.cc", "int staged = 2;\n")
        self.git("add", "same.cc")
        self.write("same.cc", "int unstaged = 3;\n")
        self.write("未跟踪 name\nwith newline.cc", "int local = 1;\n")
        before = self.git("status", "--porcelain=v1", "-z")
        report = self.run_scope("--base", "stack-parent")
        layers = {item["name"]: item for item in report["layers"]}
        self.assertEqual(set(layers["committed"]["paths"]), {"same.cc", "branch.cc"})
        self.assertEqual(layers["staged"]["paths"], ["same.cc"])
        self.assertEqual(layers["unstaged"]["paths"], ["same.cc"])
        self.assertEqual(layers["untracked"]["paths"], ["未跟踪 name\nwith newline.cc"])
        for name, added in [("committed", "+int committed"), ("staged", "+int staged"), ("unstaged", "+int unstaged")]:
            patch = subprocess.check_output(shlex.split(layers[name]["patch_command"]), text=True)
            self.assertIn(added, patch)
        self.assertEqual(before, self.git("status", "--porcelain=v1", "-z"))

    def test_base_is_required_and_never_guessed(self):
        self.assertIn("--base is required", self.run_scope(ok=False))
        self.run_scope("--base", "does-not-exist", ok=False)

    def test_other_head_requires_branch_only(self):
        self.run_scope("--base", "main", "--head", "stack-parent", ok=False)
        report = self.run_scope("--scope", "branch", "--base", "main", "--head", "stack-parent")
        self.assertEqual([x["name"] for x in report["layers"]], ["committed"])
        self.assertEqual(report["layers"][0]["paths"], ["parent.cc"])

    def test_worktree_scope_does_not_require_or_accept_a_base(self):
        report = self.run_scope("--scope", "worktree")
        self.assertEqual([x["name"] for x in report["layers"]], ["staged", "unstaged", "untracked"])
        self.run_scope("--scope", "worktree", "--base", "main", ok=False)

    def test_renamed_and_deleted_files_remain_visible(self):
        self.git("mv", "branch.cc", "renamed file.cc")
        self.git("rm", "same.cc")
        self.commit("rename and delete")
        report = self.run_scope("--scope", "branch", "--base", "HEAD~1")
        self.assertEqual(set(report["layers"][0]["paths"]), {"branch.cc", "renamed file.cc", "same.cc"})

    def test_unmerged_paths_are_explicit(self):
        self.git("checkout", "stack-parent")
        self.write("same.cc", "int conflicting = 4;\n")
        self.commit("conflict on base")
        self.git("checkout", "feature")
        result = subprocess.run(["git", "-C", str(self.repo), "merge", "stack-parent"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        report = self.run_scope("--scope", "worktree")
        self.assertEqual(report["unmerged_paths"], ["same.cc"])

    def test_multiple_merge_bases_are_rejected(self):
        tree = self.git("rev-parse", "main^{tree}").decode().strip()
        root = self.git("rev-parse", "main").decode().strip()
        left = self.git("commit-tree", tree, "-p", root, "-m", "left").decode().strip()
        right = self.git("commit-tree", tree, "-p", root, "-m", "right").decode().strip()
        first = self.git("commit-tree", tree, "-p", left, "-p", right, "-m", "first merge").decode().strip()
        second = self.git("commit-tree", tree, "-p", right, "-p", left, "-m", "second merge").decode().strip()
        error = self.run_scope("--scope", "branch", "--base", first, "--head", second, ok=False)
        self.assertIn("unique merge base", error)


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.dest = self.root / "installed"

    def test_selected_skill_includes_required_references(self):
        installed = installer.install(ROOT / "skills", self.dest, ["cpp-lifetime"])
        self.assertEqual(installed, [self.dest / "cpp-lifetime"])
        self.assertTrue((installed[0] / "references" / "cross-boundary.md").is_file())
        self.assertEqual(len(list(self.dest.iterdir())), 1)

    def test_collision_preflight_preserves_existing_and_copies_nothing(self):
        old = self.dest / "cpp-review"
        old.mkdir(parents=True)
        (old / "local.txt").write_text("keep")
        with self.assertRaises(ValueError):
            installer.install(ROOT / "skills", self.dest, ["cpp-core", "cpp-review"])
        self.assertFalse((self.dest / "cpp-core").exists())
        self.assertEqual((old / "local.txt").read_text(), "keep")

    def test_dry_run_makes_no_directories(self):
        installer.install(ROOT / "skills", self.dest, dry_run=True)
        self.assertFalse(self.dest.exists())

    def test_unknown_skill_and_dangling_destination_symlink_are_rejected(self):
        with self.assertRaises(ValueError):
            installer.install(ROOT / "skills", self.dest, ["../escape"])
        self.dest.mkdir()
        (self.dest / "cpp-core").symlink_to(self.root / "missing")
        with self.assertRaises(ValueError):
            installer.install(ROOT / "skills", self.dest, ["cpp-core"])

    def test_destination_inside_source_is_rejected_without_creating_it(self):
        source = self.root / "source"
        skill = source / "example"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("example")
        destination = skill / "recursive"
        with self.assertRaises(ValueError):
            installer.install(source, destination)
        self.assertFalse(destination.exists())


class PackageLinksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "collection"
        shutil.copytree(ROOT / "skills", self.root / "skills",
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))

    def test_every_skill_keeps_its_references_when_installed_alone(self):
        for source in sorted((ROOT / "skills").iterdir()):
            if not (source / "SKILL.md").is_file():
                continue
            with self.subTest(skill=source.name):
                isolated = Path(self.temp.name) / source.name
                installer.install(ROOT / "skills", isolated / "skills", [source.name])
                errors, count = validator.validate(isolated)
                self.assertEqual(errors, [])
                self.assertEqual(count, 1)

    def test_sibling_skill_link_is_rejected_even_when_target_exists(self):
        entry = self.root / "skills/cpp-core/SKILL.md"
        with entry.open("a", encoding="utf-8") as output:
            output.write("\n[Other skill](../cpp-lifetime/references/cross-boundary.md)\n")
        errors, _ = validator.validate(self.root)
        self.assertTrue(any("leaves package boundary" in error for error in errors), errors)

    def test_nested_reference_cannot_depend_on_collection_docs(self):
        (self.root / "docs").mkdir()
        (self.root / "docs/shared.md").write_text("Collection documentation", encoding="utf-8")
        reference = self.root / "skills/cpp-lifetime/references/cross-boundary.md"
        with reference.open("a", encoding="utf-8") as output:
            output.write("\n[Collection docs](../../../docs/shared.md)\n")
        errors, _ = validator.validate(self.root)
        self.assertTrue(any("leaves package boundary" in error for error in errors), errors)

    def test_missing_reference_is_reported(self):
        entry = self.root / "skills/cpp-core/SKILL.md"
        with entry.open("a", encoding="utf-8") as output:
            output.write("\n[Missing](references/missing.md)\n")
        errors, _ = validator.validate(self.root)
        self.assertTrue(any("broken local link" in error for error in errors), errors)

    def test_collection_docs_can_link_to_skills(self):
        (self.root / "README.md").write_text(
            "[Core](skills/cpp-core/SKILL.md)\n", encoding="utf-8")
        errors, count = validator.validate(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(count, 6)

    def test_disabled_missing_or_string_invocation_policy_is_rejected(self):
        path = self.root / "skills/cpp-core/agents/openai.yaml"
        original = yaml.safe_load(path.read_text(encoding="utf-8"))
        for value in [False, "true", None]:
            with self.subTest(policy=value):
                config = dict(original)
                if value is None:
                    config.pop("policy", None)
                else:
                    config["policy"] = {"allow_implicit_invocation": value}
                path.write_text(yaml.safe_dump(config), encoding="utf-8")
                errors, _ = validator.validate(self.root)
                self.assertTrue(any("must explicitly allow implicit invocation" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
