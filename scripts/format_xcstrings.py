#!/usr/bin/env python3
"""Deterministically format staged or tracked Xcode string catalogs.

The canonical bytes are the bytes Xcode's own string-catalog writer produces,
so a catalog that Xcode rewrote while a developer was editing it already
satisfies this contract and never turns into a full-file diff. That format is:

* keys ordered by ``NSString.localizedStandardCompare``,
* ``" : "`` between a key and its value,
* two-space indentation with every container expanded, so an empty container
  renders as ``{``, a blank line, and the closing brace,
* non-ASCII kept literal,
* no trailing newline.

Python's standard library has no ICU collation and neither :mod:`locale` nor
the system ``sort`` reproduces ``localizedStandardCompare``, so the ordering is
delegated to Foundation through ``xcstrings_key_order.swift``. That helper
compares with ``Locale(identifier: "en_US")`` rather than the developer's
current locale, which keeps the canonical bytes identical on every machine.

Verified byte-for-byte against catalogs written by Xcode 27.1 and by the
earlier Xcode that produced the 2026-10-01 and 2026-10-14 catalog revisions.
``--check`` is the drift detector if a future Xcode changes the rule: the
tracked catalogs stop matching and CI fails instead of drifting silently.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

HELPER_NAME = "xcstrings_key_order.swift"


def swift_interpreter() -> list[str]:
    located = shutil.which("swift")
    if located:
        return [located]
    xcrun = shutil.which("xcrun")
    if xcrun:
        found = subprocess.run([xcrun, "--find", "swift"], capture_output=True, text=True, check=False)
        if found.returncode == 0 and found.stdout.strip():
            return [found.stdout.strip()]
    raise ValueError("no swift interpreter; the string catalog key order needs the Xcode toolchain")


def ordered_keys(keys: list[str]) -> list[str]:
    """Order catalog keys the way Xcode does."""
    helper = Path(__file__).resolve().with_name(HELPER_NAME)
    if not helper.is_file():
        raise ValueError(f"missing key-order helper: {helper}")
    payload = ("\0".join(keys) + "\0").encode("utf-8")
    result = subprocess.run(
        [*swift_interpreter(), str(helper)],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ValueError(f"key-order helper failed: {detail}")
    ordered = result.stdout.decode("utf-8").split("\0")
    if ordered and ordered[-1] == "":
        ordered.pop()
    if len(ordered) != len(keys) or sorted(ordered) != sorted(keys):
        raise ValueError("key-order helper did not return a permutation of its input")
    return ordered


def render(value: object, indent: int = 0) -> str:
    """Serialize one JSON value the way Xcode writes it."""
    padding = "  " * indent
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + padding + "}"
        body = ",\n".join(
            f"{padding}  {json.dumps(key, ensure_ascii=False)} : {render(item, indent + 1)}"
            for key, item in value.items()
        )
        return "{\n" + body + "\n" + padding + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + padding + "]"
        body = ",\n".join(f"{padding}  {render(item, indent + 1)}" for item in value)
        return "[\n" + body + "\n" + padding + "]"
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


def run_git(root: Path, *args: bytes | str, input_bytes: bytes | None = None) -> bytes:
    return subprocess.run(
        [b"git", *[os.fsencode(arg) if isinstance(arg, str) else arg for arg in args]],
        cwd=root,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def reject_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON number {value}")


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def sort_objects(value: object) -> object:
    """Order every nested object by code point, as Xcode does outside ``strings``."""
    if isinstance(value, dict):
        return {key: sort_objects(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [sort_objects(item) for item in value]
    return value


def canonical_bytes(value: object) -> bytes:
    """Deterministic Xcode-native bytes for an already-parsed catalog."""
    value = sort_objects(value)
    if isinstance(value, dict) and isinstance(value.get("strings"), dict):
        strings = value["strings"]
        value["strings"] = {key: strings[key] for key in ordered_keys(list(strings))}
    return render(value).encode("utf-8")


def canonical_json(source: bytes) -> bytes:
    return canonical_bytes(
        json.loads(
            source.decode("utf-8"),
            object_pairs_hook=unique_object,
            parse_constant=reject_constant,
        )
    )


def git_root() -> Path:
    return Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())


def tracked_catalog_paths(root: Path) -> list[bytes]:
    return [path for path in run_git(root, "ls-files", "-z").split(b"\0") if path.endswith(b".xcstrings")]


def staged_catalog_paths(root: Path) -> list[bytes]:
    changed = run_git(root, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
    return sorted({path for path in changed.split(b"\0") if path.endswith(b".xcstrings")})


def index_entries(root: Path) -> dict[bytes, list[tuple[bytes, bytes, bytes]]]:
    entries: dict[bytes, list[tuple[bytes, bytes, bytes]]] = {}
    for record in run_git(root, "ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        header, path = record.split(b"\t", 1)
        mode, oid, stage = header.split()
        entries.setdefault(path, []).append((mode, oid, stage))
    return entries


def atomic_replace(path: Path, content: bytes, original_mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, stat.S_IMODE(original_mode))
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def format_staged(root: Path) -> int:
    entries = index_entries(root)
    formatted_count = 0
    for raw_path in staged_catalog_paths(root):
        candidates = entries.get(raw_path, [])
        if len(candidates) != 1 or candidates[0][2] != b"0":
            raise ValueError(f"{os.fsdecode(raw_path)}: staged entry is missing or conflicted")
        mode, oid, _ = candidates[0]
        original = run_git(root, "cat-file", "blob", oid)
        formatted = canonical_json(original)
        if formatted == original:
            continue

        new_oid = run_git(root, "hash-object", "-w", "--stdin", input_bytes=formatted).strip()
        run_git(root, "update-index", "--cacheinfo", mode, new_oid, raw_path)

        working_path = root / os.fsdecode(raw_path)
        if not working_path.is_symlink() and working_path.is_file() and working_path.read_bytes() == original:
            atomic_replace(working_path, formatted, working_path.stat().st_mode)
        formatted_count += 1
    return formatted_count


def check_tracked(root: Path) -> None:
    for raw_path in tracked_catalog_paths(root):
        path = root / os.fsdecode(raw_path)
        current = path.read_bytes()
        if canonical_json(current) != current:
            raise ValueError(f"{os.fsdecode(raw_path)}: file is not in canonical JSON format")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="format staged catalogs and update only their index entries")
    mode.add_argument("--check", action="store_true", help="check every tracked catalog without modifying files")
    args = parser.parse_args()

    try:
        root = git_root()
        if args.check:
            check_tracked(root)
        else:
            format_staged(root)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"xcstrings formatting failed: {detail}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
