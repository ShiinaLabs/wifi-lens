import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


FORMATTER = Path(__file__).parents[1] / "format_xcstrings.py"
PRE_COMMIT = Path(__file__).parents[2] / ".githooks" / "pre-commit"


class XcstringsFormatterTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "scripts").mkdir()
        (self.root / "scripts" / "format_xcstrings.py").write_bytes(FORMATTER.read_bytes())
        (self.root / ".githooks").mkdir()
        hook = self.root / ".githooks" / "pre-commit"
        hook.write_bytes(PRE_COMMIT.read_bytes())
        hook.chmod(0o755)
        self.path = self.root / "Catalog.xcstrings"

    def tearDown(self):
        self.temporary_directory.cleanup()

    def git(self, *arguments, input_bytes=None):
        return subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout

    def run_formatter(self, *arguments, expected=0):
        result = subprocess.run(
            [sys.executable, "scripts/format_xcstrings.py", *arguments],
            cwd=self.root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, expected, result.stderr.decode("utf-8", errors="replace"))
        return result

    def stage(self):
        self.git("add", "Catalog.xcstrings")

    def test_staged_catalog_is_canonical_and_idempotent(self):
        source = b'{"z": 1, "a": "caf\xc3\xa9"}\r\n'
        self.path.write_bytes(source)
        self.stage()
        staged_before = json.loads(self.git("show", ":Catalog.xcstrings"))

        self.run_formatter("--staged")
        canonical = self.git("show", ":Catalog.xcstrings")
        self.assertEqual(json.loads(canonical), staged_before)
        self.assertEqual(canonical, self.path.read_bytes())
        self.assertEqual(canonical, b'{\n  "a": "caf\xc3\xa9",\n  "z": 1\n}\n')

        self.run_formatter("--staged")
        self.assertEqual(self.git("show", ":Catalog.xcstrings"), canonical)
        self.assertEqual(self.path.read_bytes(), canonical)

    def test_partial_staging_does_not_stage_worktree_changes(self):
        self.path.write_text('{"z": 1, "a": 2}\n', encoding="utf-8")
        self.stage()
        staged_semantics = json.loads(self.git("show", ":Catalog.xcstrings"))
        worktree_only = '{"z": 1, "a": 2, "worktreeOnly": true}\n'
        self.path.write_text(worktree_only, encoding="utf-8")

        self.run_formatter("--staged")

        staged = self.git("show", ":Catalog.xcstrings")
        self.assertEqual(json.loads(staged), staged_semantics)
        self.assertNotIn("worktreeOnly", json.loads(staged))
        self.assertEqual(self.path.read_text(encoding="utf-8"), worktree_only)
        self.assertTrue(self.git("diff", "--", "Catalog.xcstrings"))

    def test_invalid_json_fails_without_replacing_staged_blob(self):
        invalid = b'{"broken": }\n'
        self.path.write_bytes(invalid)
        self.stage()

        self.run_formatter("--staged", expected=1)

        self.assertEqual(self.git("show", ":Catalog.xcstrings"), invalid)

    def test_check_rejects_noncanonical_tracked_catalog(self):
        self.path.write_text('{"z": 1, "a": 2}\n', encoding="utf-8")
        self.stage()

        self.run_formatter("--check", expected=1)
        self.run_formatter("--staged")
        self.run_formatter("--check")

    def test_pre_commit_hook_formats_staged_catalog(self):
        self.path.write_text('{"z": 1, "a": 2}\n', encoding="utf-8")
        self.stage()
        environment = {
            **os.environ,
            "GIT_AUTHOR_NAME": "Formatter Test",
            "GIT_AUTHOR_EMAIL": "formatter@example.invalid",
            "GIT_COMMITTER_NAME": "Formatter Test",
            "GIT_COMMITTER_EMAIL": "formatter@example.invalid",
        }
        subprocess.run(
            ["git", "-c", "core.hooksPath=.githooks", "commit", "-m", "formatter test"],
            cwd=self.root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        committed = self.git("show", "HEAD:Catalog.xcstrings")
        self.assertEqual(committed, b'{\n  "a": 2,\n  "z": 1\n}\n')


if __name__ == "__main__":
    unittest.main()
