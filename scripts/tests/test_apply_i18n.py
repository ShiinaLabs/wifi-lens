import difflib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
APPLY = REPO_ROOT / ".agents" / "skills" / "i18n-completer" / "scripts" / "apply_i18n.py"
FORMATTER = REPO_ROOT / "scripts" / "format_xcstrings.py"


def _formatter():
    spec = importlib.util.spec_from_file_location("format_xcstrings", FORMATTER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def catalog(entries: dict) -> dict:
    return {"sourceLanguage": "en", "strings": entries, "version": "1.1"}


def translated(value: str, state: str = "translated") -> dict:
    return {"stringUnit": {"state": state, "value": value}}


def manual(entry: dict) -> dict:
    return {"extractionState": "manual", "localizations": entry}


class ApplyI18nTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "Catalog.xcstrings"

    def tearDown(self):
        self.directory.cleanup()

    def write_catalog(self, document: dict) -> bytes:
        self.path.write_bytes(_formatter().canonical_bytes(document))
        return self.path.read_bytes()

    def apply(self, *arguments, expected=0, stdin=None):
        result = subprocess.run(
            [sys.executable, str(APPLY), str(self.path), *arguments],
            input=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def read(self) -> dict:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def test_updates_a_single_existing_translation(self):
        self.write_catalog(catalog({"k.one": manual({"ja": translated("old")})}))

        self.apply("--set", "k.one", "--lang", "ja", "--value", "new")

        unit = self.read()["strings"]["k.one"]["localizations"]["ja"]["stringUnit"]
        self.assertEqual(unit["value"], "new")
        self.assertEqual(unit["state"], "translated")

    def test_adds_a_language_to_an_existing_key(self):
        self.write_catalog(catalog({"k.one": manual({"en": translated("Value")})}))

        self.apply("--set", "k.one", "--lang", "ja", "--value", "値")

        localizations = self.read()["strings"]["k.one"]["localizations"]
        self.assertEqual(localizations["ja"]["stringUnit"]["value"], "値")
        self.assertEqual(localizations["en"]["stringUnit"]["value"], "Value")

    def test_updates_multiple_keys_from_stdin(self):
        self.write_catalog(
            catalog({"k.one": manual({"ja": translated("a")}), "k.two": manual({"ja": translated("b")})})
        )

        self.apply("--from", "-", stdin=json.dumps({"k.one": {"ja": "A"}, "k.two": {"ja": "B"}}))

        strings = self.read()["strings"]
        self.assertEqual(strings["k.one"]["localizations"]["ja"]["stringUnit"]["value"], "A")
        self.assertEqual(strings["k.two"]["localizations"]["ja"]["stringUnit"]["value"], "B")

    def test_rewriting_the_same_value_leaves_the_file_untouched(self):
        before = self.write_catalog(catalog({"k.one": manual({"ja": translated("same")})}))

        result = self.apply("--set", "k.one", "--lang", "ja", "--value", "same")

        self.assertIn("No changes needed.", result.stdout)
        self.assertEqual(self.path.read_bytes(), before)

    def test_state_change_with_identical_text_is_persisted(self):
        self.write_catalog(catalog({"k.one": manual({"ja": translated("same", state="needs_review")})}))
        before = self.path.read_bytes()

        result = self.apply("--set", "k.one", "--lang", "ja", "--value", "same")

        self.assertIn("STATE", result.stdout)
        self.assertNotEqual(self.path.read_bytes(), before)
        unit = self.read()["strings"]["k.one"]["localizations"]["ja"]["stringUnit"]
        self.assertEqual(unit["state"], "translated")
        self.assertEqual(unit["value"], "same")

    def test_plural_variations_survive_a_value_update(self):
        variations = {
            "plural": {
                "one": {"stringUnit": {"state": "translated", "value": "%d item"}},
                "other": {"stringUnit": {"state": "translated", "value": "%d items"}},
            }
        }
        entry = manual({"ja": {"stringUnit": {"state": "translated", "value": "old"}, "variations": variations}})
        self.write_catalog(catalog({"k.plural": entry}))

        self.apply("--set", "k.plural", "--lang", "ja", "--value", "new")

        localization = self.read()["strings"]["k.plural"]["localizations"]["ja"]
        self.assertEqual(localization["variations"], variations)
        self.assertEqual(localization["stringUnit"]["value"], "new")

    def test_unknown_metadata_survives_a_value_update(self):
        entry = {
            "extractionState": "manual",
            "shouldTranslate": False,
            "comment": "kept",
            "generatesSymbol": False,
            "localizations": {"ja": {"stringUnit": {"state": "translated", "value": "old"}, "x-extra": {"a": 1}}},
        }
        self.write_catalog(catalog({"k.meta": entry}))

        self.apply("--set", "k.meta", "--lang", "ja", "--value", "new")

        written = self.read()["strings"]["k.meta"]
        self.assertEqual(written["shouldTranslate"], False)
        self.assertEqual(written["comment"], "kept")
        self.assertEqual(written["generatesSymbol"], False)
        self.assertEqual(written["localizations"]["ja"]["x-extra"], {"a": 1})

    def test_dry_run_does_not_write(self):
        before = self.write_catalog(catalog({"k.one": manual({"ja": translated("old")})}))

        result = self.apply("--set", "k.one", "--lang", "ja", "--value", "new", "--dry-run")

        self.assertIn("Dry run", result.stdout)
        self.assertEqual(self.path.read_bytes(), before)

    def test_invalid_json_fails_without_writing(self):
        self.path.write_bytes(b'{"strings": {"broken": }')
        before = self.path.read_bytes()

        self.apply("--set", "k.one", "--lang", "ja", "--value", "new", expected=1)

        self.assertEqual(self.path.read_bytes(), before)

    def test_duplicate_json_keys_are_rejected(self):
        self.path.write_bytes(
            b'{"sourceLanguage": "en", "strings": {"k.one": {}, "k.one": {}, "k.two": {}}, "version": "1.1"}'
        )
        before = self.path.read_bytes()

        self.apply("--set", "k.two", "--lang", "ja", "--value", "v", expected=1)

        self.assertEqual(self.path.read_bytes(), before)

    def test_duplicate_keys_in_the_translation_input_are_rejected(self):
        before = self.write_catalog(catalog({"k.one": manual({"ja": translated("old")})}))

        self.apply("--from", "-", expected=1, stdin='{"k.one": {"ja": "a"}, "k.one": {"ja": "b"}}')

        self.assertEqual(self.path.read_bytes(), before)

    def test_unrelated_keys_keep_their_exact_content(self):
        entries = {
            "k.one": manual({"ja": translated("old")}),
            "k.two": manual({"de": translated("zwei"), "ja": translated("二")}),
            "k.three": manual({"ja": translated("三", state="needs_review")}),
        }
        self.write_catalog(catalog(entries))

        self.apply("--set", "k.one", "--lang", "ja", "--value", "new")

        strings = self.read()["strings"]
        self.assertEqual(strings["k.two"], entries["k.two"])
        self.assertEqual(strings["k.three"], entries["k.three"])

    def test_editing_one_translation_on_a_canonical_catalog_is_a_small_diff(self):
        entries = {
            f"feature.section_{index:03d}.label": manual({"ja": translated(f"値{index}"), "de": translated(f"W{index}")})
            for index in range(500)
        }
        before = self.write_catalog(catalog(entries))

        self.apply("--set", "feature.section_250.label", "--lang", "ja", "--value", "変更後")

        after = self.path.read_bytes()
        diff = [
            line
            for line in difflib.unified_diff(
                before.decode("utf-8").splitlines(), after.decode("utf-8").splitlines(), lineterm=""
            )
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        ]
        self.assertLess(len(diff), 6, f"editing one translation rewrote {len(diff)} lines")

    def test_written_catalog_is_still_canonical(self):
        self.write_catalog(catalog({"k.one": manual({"ja": translated("old")})}))

        self.apply("--set", "k.one", "--lang", "ja", "--value", "new")

        written = self.path.read_bytes()
        self.assertEqual(written, _formatter().canonical_json(written))


if __name__ == "__main__":
    unittest.main()
