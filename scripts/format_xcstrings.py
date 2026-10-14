#!/usr/bin/env python3
"""Deterministically format staged or tracked Xcode string catalogs."""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


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


def canonical_json(source: bytes) -> bytes:
    value = json.loads(
        source.decode("utf-8"),
        object_pairs_hook=unique_object,
        parse_constant=reject_constant,
    )
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


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
