#!/usr/bin/env python3
"""Legacy heuristic for public Markdown content.

This is an auxiliary content lint only. It is not an OSS/Pro boundary
verifier, and its result must never be treated as a boundary ``PASS``.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple


PRIVATE_PATH = re.compile(
    r"(?<![\w.-])Pro/(?!AGENTS\.md\b|docs/[A-Za-z0-9._/-]+\.md\b)[A-Za-z0-9._/-]+"
)
PRO_ASSERTION = re.compile(
    r"\bPro(?:\s+(?:edition|target|implementation|app))?\s+"
    r"(?:uses|stores|implements|owns|creates|persists|routes|manages|contains|"
    r"relies|writes|reads|publishes|registers)\b",
    re.IGNORECASE,
)
IMPLEMENTATION_SIGNAL = re.compile(
    r"\b(?:class|struct|actor|protocol|enum|SQLite|schema|table|database|queue|"
    r"journal|persistence|backpressure|observer|coordinator)\b",
    re.IGNORECASE,
)
WORD = re.compile(r"[A-Za-z0-9_]+")
MIN_COPY_WORDS = 12
SELF_PROTECTED_PREFIX = Path(".agents/skills/protect-knowledge-boundary")


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
        if any(item.level == "FAIL" for item in self.findings):
            return 1
        if any(item.level == "REVIEW" for item in self.findings):
            return 2
        return 0


def _git_paths(root: Path, directory: Path, pattern: str = "*.md") -> list[Path]:
    command = [
        "git",
        "-C",
        str(directory),
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        pattern,
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return [directory / line for line in result.stdout.splitlines() if line]
    return list(directory.rglob(pattern)) if directory.exists() else []


def _public_markdown_paths(root: Path) -> list[Path]:
    paths = _git_paths(root, root)
    return [
        path
        for path in paths
        if path.is_file()
        and not path.relative_to(root).is_relative_to(Path("Pro"))
        and not path.relative_to(root).is_relative_to(SELF_PROTECTED_PREFIX)
    ]


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


def _private_passages(root: Path) -> list[tuple[tuple[str, ...], str]]:
    private_root = root / "Pro"
    passages: list[tuple[tuple[str, ...], str]] = []
    for path in _git_paths(root, private_root):
        try:
            relative = path.relative_to(root).as_posix()
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError, ValueError):
            continue
        for _, paragraph in _paragraphs(text):
            words = _normalized_words(paragraph)
            if len(words) >= MIN_COPY_WORDS:
                passages.append((words, relative))
    return passages


def _contains_words(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    if len(needle) > len(haystack):
        return False
    width = len(needle)
    return any(haystack[index : index + width] == needle for index in range(len(haystack) - width + 1))


def scan_repository(root: Path, paths: list[Path] | None = None) -> ScanResult:
    root = root.resolve()
    candidates = paths if paths is not None else _public_markdown_paths(root)
    private_passages = _private_passages(root)
    findings: list[Finding] = []

    for path in candidates:
        path = path.resolve()
        try:
            relative = path.relative_to(root)
        except ValueError:
            findings.append(Finding("FAIL", "outside-root", str(path), 0, "Public scan path is outside the repository."))
            continue
        if relative.is_relative_to(Path("Pro")) or relative.is_relative_to(SELF_PROTECTED_PREFIX):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            findings.append(Finding("FAIL", "unreadable-file", relative.as_posix(), 0, str(error)))
            continue

        for line_number, paragraph in _paragraphs(text):
            private_path = PRIVATE_PATH.search(paragraph)
            if private_path:
                findings.append(
                    Finding(
                        "FAIL",
                        "private-path",
                        relative.as_posix(),
                        line_number,
                        "Public content references a private path outside Pro/docs/*.md.",
                    )
                )

            if PRO_ASSERTION.search(paragraph) and IMPLEMENTATION_SIGNAL.search(paragraph):
                findings.append(
                    Finding(
                        "FAIL",
                        "implementation-detail",
                        relative.as_posix(),
                        line_number,
                        "Public content makes a Pro implementation assertion.",
                    )
                )

            public_words = _normalized_words(paragraph)
            if len(public_words) < MIN_COPY_WORDS:
                continue
            for private_words, private_path_name in private_passages:
                if _contains_words(public_words, private_words):
                    findings.append(
                        Finding(
                            "FAIL",
                            "copied-private-passage",
                            relative.as_posix(),
                            line_number,
                            f"Public content duplicates a passage from {private_path_name}.",
                        )
                    )
                    break

    return ScanResult(findings)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("paths", nargs="*", type=Path)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    root = args.root.resolve()
    paths = [path if path.is_absolute() else root / path for path in args.paths] or None
    result = scan_repository(root, paths)
    for item in result.findings:
        print(f"{item.level} {item.path}:{item.line} [{item.code}] {item.message}")
    status = {0: "PASS", 1: "FAIL", 2: "REVIEW"}[result.exit_code]
    print(f"{status}: auxiliary public-content lint; manual boundary review required")
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
