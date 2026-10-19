#!/usr/bin/env python3
"""Apply translations to .xcstrings from a JSON input.

Usage:
    # Apply from JSON file
    python3 apply_i18n.py <xcstrings_path> --from <json_file>

    # Apply inline (single key)
    python3 apply_i18n.py <xcstrings_path> --set KEY --lang ja --value "翻訳"

    # Apply from stdin (pipe JSON)
    cat translations.json | python3 apply_i18n.py <xcstrings_path> --from -

JSON input format:
    {
      "key.name": {
        "de": "German value",
        "es": "Spanish value"
      },
      "another.key": {
        "ja": "Japanese value"
      }
    }

Options:
    --dry-run       Show what would be changed without writing
    --source-lang   Source language for new keys (default: en)

Writing goes through scripts/format_xcstrings.py, so a translation edit produces
the same canonical bytes the repository requires and never reformats the
catalog. Only the named keys and languages are touched: an existing language
entry keeps its other fields, including any variations.
"""

import argparse
import importlib.util
import json
import sys
from pathlib import Path


def formatter_module():
    """Load the repository's canonical serializer."""
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "scripts" / "format_xcstrings.py"
        if candidate.is_file():
            spec = importlib.util.spec_from_file_location("format_xcstrings", candidate)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    raise SystemExit(
        "ERROR: scripts/format_xcstrings.py not found above this script; "
        "run apply_i18n.py from inside the repository"
    )


def strict_json(raw: str) -> dict:
    """Parse JSON, refusing input that would silently lose data.

    Plain ``json.load`` keeps only the last of a set of duplicate object keys,
    so a catalog with duplicates would be rewritten with entries dropped.
    """
    formatter = formatter_module()
    return json.loads(
        raw,
        object_pairs_hook=formatter.unique_object,
        parse_constant=formatter.reject_constant,
    )


def load_xcstrings(path: str) -> dict:
    return strict_json(Path(path).read_text(encoding="utf-8"))


def save_xcstrings(path: str, data: dict):
    formatter = formatter_module()
    target = Path(path)
    formatter.atomic_replace(target, formatter.canonical_bytes(data), target.stat().st_mode)


def apply_translations(data: dict, translations: dict, source_lang: str = "en") -> list[str]:
    """Apply translations dict to xcstrings data. Returns list of changes."""
    changes = []
    strings = data.setdefault("strings", {})
    for key, langs in translations.items():
        if key not in strings:
            strings[key] = {
                "extractionState": "manual",
                "localizations": {}
            }

        entry = strings[key]
        localizations = entry.setdefault("localizations", {})

        for lang, value in langs.items():
            # Merge into the existing entry: a language may already carry
            # variations, and those must survive a plain value update.
            localization = localizations.setdefault(lang, {})
            unit = localization.setdefault("stringUnit", {})
            old_value = unit.get("value")
            old_state = unit.get("state")
            if old_value == value and old_state == "translated":
                continue
            unit["state"] = "translated"
            unit["value"] = value
            if old_value is None:
                changes.append(f"ADD    {key} [{lang}]: \"{value}\"")
            elif old_value != value:
                changes.append(f"UPDATE {key} [{lang}]: \"{old_value}\" -> \"{value}\"")
            else:
                changes.append(f"STATE  {key} [{lang}]: {old_state or '<absent>'} -> translated")

    return changes


def main():
    parser = argparse.ArgumentParser(description="Apply translations to .xcstrings")
    parser.add_argument("xcstrings", help="Path to .xcstrings file")
    parser.add_argument("--from", dest="from_file", help="JSON file with translations (- for stdin)")
    parser.add_argument("--set", dest="set_key", help="Single key to set")
    parser.add_argument("--lang", help="Language code for --set")
    parser.add_argument("--value", help="Translation value for --set")
    parser.add_argument("--dry-run", action="store_true", help="Show changes without writing")
    parser.add_argument("--source-lang", default="en", help="Source language (default: en)")
    args = parser.parse_args()

    try:
        data = load_xcstrings(args.xcstrings)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {args.xcstrings}: {error}", file=sys.stderr)
        sys.exit(1)

    if args.set_key:
        if not args.lang or not args.value:
            print("ERROR: --set requires --lang and --value", file=sys.stderr)
            sys.exit(1)
        translations = {args.set_key: {args.lang: args.value}}
    elif args.from_file:
        try:
            if args.from_file == "-":
                translations = strict_json(sys.stdin.read())
            else:
                translations = strict_json(Path(args.from_file).read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
            print(f"ERROR: {args.from_file}: {error}", file=sys.stderr)
            sys.exit(1)
    else:
        print("ERROR: Provide --from or --set", file=sys.stderr)
        sys.exit(1)

    changes = apply_translations(data, translations, args.source_lang)

    if not changes:
        print("No changes needed.")
        return

    if args.dry_run:
        print(f"Dry run — {len(changes)} change(s):")
        for c in changes:
            print(f"  {c}")
    else:
        save_xcstrings(args.xcstrings, data)
        print(f"Applied {len(changes)} change(s):")
        for c in changes:
            print(f"  {c}")


if __name__ == "__main__":
    main()
