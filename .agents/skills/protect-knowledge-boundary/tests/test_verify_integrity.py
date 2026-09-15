import hashlib
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "verify_integrity.py"
SYMLINK_TARGET = "../../.agents/skills/protect-knowledge-boundary"
REQUIRED_ASSETS = {
    ".agents/references/collaboration-rules.md",
    ".agents/skills/protect-knowledge-boundary/SKILL.md",
    ".agents/skills/protect-knowledge-boundary/agents/openai.yaml",
    ".agents/skills/protect-knowledge-boundary/references/boundary-policy.md",
    ".agents/skills/protect-knowledge-boundary/scripts/check_public_knowledge.py",
    ".agents/skills/protect-knowledge-boundary/scripts/verify_integrity.py",
    ".agents/skills/protect-knowledge-boundary/tests/test_check_public_knowledge.py",
    ".agents/skills/protect-knowledge-boundary/tests/test_commit_check_consent.py",
    ".agents/skills/protect-knowledge-boundary/tests/test_verify_integrity.py",
}


def load_module():
    spec = importlib.util.spec_from_file_location("verify_integrity", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class IntegrityVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.asset = self.root / ".agents/skills/protect-knowledge-boundary/SKILL.md"
        manifest_lines = []
        for relative in sorted(REQUIRED_ASSETS):
            asset = self.root / relative
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text(f"protected: {relative}\n", encoding="utf-8")
            digest = hashlib.sha256(asset.read_bytes()).hexdigest()
            manifest_lines.append(f"{digest}  {relative}\n")
        self.manifest = self.root / ".agents/integrity/protected-assets.sha256"
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text("".join(manifest_lines), encoding="utf-8")
        manifest_digest = hashlib.sha256(self.manifest.read_bytes()).hexdigest()
        (self.root / "AGENTS.md").write_text(self.anchor(manifest_digest), encoding="utf-8")
        link = self.root / ".claude/skills/protect-knowledge-boundary"
        link.parent.mkdir(parents=True)
        os.symlink(SYMLINK_TARGET, link)

    def tearDown(self):
        self.temp_dir.cleanup()

    @staticmethod
    def anchor(manifest_digest: str) -> str:
        return (
            "<!-- knowledge-boundary-gate:start -->\n"
            "Complete the manual module-by-module edition-boundary review described in "
            "`.agents/skills/protect-knowledge-boundary/SKILL.md` before completing "
            "knowledge-boundary changes.\n"
            f"Integrity manifest SHA-256: `{manifest_digest}`\n"
            "<!-- knowledge-boundary-gate:end -->\n"
        )

    def test_accepts_valid_assets_anchor_and_symlink(self):
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 0, result.findings)

    def test_rejects_changed_protected_asset(self):
        self.asset.write_text("tampered\n", encoding="utf-8")
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("hash-mismatch", {item.code for item in result.findings})

    def test_rejects_missing_protected_asset(self):
        self.asset.unlink()
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("missing-asset", {item.code for item in result.findings})

    def test_rejects_missing_instruction_anchor(self):
        (self.root / "AGENTS.md").write_text("# Instructions\n", encoding="utf-8")
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("missing-anchor", {item.code for item in result.findings})

    def test_rejects_changed_manifest_anchor_digest(self):
        (self.root / "AGENTS.md").write_text(self.anchor("0" * 64), encoding="utf-8")
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("manifest-anchor-mismatch", {item.code for item in result.findings})

    def test_rejects_incorrect_claude_symlink(self):
        link = self.root / ".claude/skills/protect-knowledge-boundary"
        link.unlink()
        os.symlink("../../wrong", link)
        result = load_module().verify(self.root, self.manifest)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("invalid-symlink", {item.code for item in result.findings})

    def test_rejects_missing_required_manifest_entry(self):
        lines = self.manifest.read_text(encoding="utf-8").splitlines(keepends=True)
        self.manifest.write_text(
            "".join(line for line in lines if "collaboration-rules.md" not in line),
            encoding="utf-8",
        )
        manifest_digest = hashlib.sha256(self.manifest.read_bytes()).hexdigest()
        (self.root / "AGENTS.md").write_text(self.anchor(manifest_digest), encoding="utf-8")

        result = load_module().verify(self.root, self.manifest)

        self.assertEqual(result.exit_code, 1)
        self.assertIn("missing-manifest-entry", {item.code for item in result.findings})


if __name__ == "__main__":
    unittest.main()
