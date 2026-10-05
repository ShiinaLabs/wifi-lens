#!/usr/bin/env python3
"""Auxiliary duplicate-content check for public Markdown assets."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

MIN_COPY_WORDS = 12
SELF_PROTECTED_PREFIX = Path(".agents/skills/protect-knowledge-boundary")
WORD = re.compile(r"[A-Za-z0-9_]+")


class Finding(NamedTuple):
    level: str
    code: str
    path: str
    line: int
    message: str


class ScanResult:
    def __init__(self, findings: list[Finding]):
        self.findings = findings

    @property
    def exit_code(self) -> int:
        return 1 if any(item.level == "FAIL" for item in self.findings) else 0


def _git_markdown_paths(directory: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(directory), "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.md"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        return [directory / line for line in result.stdout.splitlines() if line]
    return list(directory.rglob("*.md")) if directory.exists() else []


def _paragraphs(text: str):
    lines: list[str] = []
    start = 1
    for line_number, line in enumerate(text.splitlines(), 1):
        if line.strip():
            if not lines:
                start = line_number
            lines.append(line.strip())
        elif lines:
            yield start, " ".join(lines)
            lines = []
    if lines:
        yield start, " ".join(lines)


def _normalized_words(text: str) -> tuple[str, ...]:
    return tuple(word.lower() for word in WORD.findall(text))


def _reference_passages(reference_root: Path | None) -> list[tuple[tuple[str, ...], str]]:
    if reference_root is None:
        return []
    passages: list[tuple[tuple[str, ...], str]] = []
    for path in _git_markdown_paths(reference_root.resolve()):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        for _, paragraph in _paragraphs(text):
            words = _normalized_words(paragraph)
            if len(words) >= MIN_COPY_WORDS:
                passages.append((words, "authorized reference"))
    return passages


def _contains_words(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    if len(needle) > len(haystack):
        return False
    width = len(needle)
    return any(haystack[index : index + width] == needle for index in range(len(haystack) - width + 1))


def scan_repository(
    root: Path,
    paths: list[Path] | None = None,
    reference_root: Path | None = None,
) -> ScanResult:
    root = root.resolve()
    candidates = paths if paths is not None else _git_markdown_paths(root)
    reference_passages = _reference_passages(reference_root)
    findings: list[Finding] = []

    for path in candidates:
        path = path.resolve()
        try:
            relative = path.relative_to(root)
        except ValueError:
            findings.append(Finding("FAIL", "outside-root", str(path), 0, "Public scan path is outside the repository."))
            continue
        if relative.is_relative_to(SELF_PROTECTED_PREFIX):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            findings.append(Finding("FAIL", "unreadable-file", relative.as_posix(), 0, str(error)))
            continue

        for line_number, paragraph in _paragraphs(text):
            public_words = _normalized_words(paragraph)
            if len(public_words) < MIN_COPY_WORDS:
                continue
            if any(_contains_words(public_words, passage) for passage, _ in reference_passages):
                findings.append(
                    Finding(
                        "FAIL",
                        "copied-reference-passage",
                        relative.as_posix(),
                        line_number,
                        "Public content duplicates a passage from the authorized reference checkout.",
                    )
                )
                break

    return ScanResult(findings)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--reference-root", type=Path, help="Optional authorized checkout used for duplicate-content comparison.")
    parser.add_argument("paths", nargs="*", type=Path)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    root = args.root.resolve()
    paths = [path if path.is_absolute() else root / path for path in args.paths] or None
    result = scan_repository(root, paths, args.reference_root)
    for item in result.findings:
        print(f"{item.level} {item.path}:{item.line} [{item.code}] {item.message}")
    status = "FAIL" if result.exit_code else "PASS"
    print(f"{status}: auxiliary duplicate-content check; manual boundary review required")
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
