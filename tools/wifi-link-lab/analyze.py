#!/usr/bin/env python3
"""Offline analyzer for WiFi Link Lab JSONL experiments."""
from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
import json
import math
import re
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

SCHEMA_VERSION = 1
DATA_FILES = ("observations.jsonl", "events.jsonl", "markers.jsonl")
ZIP_ALLOWLIST = ("environment.json", *DATA_FILES, "summary.md")
STATE_FIELDS = (
    "interfaceEnumerated", "interfaceUp", "interfaceRunning", "ipv4Present", "ipv6Present",
    "scLinkKeyPresent", "scLinkActive", "scLinkDetaching", "scIPv4KeyPresent", "scIPv6KeyPresent",
    "nwPathUsesWiFi", "ssidReadable", "bssidReadable", "channelReadable", "flagsConflict",
    "powerOnRaw", "serviceActiveRaw",
)
IDENTITY_TAG_FIELDS = ("ssidTag", "bssidTag")
SCENARIO_ROWS = (
    ("Normal connection", ("normal connection", "normal", "connected")),
    ("Wi-Fi radio off", ("wifi radio off", "radio off", "turn wifi off", "wi-fi off", "radio toggle")),
    ("AP lost while Wi-Fi on", ("ap lost", "access point lost", "lost ap", "ap unavailable", "access point disappears", "access point unavailable")),
    ("Recovery", ("recovery", "recover", "restore connection", "radio on recovery", "access point recovery")),
    ("Network switch", ("network switch", "switch network", "roam", "roaming", "network a to network b")),
)


def _parse_time(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except (ValueError, OverflowError):
        return None


def _mono(record: dict[str, Any]) -> int | None:
    value = record.get("monotonicNanoseconds")
    if isinstance(value, bool):
        return None
    try:
        result = int(value)
        return result if result >= 0 else None
    except (TypeError, ValueError, OverflowError):
        return None


def _time_key(record: dict[str, Any]) -> tuple[float, int, int]:
    timestamp = _parse_time(record.get("time"))
    utc = timestamp.timestamp() if timestamp else math.inf
    mono = _mono(record)
    return utc, mono if mono is not None else 2**63 - 1, int(record.get("_line", 0))


def read_jsonl(path: Path) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    records: list[dict[str, Any]] = []
    diagnostics: list[str] = []
    if not path.exists():
        diagnostics.append(f"Missing input file: {path.name}")
        return records, diagnostics, []
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        diagnostics.append(f"Could not read {path.name}: {type(exc).__name__}")
        return records, diagnostics, []
    raw_lines = text.splitlines()
    for number, line in enumerate(raw_lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError("JSON line is not an object")
            value["_line"] = number
            records.append(value)
        except (json.JSONDecodeError, ValueError):
            suffix = " (possibly truncated final line)" if number == len(raw_lines) and not line.rstrip().endswith("}") else ""
            diagnostics.append(f"Malformed {path.name} line {number}{suffix}; skipped, remaining lines were still read")
    return records, diagnostics, raw_lines


def _secret_key(key: str) -> bool:
    normalized = re.sub(r"[^a-z0-9]", "", key.lower())
    if normalized.endswith("tag") or normalized.endswith("keypresent") or normalized.endswith("readable"):
        return False
    return any(token in normalized for token in (
        "ssid", "bssid", "mac", "ipv4", "ipv6", "ipaddress", "routeraddress", "hostname", "serialnumber",
        "location", "networkname", "rawnetwork", "credential", "apikey", "token", "password",
    ))


def collect_sensitive_values(values: Iterable[Any]) -> set[str]:
    secrets: set[str] = set()

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "_line":
                    continue
                normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
                if _secret_key(str(key)) and isinstance(item, str) and item.strip() and not normalized.endswith(("tag", "keypresent", "readable")):
                    secrets.add(item.strip())
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    for value in values:
        walk(value)
    return {secret for secret in secrets if len(secret) >= 2}


def collect_raw_line_secrets(raw_lines: Iterable[str]) -> set[str]:
    """Extract sensitive values from valid or damaged JSON-like key/value text."""
    secrets: set[str] = set()
    key_value = re.compile(r'''["']?([A-Za-z_][\w.-]*)["']?\s*:\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^,}\s]+))''')
    for line in raw_lines:
        for match in key_value.finditer(line):
            key, double, single, bare = match.groups()
            value = double if double is not None else single if single is not None else bare
            normalized_key = re.sub(r"[^a-z0-9]", "", key.lower())
            if (_secret_key(key) and not normalized_key.endswith(("tag", "keypresent", "readable"))
                    and value and value.strip().lower() not in {"true", "false", "null"} and len(value.strip()) >= 2):
                try:
                    decoded = json.loads('"' + value + '"') if double is not None else value
                except json.JSONDecodeError:
                    decoded = value.replace("\\\\", "")
                if isinstance(decoded, str) and len(decoded.strip()) >= 2:
                    secrets.add(decoded.strip())
    return secrets


def _redact_text(text: str, secrets: set[str]) -> str:
    for secret in sorted(secrets, key=len, reverse=True):
        text = re.sub(re.escape(secret), "[REDACTED]", text, flags=re.IGNORECASE)
    # Catch common identifiers even when their source key was malformed or unexpected.
    text = re.sub(r"(?<![\w])(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}(?![\w])", "[REDACTED]", text)
    text = re.sub(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])", lambda m: "[REDACTED]" if _is_ip(m.group()) else m.group(), text)
    text = re.sub(r'("(?:[^"\\]*(?:ssid|bssid|mac|ipaddress|routeraddress|hostname|serialnumber|location|networkname)[^"\\]*)"\s*:\s*)"(?:\\.|[^"\\])*"', r'\1"[REDACTED]"', text, flags=re.IGNORECASE)
    return text


def _is_ip(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def sanitize_record(record: dict[str, Any], secrets: set[str]) -> dict[str, Any]:
    def clean(value: Any, key: str = "") -> Any:
        if _secret_key(key):
            normalized = re.sub(r"[^a-z0-9]", "", key.lower())
            if not normalized.endswith(("tag", "keypresent", "readable")) and value is not None:
                return "[REDACTED]"
        if isinstance(value, dict):
            return {str(k): clean(v, str(k)) for k, v in value.items() if k != "_line"}
        if isinstance(value, list):
            return [clean(item, key) for item in value]
        if isinstance(value, str):
            return _redact_text(value, secrets)
        return value
    return clean(record)


def _duration_ms(sample: dict[str, Any]) -> float | None:
    start, end = _parse_time(sample.get("sampleStartedAt")), _parse_time(sample.get("sampleEndedAt"))
    if start and end:
        ms = (end - start).total_seconds() * 1000
        return ms if ms >= 0 else None
    return None


def _is_valid_sample(record: dict[str, Any]) -> bool:
    start_mono = record.get("sampleStartMonotonicNanoseconds")
    try:
        valid_start_mono = not isinstance(start_mono, bool) and int(start_mono) >= 0
    except (TypeError, ValueError, OverflowError):
        valid_start_mono = False
    return (record.get("kind") == "sample" and record.get("schemaVersion") == SCHEMA_VERSION
            and _parse_time(record.get("time")) is not None and _mono(record) is not None
            and valid_start_mono and record.get("trigger") in {"timer", "notification", "startup"}
            and _duration_ms(record) is not None)


def _is_notification(event: dict[str, Any]) -> bool:
    event_type = str(event.get("eventType", "")).lower()
    source = str(event.get("source", "")).lower()
    if "notification" in f"{source} {event_type}":
        return True
    if event_type in {"registration", "unregistration", "stopped", "interfacechanged", "interfaceunavailable"}:
        return False
    return event_type in {
        "powerdidchange", "ssiddidchange", "bssiddidchange", "linkdidchange", "modedidchange",
        "clientconnectioninterrupted", "clientconnectioninvalidated", "dynamicstorechanged",
        "pathupdate", "willsleep", "didwake",
    }


def _is_registration_event(event: dict[str, Any]) -> bool:
    event_type = str(event.get("eventType", "")).lower()
    return "registration" in event_type and not event_type.startswith("unregistration")


def _registration_outcome(event: dict[str, Any]) -> str:
    if event.get("success") is True or any(word in str(event.get("eventType", "")).lower() for word in ("success", "registered")):
        return "success"
    if event.get("success") is False or any(word in str(event.get("eventType", "")).lower() for word in ("fail", "error", "denied")):
        return "failure"
    return "unknown"


def scenario_intervals(markers: list[dict[str, Any]]) -> dict[str, list[tuple[float, float | None]]]:
    result: dict[str, list[tuple[float, float | None]]] = defaultdict(list)
    open_markers: dict[str, float] = {}
    for marker in sorted(markers, key=_time_key):
        stamp = _parse_time(marker.get("time"))
        if not stamp:
            continue
        mono = _mono(marker)
        coordinate = mono if mono is not None else stamp.timestamp() * 1e9
        scenario = str(marker.get("scenarioName") or "(unnamed scenario)")
        marker_type = str(marker.get("markerType") or "").lower()
        if marker_type in {"scenario_started", "scenariostarted", "start", "begin", "scenario_begin"}:
            open_markers[scenario] = coordinate
        elif marker_type in {
            "scenario_completed", "scenariocompleted", "end", "stop", "finish", "close",
            "scenario_interrupted", "scenariointerrupted", "experiment_interrupted", "experimentinterrupted",
            "scenario_skipped", "scenariosskipped", "scenarioskipped",
        }:
            start = open_markers.pop(scenario, None)
            if start is not None:
                result[scenario].append((start, coordinate))
    for scenario, start in open_markers.items():
        result[scenario].append((start, None))
    return result


def action_intervals(markers: list[dict[str, Any]]) -> dict[str, list[tuple[str, float, float | None]]]:
    """Return measured operator-action windows, ending at observation completion."""
    result: dict[str, list[tuple[str, float, float | None]]] = defaultdict(list)
    open_actions: dict[str, tuple[str, float]] = {}
    closing_markers = {
        "observationcompleted", "scenariointerrupted", "experimentinterrupted",
        "scenarioskipped", "scenariocompleted",
    }
    for marker in sorted(markers, key=_time_key):
        stamp = _parse_time(marker.get("time"))
        if not stamp:
            continue
        mono = _mono(marker)
        coordinate = mono if mono is not None else stamp.timestamp() * 1e9
        scenario = str(marker.get("scenarioName") or "(unnamed scenario)")
        marker_type = re.sub(r"[^a-z]", "", str(marker.get("markerType") or "").lower())
        if marker_type == "operatoractionstarted":
            open_actions[scenario] = (str(marker.get("actionName") or ""), coordinate)
        elif marker_type in closing_markers:
            opened = open_actions.pop(scenario, None)
            if opened is not None:
                action_name, start = opened
                result[scenario].append((action_name, start, coordinate))
    for scenario, (action_name, start) in open_actions.items():
        result[scenario].append((action_name, start, None))
    return result


def _action_family(scenario: str, action: str) -> str | None:
    scenario_family = _scenario_family(scenario)
    text = re.sub(r"[^a-z0-9一-鿿]+", " ", action.lower()).strip()
    if scenario_family == "Normal connection":
        return scenario_family
    if scenario_family == "Network switch":
        return scenario_family
    recovery_terms = ("恢复", "重新开启", "重新连接", "recovery", "restore", "reconnect", "radio on")
    if scenario_family in {"Wi-Fi radio off", "AP lost while Wi-Fi on"} and any(term in text for term in recovery_terms):
        return "Recovery"
    unavailable_terms = ("关闭", "关闭测试接入点", "不可用", "无线电关闭", "wifi off", "radio off", "turn wifi off", "unavailable", "disappear")
    if scenario_family == "Wi-Fi radio off" and any(term in text for term in unavailable_terms):
        return "Wi-Fi radio off"
    if scenario_family == "AP lost while Wi-Fi on" and any(term in text for term in unavailable_terms):
        return "AP lost while Wi-Fi on"
    if scenario_family is None and any(term in text for term in recovery_terms):
        return "Recovery"
    return None


def _action_samples_and_events(
    family: str,
    action_spans: dict[str, list[tuple[str, float, float | None]]],
    samples: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    spans = [
        (scenario, start, end)
        for scenario, actions in action_spans.items()
        for action, start, end in actions
        if _action_family(scenario, action) == family
    ]
    selected_samples = [sample for sample in samples if any(_in_interval(sample, (start, end)) for _, start, end in spans)]
    selected_events = [event for event in events if any(_in_interval(event, (start, end)) for _, start, end in spans)]
    return selected_samples, selected_events


def _has_action_markers(markers: list[dict[str, Any]]) -> bool:
    return any(re.sub(r"[^a-z]", "", str(m.get("markerType") or "").lower()) == "operatoractionstarted" for m in markers)


def _scenario_fallback_samples_and_events(
    family: str,
    intervals: dict[str, list[tuple[float, float | None]]],
    samples: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    names = [name for name in intervals if _scenario_family(name) == family]
    spans = [span for name in names for span in intervals[name]]
    return (
        [sample for sample in samples if any(_in_interval(sample, span) for span in spans)],
        [event for event in events if any(_in_interval(event, span) for span in spans)],
    )


def _coordinate(record: dict[str, Any]) -> float:
    mono = _mono(record)
    stamp = _parse_time(record.get("time"))
    return float(mono) if mono is not None else stamp.timestamp() * 1e9 if stamp else math.nan


def _in_interval(record: dict[str, Any], interval: tuple[float, float | None]) -> bool:
    coordinate = _coordinate(record)
    start, end = interval
    return coordinate >= start and (end is None or coordinate <= end)


def _mode(sample: dict[str, Any]) -> str:
    value = next((sample.get(key) for key in ("wifiMode", "mode", "interfaceMode", "interfaceType") if sample.get(key) is not None), None)
    text = str(value).strip().lower() if value is not None else ""
    if text in {"station", "client", "managed", "infrastructure"}:
        return "station"
    if text in {"none", "off", "disabled", "0"}:
        return "none"
    return "未观测"


def _state(sample: dict[str, Any], *keys: str) -> Any:
    return next((sample.get(key) for key in keys if key in sample), None)


def _scenario_family(name: str) -> str | None:
    normalized = re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()
    for label, aliases in SCENARIO_ROWS:
        if any(alias in normalized for alias in aliases):
            return label
    return None


def analyze(environment: Any, observations: list[dict[str, Any]], events: list[dict[str, Any]], markers: list[dict[str, Any]], diagnostics: list[str]) -> str:
    samples = sorted((r for r in observations if _is_valid_sample(r)), key=_time_key)
    valid_events = sorted((r for r in events if _parse_time(r.get("time")) is not None and _mono(r) is not None), key=_time_key)
    valid_markers = sorted((r for r in markers if _parse_time(r.get("time")) is not None), key=_time_key)
    malformed = len(observations) - len(samples)
    if malformed:
        diagnostics.append(f"{malformed} observation record(s) were not valid schema-v{SCHEMA_VERSION} timestamped samples")

    state_counts: dict[str, Counter[str]] = {}
    first_changes: dict[str, str] = {}
    for field in STATE_FIELDS:
        counts: Counter[str] = Counter()
        prior: Any = None
        for sample in samples:
            value = sample.get(field)
            counts["true" if value is True else "false" if value is False else "unknown"] += 1
            if value is not None and prior is not None and value != prior and field not in first_changes:
                first_changes[field] = str(sample.get("time", "unknown"))
            if value is not None:
                prior = value
        state_counts[field] = counts

    identity_tag_changes = Counter()
    first_identity_tag_changes: dict[str, str] = {}
    for previous, sample in zip(samples, samples[1:]):
        for field in IDENTITY_TAG_FIELDS:
            before, after = previous.get(field), sample.get(field)
            if before != after and (before is not None or after is not None):
                identity_tag_changes[field] += 1
                first_identity_tag_changes.setdefault(field, str(sample.get("time", "unknown")))

    gaps = [(int(_mono(r)) - int(_mono(l))) / 1e6 for l, r in zip(samples, samples[1:]) if _mono(r) >= _mono(l)]
    durations = [d for sample in samples if (d := _duration_ms(sample)) is not None]
    failures = [s for s in samples if isinstance(s.get("errorsByField"), dict) and s["errorsByField"]]
    intervals = scenario_intervals(valid_markers)
    action_spans = action_intervals(valid_markers)
    has_action_markers = _has_action_markers(valid_markers)
    scenario_stats: dict[str, dict[str, Any]] = {}
    scenario_membership: dict[str, set[str]] = defaultdict(set)
    for scenario, spans in intervals.items():
        in_scenario = [s for s in samples if any(_in_interval(s, span) for span in spans)]
        gs = [(int(_mono(r)) - int(_mono(l))) / 1e6 for l, r in zip(in_scenario, in_scenario[1:]) if _mono(r) >= _mono(l)]
        ds = [d for s in in_scenario if (d := _duration_ms(s)) is not None]
        scenario_stats[scenario] = {"samples": in_scenario, "failures": sum(bool(s.get("errorsByField")) for s in in_scenario),
                                    "max_gap": max(gs) if gs else None, "mean_duration": sum(ds) / len(ds) if ds else None}
        for event in valid_events:
            if any(_in_interval(event, span) for span in spans):
                scenario_membership[scenario].add(str(event.get("_line", "")))

    event_latencies: list[float] = []
    notification_latencies: list[float] = []
    notification_unfollowed = 0
    for index, event in enumerate(valid_events):
        next_sample = next((s for s in samples if _coordinate(s) >= _coordinate(event)), None)
        if next_sample:
            latency = (_mono(next_sample) - _mono(event)) / 1e6
            if latency >= 0:
                event_latencies.append(latency)
                if _is_notification(event):
                    notification_latencies.append(latency)
        if _is_notification(event):
            before = next((s for s in reversed(samples) if _coordinate(s) < _coordinate(event)), None)
            after = next((s for s in samples if _coordinate(s) >= _coordinate(event)), None)
            changed = before is not None and after is not None and any(before.get(f) != after.get(f) for f in STATE_FIELDS if before.get(f) is not None or after.get(f) is not None)
            if not changed:
                notification_unfollowed += 1

    event_counts = Counter((str(e.get("source") or "unknown"), str(e.get("eventType") or "unknown")) for e in valid_events)
    source_counts = Counter()
    for event in valid_events:
        src = str(event.get("source") or "unknown").lower()
        family = "CoreWLAN" if "corewlan" in src else "SystemConfiguration" if "systemconfiguration" in src or src.startswith("sc") else "NWPath" if "nwpath" in src or "networkpath" in src else None
        if family:
            source_counts[family] += 1
    registration = Counter(_registration_outcome(e) for e in valid_events if _is_registration_event(e))
    contradictions: list[str] = []
    changes_by_sample: list[bool] = []
    for previous, sample in zip(samples, samples[1:]):
        changes_by_sample.append(any(previous.get(f) != sample.get(f) for f in STATE_FIELDS if previous.get(f) is not None or sample.get(f) is not None))
    for sample in samples:
        t = sample.get("time", "unknown")
        mode = _mode(sample)
        if mode == "station" and sample.get("scLinkActive") is False:
            contradictions.append(f"{t}: station mode conflicts with Link.Active=false")
        if mode == "none" and sample.get("scLinkActive") is True:
            contradictions.append(f"{t}: mode none conflicts with Link.Active=true")
        link_active = sample.get("scLinkActive") is True or sample.get("nwPathUsesWiFi") is True
        if sample.get("powerOnRaw") is False and link_active:
            contradictions.append(f"{t}: power off conflicts with an active Wi-Fi link")
        if sample.get("ssidReadable") is False and mode == "station":
            contradictions.append(f"{t}: SSID unreadable conflicts with station mode")
        if sample.get("nwPathUsesWiFi") is False and mode == "station":
            contradictions.append(f"{t}: no Wi-Fi NWPath conflicts with station mode")
        pairs = (("interfaceUp", False, "interfaceRunning", True), ("interfaceEnumerated", False, "interfaceUp", True),
                 ("scLinkKeyPresent", False, "scLinkActive", True), ("nwPathUsesWiFi", True, "nwPathStatus", "unsatisfied"))
        for a, av, b, bv in pairs:
            if sample.get(a) is av and sample.get(b) == bv:
                contradictions.append(f"{t}: {a}={av} conflicts with {b}={bv}")
    for left, right in zip(samples, samples[1:]):
        if left.get("interfaceEnumerated") is True and right.get("interfaceEnumerated") is False:
            contradictions.append(f"{right['time']}: interface disappeared")
        if left.get("interfaceEnumerated") is False and right.get("interfaceEnumerated") is True:
            contradictions.append(f"{right['time']}: interface reappeared")
    open_operator_actions: dict[tuple[str, str], float] = {}
    for marker in valid_markers:
        marker_type = re.sub(r"[^a-z]", "", str(marker.get("markerType", "")).lower())
        scenario = str(marker.get("scenarioName") or "(unnamed scenario)")
        action_name = str(marker.get("actionName") or "")
        key = (scenario, action_name)
        if marker_type == "operatoractionstarted":
            open_operator_actions[key] = _coordinate(marker)
            continue
        if marker_type == "operatoractioncompleted" and key in open_operator_actions:
            start = open_operator_actions.pop(key)
            normalized_action = action_name.lower()
            if any(word in normalized_action for word in ("观察", "基线", "确认", "记录", "observe", "baseline", "confirm", "record")):
                continue
            before = next((s for s in reversed(samples) if _coordinate(s) < start), None)
            following = next((s for s in samples if _coordinate(s) >= _coordinate(marker)), None)
        elif marker_type == "operatoraction":
            before = next((s for s in reversed(samples) if _coordinate(s) < _coordinate(marker)), None)
            following = next((s for s in samples if _coordinate(s) >= _coordinate(marker)), None)
        else:
            continue
        related = before is not None and following is not None and any(
            before.get(f) != following.get(f)
            for f in STATE_FIELDS
            if before.get(f) is not None or following.get(f) is not None
        )
        if not related:
            contradictions.append(f"{marker.get('time')}: operator action has no related observed state change")
    if notification_unfollowed:
        contradictions.append(f"{notification_unfollowed} notification(s) had no following state change")

    registration_text = f"success {registration['success']}, failure {registration['failure']}, unknown {registration['unknown']}" if registration else "未观测"
    skipped_count = sum("skip" in str(m.get("markerType", "")).lower() for m in valid_markers)
    interrupted_count = sum("interrupt" in str(m.get("markerType", "")).lower() for m in valid_markers)
    lines = ["# WiFi Link Lab Experiment Report", "", "> Analysis is offline and descriptive. It does not conclude that Wi-Fi disconnected.", "", "## Experiment status", "", "**Waiting for a real-device experiment.** Values below are measured from available records; absent evidence is reported as 未观测, never as an expected result.", "", f"- Environment metadata: {'available' if isinstance(environment, dict) else '未观测'}", f"- Valid samples: {len(samples)}", f"- Valid events: {len(valid_events)}", f"- Skipped scenario marker(s): {skipped_count} (not counted as passes)", f"- Interrupted/incomplete marker(s): {interrupted_count} (not counted as passes)", f"- Sample failures (non-empty errorsByField): {len(failures)}", f"- Malformed/truncated lines or records: {len(diagnostics)}"]
    lines += ["", "## Measured values", "", "| Measure | Value |", "|---|---:|"]
    metrics = (("Maximum sample interval (ms)", f"{max(gaps):.3f}" if gaps else "未观测"),
               ("Mean sample duration (ms)", f"{sum(durations)/len(durations):.3f}" if durations else "未观测"),
               ("SSID tag changes", str(identity_tag_changes["ssidTag"])),
               ("BSSID tag changes", str(identity_tag_changes["bssidTag"])),
               ("First SSID tag change", first_identity_tag_changes.get("ssidTag", "未观测")),
               ("First BSSID tag change", first_identity_tag_changes.get("bssidTag", "未观测")),
               ("Notification to next valid sample (mean ms)", f"{sum(notification_latencies)/len(notification_latencies):.3f}" if notification_latencies else "未观测"),
               ("Event to next valid sample (mean ms)", f"{sum(event_latencies)/len(event_latencies):.3f}" if event_latencies else "未观测"),
               ("Events linked to a following sample", f"{sum(any(_coordinate(s) >= _coordinate(e) for s in samples) for e in valid_events)}/{len(valid_events)}" if valid_events else "未观测"),
               ("Listener registration failures (nonfatal events)", str(registration["failure"]) if registration else "未观测"),
               ("Registration outcomes", registration_text),
               ("Notifications without following state change", str(notification_unfollowed) if any(_is_notification(e) for e in valid_events) else "未观测"))
    lines.extend(f"| {label} | {value} |" for label, value in metrics)
    lines += ["", "## Fixed scenario measurements", "", "| Scenario | Samples | Station / none | Power on | Service active | Link.Active true / false / null | Flag/path changes | Registration outcomes | CoreWLAN / SystemConfiguration / NWPath events | First field change | Event-to-next-sample latency (mean ms) | Events related to marker interval |", "|---|---:|---|---|---|---|---:|---|---|---|---:|---:|"]
    for label, _aliases in SCENARIO_ROWS:
        if has_action_markers:
            selected, evs = _action_samples_and_events(label, action_spans, samples, valid_events)
        else:
            selected, evs = _scenario_fallback_samples_and_events(label, intervals, samples, valid_events)
        if not selected:
            lines.append(f"| {label} | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 | 未观测 |")
            continue
        modes = Counter(_mode(s) for s in selected)
        power = Counter("true" if s.get("powerOnRaw") is True else "false" if s.get("powerOnRaw") is False else "null" for s in selected)
        service = Counter("true" if s.get("serviceActiveRaw") is True else "false" if s.get("serviceActiveRaw") is False else "null" for s in selected)
        active = Counter("true" if s.get("scLinkActive") is True else "false" if s.get("scLinkActive") is False else "null" for s in selected)
        flags_changes = sum(1 for a, b in zip(selected, selected[1:]) if any(a.get(f) != b.get(f) for f in ("flagsConflict", "nwPathStatus", "nwPathUsesWiFi") if a.get(f) is not None or b.get(f) is not None))
        ec = Counter()
        for e in evs:
            src = str(e.get("source", "")).lower()
            family = "CoreWLAN" if "corewlan" in src else "SystemConfiguration" if "systemconfiguration" in src or src.startswith("sc") else "NWPath" if "nwpath" in src or "networkpath" in src else None
            if family: ec[family] += 1
        latency = []
        for e in evs:
            nxt = next((s for s in selected if _coordinate(s) >= _coordinate(e)), None)
            if nxt and _mono(nxt) >= _mono(e): latency.append((_mono(nxt) - _mono(e)) / 1e6)
        change = None
        for before, after in zip(selected, selected[1:]):
            changed_field = next((field for field in (*STATE_FIELDS, *IDENTITY_TAG_FIELDS)
                                  if before.get(field) != after.get(field)
                                  and (before.get(field) is not None or after.get(field) is not None)), None)
            if changed_field:
                change = f"{changed_field} @ {after['time']}"
                break
        reg = Counter(_registration_outcome(e) for e in evs if _is_registration_event(e))
        lines.append(f"| {label} | {len(selected)} | station {modes['station']} / none {modes['none']} | true {power['true']} / false {power['false']} / null {power['null']} | true {service['true']} / false {service['false']} / null {service['null']} | {active['true']} / {active['false']} / {active['null']} | {flags_changes} | success {reg['success']} / failure {reg['failure']} / unknown {reg['unknown']} | {ec['CoreWLAN']} / {ec['SystemConfiguration']} / {ec['NWPath']} | {change or '未观测'} | {f'{sum(latency)/len(latency):.3f}' if latency else '未观测'} | {len(evs)} |")
    lines += ["", "## Scenario marker intervals", "", "| Scenario | Samples | Failures | Maximum interval (ms) | Mean duration (ms) |", "|---|---:|---:|---:|---:|"]
    if scenario_stats:
        for name, stats in scenario_stats.items():
            maximum = f"{stats['max_gap']:.3f}" if stats["max_gap"] is not None else "未观测"
            mean_duration = f"{stats['mean_duration']:.3f}" if stats["mean_duration"] is not None else "未观测"
            lines.append(f"| {name} | {len(stats['samples'])} | {stats['failures']} | {maximum} | {mean_duration} |")
    else:
        lines.append("| 未观测 | 未观测 | 未观测 | 未观测 | 未观测 |")
    lines += ["", "## Observed state counts", "", "| Field | True | False | Unknown / missing | First observed change |", "|---|---:|---:|---:|---|"]
    for field, counts in state_counts.items():
        lines.append(f"| {field} | {counts['true']} | {counts['false']} | {counts['unknown']} | {first_changes.get(field, '未观测')} |")
    lines += ["", "## Event counts", "", "| Source | Event type | Count |", "|---|---|---:|"]
    if event_counts:
        lines.extend(f"| {source} | {event_type} | {count} |" for (source, event_type), count in sorted(event_counts.items()))
    else:
        lines.append("| 未观测 | 未观测 | 0 |")
    lines += ["", "## Contradictions", ""]
    lines.extend(f"- {item}" for item in contradictions) if contradictions else lines.append("- 未观测")
    lines += ["", "## Diagnostics", ""]
    lines.extend(f"- {item}" for item in diagnostics) if diagnostics else lines.append("- None")
    return "\n".join(lines) + "\n"


def _safe_jsonl(records: list[dict[str, Any]], raw_lines: list[str], secrets: set[str]) -> str:
    output: list[str] = []
    by_line = {record.get("_line"): sanitize_record(record, secrets) for record in records}
    for number, raw in enumerate(raw_lines, 1):
        if number in by_line:
            output.append(json.dumps(by_line[number], ensure_ascii=False, separators=(",", ":")))
        elif raw.strip():
            # Damaged source bytes are never archived; retain only a safe diagnostic stub.
            output.append(json.dumps({"malformedLine": number, "content": "[REDACTED; malformed source omitted]"}, separators=(",", ":")))
    return "\n".join(output) + ("\n" if output else "")


def run(experiment_dir: Path, output_dir: Path | None = None, archive_path: Path | None = None) -> Path:
    output_dir = output_dir or experiment_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    diagnostics: list[str] = []
    env_path = experiment_dir / "environment.json"
    try:
        environment = json.loads(env_path.read_text(encoding="utf-8")) if env_path.exists() else None
        if not env_path.exists(): diagnostics.append("Missing input file: environment.json")
    except (OSError, json.JSONDecodeError):
        environment = None
        diagnostics.append("Malformed environment.json; metadata unavailable")
    observations, d, raw_obs = read_jsonl(experiment_dir / "observations.jsonl"); diagnostics.extend(d)
    events, d, raw_events = read_jsonl(experiment_dir / "events.jsonl"); diagnostics.extend(d)
    markers, d, raw_markers = read_jsonl(experiment_dir / "markers.jsonl"); diagnostics.extend(d)
    all_records = [r for rows in (observations, events, markers) for r in rows]
    secrets = collect_sensitive_values([environment, *all_records])
    secrets.update(collect_raw_line_secrets((*raw_obs, *raw_events, *raw_markers)))
    sanitized_env = sanitize_record(environment, secrets) if isinstance(environment, dict) else {}
    sanitized_inputs = {"observations.jsonl": _safe_jsonl(observations, raw_obs, secrets), "events.jsonl": _safe_jsonl(events, raw_events, secrets), "markers.jsonl": _safe_jsonl(markers, raw_markers, secrets)}
    summary = _redact_text(analyze(environment, observations, events, markers, diagnostics), secrets)
    summary_path = output_dir / "summary.md"
    summary_path.write_text(summary, encoding="utf-8")
    archive_path = archive_path or output_dir / "report.zip"
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("environment.json", json.dumps(sanitized_env, ensure_ascii=False, indent=2) + "\n")
        for name in DATA_FILES: archive.writestr(name, sanitized_inputs[name])
        archive.writestr("summary.md", summary)
    return summary_path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Analyze WiFi Link Lab experiment logs offline")
    parser.add_argument("experiment_dir", nargs="?", type=Path, help="directory containing experiment JSON and JSONL")
    parser.add_argument("--experiment-dir", "--input-dir", "--input", dest="input_dir", type=Path)
    parser.add_argument("--output-dir", "--out-dir", dest="output_dir", type=Path)
    parser.add_argument("--archive", "--zip", dest="archive", type=Path, help="report ZIP path (default: <output-dir>/report.zip)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    experiment_dir = args.input_dir or args.experiment_dir
    if experiment_dir is None: build_parser().error("an experiment directory is required")
    summary = run(experiment_dir, args.output_dir, args.archive)
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
