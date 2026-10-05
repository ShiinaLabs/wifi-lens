import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "check_public_knowledge.py"


def load_module():
    spec = importlib.util.spec_from_file_location("check_public_knowledge", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class AuxiliaryContentLintTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.reference = self.root / "reference-source"
        self.reference.mkdir()

    def tearDown(self):
        self.temp_dir.cleanup()

    def write(self, base: Path, relative_path: str, content: str) -> Path:
        path = base / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_accepts_public_edition_language(self):
        public = self.write(self.root, "docs/public.md", "The app supports multiple editions through a stable public composition contract.\n")
        result = load_module().scan_repository(self.root, [public])
        self.assertEqual(result.exit_code, 0, result.findings)

    def test_detects_copy_from_authorized_reference_checkout(self):
        passage = "The runtime publishes immutable observations through ordered delivery and explicit consumer boundaries."
        public = self.write(self.root, "docs/public.md", passage + "\n")
        self.write(self.reference, "docs/internal.md", passage + "\n")
        result = load_module().scan_repository(self.root, [public], self.reference)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("copied-reference-passage", {item.code for item in result.findings})

    def test_rejects_scan_path_outside_public_root(self):
        with tempfile.TemporaryDirectory() as external_directory:
            external = Path(external_directory) / "outside.md"
            external.write_text("text\n", encoding="utf-8")
            result = load_module().scan_repository(self.root, [external])
        self.assertEqual(result.exit_code, 1)
        self.assertIn("outside-root", {item.code for item in result.findings})


if __name__ == "__main__":
    unittest.main()
