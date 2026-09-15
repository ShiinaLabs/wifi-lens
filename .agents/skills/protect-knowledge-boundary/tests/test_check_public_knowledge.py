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
        (self.root / "Pro" / "docs").mkdir(parents=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def write(self, relative_path: str, content: str) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def scan(self, public_text: str, private_text: str = ""):
        public = self.write("docs/public.md", public_text)
        if private_text:
            self.write("Pro/docs/private.md", private_text)
        module = load_module()
        return module.scan_repository(self.root, [public])

    def test_allows_private_document_index_without_summary(self):
        result = self.scan(
            "| `Pro/docs/ARCHITECTURE.md` | Private Pro architecture; read it only inside the Pro repository. |\n"
        )
        self.assertEqual(result.exit_code, 0, result.findings)

    def test_allows_private_agent_instruction_entrypoint(self):
        result = self.scan(
            "For explicitly Pro-scoped work, follow `Pro/AGENTS.md` inside the private repository.\n"
        )
        self.assertEqual(result.exit_code, 0, result.findings)

    def test_rejects_private_source_path(self):
        result = self.scan("Inspect `Pro/Sources/EventJournal.swift` for details.\n")
        self.assertEqual(result.exit_code, 1)
        self.assertIn("private-path", {item.code for item in result.findings})

    def test_rejects_pro_implementation_summary(self):
        result = self.scan(
            "The Pro edition uses SQLite tables to persist events through an internal queue.\n"
        )
        self.assertEqual(result.exit_code, 1)
        self.assertIn("implementation-detail", {item.code for item in result.findings})

    def test_rejects_passage_copied_from_private_document(self):
        private = (
            "The private runtime publishes immutable observations through a bounded "
            "consumer pipeline with ordered delivery and explicit backpressure."
        )
        result = self.scan(private + "\n", private)
        self.assertEqual(result.exit_code, 1)
        self.assertIn("copied-private-passage", {item.code for item in result.findings})


if __name__ == "__main__":
    unittest.main()
