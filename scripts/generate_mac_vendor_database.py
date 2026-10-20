#!/usr/bin/env python3
"""Generate WiFi Lens's compact MAC-prefix-to-organization mapping."""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import re
import urllib.request
import warnings
from datetime import datetime, timezone
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Iterable, TextIO


@dataclass(frozen=True)
class RegistrySpec:
    registry: str
    prefix_length: int


REGISTRIES = {
    "https://standards-oui.ieee.org/oui/oui.csv": RegistrySpec("MA-L", 24),
    "https://standards-oui.ieee.org/oui28/mam.csv": RegistrySpec("MA-M", 28),
    "https://standards-oui.ieee.org/oui36/oui36.csv": RegistrySpec("MA-S", 36),
    "https://standards-oui.ieee.org/iab/iab.csv": RegistrySpec("IAB", 36),
}

def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def normalize_iso_override(value: str, argument_name: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"{argument_name} must use ISO 8601 format") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_last_modified(value: str | None) -> str | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def normalize_organization(value: str) -> str:
    return " ".join(html.unescape(value).split())


def parse_registry(stream: TextIO, spec: RegistrySpec) -> list[dict[str, object]]:
    reader = csv.DictReader(stream)
    required_columns = {"Registry", "Assignment", "Organization Name"}
    if not required_columns.issubset(reader.fieldnames or []):
        raise ValueError(f"missing required columns for {spec.registry}")

    expected_hex_count = spec.prefix_length // 4
    entries: list[dict[str, object]] = []
    for row in reader:
        if row.get("Registry", "").strip() != spec.registry:
            raise ValueError(f"unexpected registry: {row.get('Registry')!r}")

        prefix = re.sub(r"[^0-9A-Fa-f]", "", row.get("Assignment", "")).upper()
        if len(prefix) != expected_hex_count or not re.fullmatch(r"[0-9A-F]+", prefix):
            raise ValueError(f"invalid {spec.registry} assignment: {prefix!r}")

        organization = normalize_organization(row.get("Organization Name", ""))
        if not organization or organization.casefold() == "private":
            continue

        entries.append(
            {
                "prefix": prefix,
                "prefixLength": spec.prefix_length,
                "organization": organization,
            }
        )
    return entries


def build_database(
    entries: Iterable[dict[str, object]],
    retrieved_at: str,
    sources: list[dict[str, str | None]],
    source_updated_at: str | None = None,
) -> dict[str, object]:
    unique: dict[tuple[int, str], dict[str, object]] = {}
    ambiguous: set[tuple[int, str]] = set()
    for entry in entries:
        key = (int(entry["prefixLength"]), str(entry["prefix"]))
        if key in ambiguous:
            continue
        existing = unique.get(key)
        if existing is not None and existing["organization"] != entry["organization"]:
            unique.pop(key)
            ambiguous.add(key)
            continue
        unique[key] = entry

    ordered = sorted(
        unique.values(),
        key=lambda entry: (-int(entry["prefixLength"]), str(entry["prefix"])),
    )
    available_source_dates = [
        source["lastModifiedAt"]
        for source in sources
        if source.get("lastModifiedAt")
    ]
    if not source_updated_at and not available_source_dates:
        raise ValueError("all IEEE sources are missing Last-Modified and no override was provided")
    if len(available_source_dates) < len(sources):
        warnings.warn(
            "one or more IEEE sources are missing Last-Modified; sourceUpdatedAt uses available values",
            RuntimeWarning,
            stacklevel=2,
        )
    return {
        "schemaVersion": 1,
        "retrievedAt": retrieved_at,
        "sourceUpdatedAt": source_updated_at or max(available_source_dates),
        "sources": sorted(sources, key=lambda source: source["url"]),
        "ambiguousPrefixCount": len(ambiguous),
        "notice": (
            "Derived from IEEE Registration Authority public listings. "
            "Organizations are address-block registrants and may differ from device brands."
        ),
        "entries": ordered,
    }


def download_text(url: str) -> tuple[TextIO, str | None]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "WiFiLens-MACVendorDatabaseGenerator/1.0 "
                "(+https://github.com/ShiinaLabs/wifi-lens)"
            )
        },
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        content = response.read().decode("utf-8-sig")
        return io.StringIO(content), parse_last_modified(response.headers.get("Last-Modified"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--retrieved-at", help="Override retrieval time in ISO 8601 format")
    parser.add_argument(
        "--source-updated-at",
        help="Override IEEE source update time in ISO 8601 format",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "WiFiLens/Sources/WiFiLens/Resources/mac-vendor-database.json",
        help="Output resource path (defaults to the bundled app resource)",
    )
    args = parser.parse_args()

    try:
        retrieved_at = normalize_iso_override(args.retrieved_at, "--retrieved-at") if args.retrieved_at else utc_now_iso()
        source_updated_at = (
            normalize_iso_override(args.source_updated_at, "--source-updated-at")
            if args.source_updated_at
            else None
        )
    except ValueError as error:
        parser.error(str(error))

    all_entries: list[dict[str, object]] = []
    sources: list[dict[str, str | None]] = []
    for url, spec in REGISTRIES.items():
        stream, last_modified_at = download_text(url)
        with stream:
            all_entries.extend(parse_registry(stream, spec))
        sources.append({"url": url, "lastModifiedAt": last_modified_at})

    database = build_database(
        all_entries,
        retrieved_at,
        sources,
        source_updated_at=source_updated_at,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            database,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
