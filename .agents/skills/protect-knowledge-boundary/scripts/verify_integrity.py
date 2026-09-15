#!/usr/bin/env python3
"""Verify the integrity of the protected boundary-review instructions.

This checks instruction assets only. It does not evaluate whether an OSS/Pro
module relationship is safe.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import NamedTuple


EXPECTED_SYMLINK = "../../.agents/skills/protect-knowledge-boundary"
REQUIRED_PROTECTED_ASSETS = frozenset(
    {
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
)
ANCHOR = re.compile(
    r"<!-- knowledge-boundary-gate:start -->\n"
    r"Complete the manual module-by-module edition-boundary review described in "
    r"`\.agents/skills/protect-knowledge-boundary/SKILL\.md` before completing "
    r"knowledge-boundary changes\.\n"
    r"Integrity manifest SHA-256: `([0-9a-f]{64})`\n"
    r"<!-- knowledge-boundary-gate:end -->"
)


class Finding(NamedTuple):
    code: str
    message: str


class VerificationResult:
    def __init__(self, findings: list[Finding]):
        self.findings = findings

    @property
    def exit_code(self) -> int:
        return 1 if self.findings else 0


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parse_manifest(root: Path, manifest: Path, findings: list[Finding]):
    entries: list[tuple[str, Path]] = []
    try:
        lines = manifest.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        findings.append(Finding("missing-manifest", f"Cannot read integrity manifest: {error}"))
        return entries

    for line_number, line in enumerate(lines, 1):
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            findings.append(Finding("invalid-manifest", f"Invalid manifest line {line_number}."))
            continue
        relative = PurePosixPath(match.group(2))
        if relative.is_absolute() or ".." in relative.parts:
            findings.append(Finding("invalid-manifest-path", f"Unsafe manifest path on line {line_number}."))
            continue
        entries.append((match.group(1), root.joinpath(*relative.parts)))
    if not entries and not findings:
        findings.append(Finding("empty-manifest", "Integrity manifest has no protected assets."))
    return entries


def verify(root: Path, manifest: Path) -> VerificationResult:
    root = root.resolve()
    manifest = manifest.resolve()
    findings: list[Finding] = []
    entries = _parse_manifest(root, manifest, findings)

    listed_assets = {path.relative_to(root).as_posix() for _, path in entries}
    for missing in sorted(REQUIRED_PROTECTED_ASSETS - listed_assets):
        findings.append(
            Finding("missing-manifest-entry", f"Required protected asset is not listed: {missing}")
        )

    for expected, path in entries:
        if not path.is_file():
            findings.append(Finding("missing-asset", f"Protected asset is missing: {path.relative_to(root)}"))
        elif _sha256(path) != expected:
            findings.append(Finding("hash-mismatch", f"Protected asset changed: {path.relative_to(root)}"))

    agents_path = root / "AGENTS.md"
    try:
        agents_text = agents_path.read_text(encoding="utf-8")
    except OSError:
        agents_text = ""
    anchor = ANCHOR.search(agents_text)
    if anchor is None:
        findings.append(Finding("missing-anchor", "AGENTS.md knowledge-boundary gate is missing or changed."))
    elif manifest.is_file() and _sha256(manifest) != anchor.group(1):
        findings.append(Finding("manifest-anchor-mismatch", "AGENTS.md does not pin the current integrity manifest."))

    symlink = root / ".claude/skills/protect-knowledge-boundary"
    if not symlink.is_symlink() or os.readlink(symlink) != EXPECTED_SYMLINK:
        findings.append(Finding("invalid-symlink", "Claude Skill symlink is missing or points to the wrong target."))

    return VerificationResult(findings)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--manifest", type=Path)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    root = args.root.resolve()
    manifest = args.manifest or root / ".agents/integrity/protected-assets.sha256"
    result = verify(root, manifest)
    for item in result.findings:
        print(f"FAIL [{item.code}] {item.message}")
    status = "PASS" if result.exit_code == 0 else "FAIL"
    print(f"{status}: boundary-review instruction integrity")
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
