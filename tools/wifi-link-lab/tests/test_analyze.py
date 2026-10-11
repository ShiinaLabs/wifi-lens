from __future__ import annotations

import json
import socket
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import analyze
import run_experiment


class AnalyzerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "environment.json").write_text('{"toolVersion":"test"}\n', encoding="utf-8")

    @staticmethod
    def sample(second: int, **extra):
        base = {
            "schemaVersion": 1, "kind": "sample", "time": f"2026-01-01T00:00:{second:02d}.000Z",
            "monotonicNanoseconds": second * 1_000_000_000, "sampleStartMonotonicNanoseconds": second * 1_000_000_000,
            "sampleStartedAt": f"2026-01-01T00:00:{second:02d}.000Z",
            "sampleEndedAt": f"2026-01-01T00:00:{second:02d}.010Z", "trigger": "timer",
            "interfaceName": "en0", "ssidReadable": True, "ssidTag": "SSID-1", "bssidReadable": True,
            "bssidTag": "AP-1", "interfaceEnumerated": True, "interfaceUp": True, "interfaceRunning": True,
            "ipv4Present": True, "ipv6Present": False, "scLinkKeyPresent": True, "scLinkActive": True,
            "scLinkDetaching": False, "scIPv4KeyPresent": True, "scIPv6KeyPresent": False,
            "nwPathStatus": "satisfied", "nwPathUsesWiFi": True, "nwPathInterfaceNames": ["en0"],
            "errorsByField": {},
        }
        base.update(extra)
        return base

    def write_jsonl(self, name, records):
        (self.root / name).write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")

    def run_analysis(self):
        analyze.run(self.root)
        return (self.root / "summary.md").read_text(encoding="utf-8")

    def test_parseable_jsonl_and_summary(self):
        self.write_jsonl("observations.jsonl", [self.sample(1)])
        self.write_jsonl("events.jsonl", [])
        self.write_jsonl("markers.jsonl", [])
        summary = self.run_analysis()
        self.assertIn("Valid samples: 1", summary)
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            self.assertIn("observations.jsonl", archive.namelist())

    def test_missing_fields_and_null_are_unknown_not_false(self):
        self.write_jsonl("observations.jsonl", [self.sample(1, interfaceUp=None)])
        summary = self.run_analysis()
        self.assertIn("| interfaceUp | 0 | 0 | 1 |", summary)
        self.assertIn("| ipv6Present | 0 | 1 | 0 |", summary)

    def test_records_sort_by_time_and_monotonic(self):
        self.write_jsonl("observations.jsonl", [self.sample(2), self.sample(1)])
        summary = self.run_analysis()
        self.assertIn("Maximum sample interval (ms) | 1000.000", summary)

    def test_event_to_following_sample_link_and_notification_latency(self):
        self.write_jsonl("observations.jsonl", [self.sample(2)])
        self.write_jsonl("events.jsonl", [{"schemaVersion": 1, "kind": "event", "source": "notification", "eventType": "changed", "time": "2026-01-01T00:00:01.500Z", "monotonicNanoseconds": 1_500_000_000}])
        summary = self.run_analysis()
        self.assertIn("Events linked to a following sample | 1/1", summary)
        self.assertIn("Notification to next valid sample (mean ms) | 500.000", summary)

    def test_source_callback_events_count_for_notification_latency(self):
        self.write_jsonl("observations.jsonl", [self.sample(2)])
        self.write_jsonl("events.jsonl", [
            {"kind": "event", "source": "systemConfiguration", "eventType": "dynamicStoreChanged", "time": "2026-01-01T00:00:01.500Z", "monotonicNanoseconds": 1_500_000_000},
            {"kind": "event", "source": "networkPath", "eventType": "pathUpdate", "time": "2026-01-01T00:00:01.800Z", "monotonicNanoseconds": 1_800_000_000},
            {"kind": "event", "source": "coreWLAN", "eventType": "registration", "time": "2026-01-01T00:00:01.000Z", "monotonicNanoseconds": 1_000_000_000, "success": True},
        ])
        summary = self.run_analysis()
        self.assertIn("Notification to next valid sample (mean ms) | 350.000", summary)

    def test_changing_anonymous_tags_are_not_treated_as_identity(self):
        self.write_jsonl("observations.jsonl", [self.sample(1, ssidTag="SSID-1"), self.sample(2, ssidTag="SSID-2")])
        summary = self.run_analysis()
        self.assertIn("Valid samples: 2", summary)
        self.assertNotIn("ssidTag", summary)
        self.assertIn("SSID tag changes | 1", summary)
        self.assertIn("BSSID tag changes | 0", summary)

    def test_raw_ssid_and_bssid_cleartext_are_removed_from_output_and_zip(self):
        secret_ssid, secret_bssid = "PrivateCafeNetwork", "aa:bb:cc:dd:ee:ff"
        self.write_jsonl("observations.jsonl", [self.sample(1, ssid=secret_ssid, bssid=secret_bssid, debugLog=f"seen {secret_ssid} {secret_bssid}")])
        summary = self.run_analysis()
        self.assertIn(secret_ssid, (self.root / "observations.jsonl").read_text(encoding="utf-8"))  # Source logs remain untouched.
        self.assertNotIn(secret_ssid, summary)
        self.assertNotIn(secret_bssid, summary)
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            payload = b"".join(archive.read(name) for name in archive.namelist())
            self.assertNotIn(secret_ssid.encode(), payload)
            self.assertNotIn(secret_bssid.encode(), payload)

    def test_truncated_line_diagnostic_and_valid_records_continue(self):
        (self.root / "observations.jsonl").write_text(json.dumps(self.sample(1)) + "\n{\"kind\":\"sample\",\"time\":", encoding="utf-8")
        summary = self.run_analysis()
        self.assertIn("Valid samples: 1", summary)
        self.assertIn("Malformed observations.jsonl line 2", summary)

    def test_no_notifications_reports_unobserved(self):
        self.write_jsonl("observations.jsonl", [self.sample(1)])
        self.write_jsonl("events.jsonl", [])
        summary = self.run_analysis()
        self.assertIn("Notification to next valid sample (mean ms) | 未观测", summary)

    def test_registration_failure_is_nonfatal_and_reported(self):
        self.write_jsonl("events.jsonl", [{"kind": "event", "source": "notification", "eventType": "registration_failed", "success": False, "time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 1}])
        summary = self.run_analysis()
        self.assertIn("Listener registration failures (nonfatal events) | 1", summary)
        self.assertIn("Waiting for a real-device experiment", summary)

    def test_skips_are_not_passes(self):
        self.write_jsonl("markers.jsonl", [{"kind": "marker", "time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 1, "markerType": "skip", "scenarioName": "roam", "skipReason": "not available"}])
        summary = self.run_analysis()
        self.assertIn("Skipped scenario marker(s): 1 (not counted as passes)", summary)
        self.assertIn("Sample failures (non-empty errorsByField): 0", summary)

    def test_analyzer_does_not_use_network(self):
        self.write_jsonl("observations.jsonl", [self.sample(1)])
        with patch.object(socket, "socket", side_effect=AssertionError("network used")):
            self.run_analysis()

    def test_existing_input_logs_are_retained(self):
        original = json.dumps(self.sample(1)) + "\n"
        (self.root / "observations.jsonl").write_text(original, encoding="utf-8")
        self.run_analysis()
        self.assertEqual((self.root / "observations.jsonl").read_text(encoding="utf-8"), original)

    def test_ctrl_c_termination_keeps_existing_evidence(self):
        original = json.dumps(self.sample(1)) + "\n"
        evidence_path = self.root / "observations.jsonl"
        evidence_path.write_text(original, encoding="utf-8")
        child = subprocess.Popen([
            sys.executable,
            "-I",
            "-c",
            "import signal, time; signal.signal(signal.SIGINT, lambda *_: exit(0)); time.sleep(60)",
        ])
        self.addCleanup(lambda: child.poll() is None and child.kill())

        run_experiment.terminate_child(child)

        self.assertIsNotNone(child.poll())
        self.assertEqual(evidence_path.read_text(encoding="utf-8"), original)

    def test_report_scrubs_secrets_from_environment_and_log_text(self):
        secret = "UserHomeSSID"
        (self.root / "environment.json").write_text(json.dumps({"ssid": secret, "version": "1"}), encoding="utf-8")
        self.write_jsonl("events.jsonl", [{"kind": "event", "source": "system", "eventType": "logged", "time": "2026-01-01T00:00:00Z", "message": f"connected to {secret}"}])
        self.run_analysis()
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            text = b"".join(archive.read(name) for name in archive.namelist()).decode("utf-8")
        self.assertNotIn(secret, text)
        self.assertIn("[REDACTED]", text)

    def test_zip_contains_only_explicit_allowlist(self):
        for filename in ("observations.jsonl", "events.jsonl", "markers.jsonl"):
            self.write_jsonl(filename, [])
        (self.root / "private.txt").write_text("do not archive", encoding="utf-8")
        self.run_analysis()
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            self.assertEqual(set(archive.namelist()), set(analyze.ZIP_ALLOWLIST))
            self.assertNotIn("private.txt", archive.namelist())

    def test_scenario_marker_interval_metrics_are_measured(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2, errorsByField={"channel": "unavailable"})])
        self.write_jsonl("markers.jsonl", [
            {"kind": "marker", "time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "start", "scenarioName": "roam"},
            {"kind": "marker", "time": "2026-01-01T00:00:03Z", "monotonicNanoseconds": 3_000_000_000, "markerType": "end", "scenarioName": "roam"},
        ])
        summary = self.run_analysis()
        self.assertIn("| roam | 2 | 1 | 1000.000 | 10.000 |", summary)
    def test_scenario_completed_closes_marker_interval(self):
        intervals = analyze.scenario_intervals([
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": "Normal connection"},
            {"time": "2026-01-01T00:00:02Z", "monotonicNanoseconds": 2_000_000_000, "markerType": "scenarioCompleted", "scenarioName": "Normal connection"},
        ])
        self.assertEqual(intervals["Normal connection"], [(0, 2_000_000_000)])

    def test_action_markers_do_not_truncate_scenario_observation_interval(self):
        intervals = analyze.scenario_intervals([
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": "Normal connection"},
            {"time": "2026-01-01T00:00:01Z", "monotonicNanoseconds": 1_000_000_000, "markerType": "operatorActionStarted", "scenarioName": "Normal connection"},
            {"time": "2026-01-01T00:00:02Z", "monotonicNanoseconds": 2_000_000_000, "markerType": "operatorActionCompleted", "scenarioName": "Normal connection"},
            {"time": "2026-01-01T00:00:05Z", "monotonicNanoseconds": 5_000_000_000, "markerType": "scenarioCompleted", "scenarioName": "Normal connection"},
        ])
        self.assertEqual(intervals["Normal connection"], [(0, 5_000_000_000)])

    def test_driver_action_windows_include_samples_after_action_completed(self):
        scenario = "B-radio-toggle"
        markers = [
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": scenario},
            {"time": "2026-01-01T00:00:01Z", "monotonicNanoseconds": 1_000_000_000, "markerType": "operatorActionStarted", "scenarioName": scenario, "actionName": "关闭 Wi-Fi"},
            {"time": "2026-01-01T00:00:02Z", "monotonicNanoseconds": 2_000_000_000, "markerType": "operatorActionCompleted", "scenarioName": scenario, "actionName": "关闭 Wi-Fi"},
            {"time": "2026-01-01T00:00:05Z", "monotonicNanoseconds": 5_000_000_000, "markerType": "observationCompleted", "scenarioName": scenario, "actionName": "关闭 Wi-Fi"},
            {"time": "2026-01-01T00:00:06Z", "monotonicNanoseconds": 6_000_000_000, "markerType": "scenarioCompleted", "scenarioName": scenario},
        ]
        intervals = analyze.action_intervals(markers)
        self.assertEqual(intervals[scenario], [("关闭 Wi-Fi", 1_000_000_000, 5_000_000_000)])
        self.write_jsonl("observations.jsonl", [self.sample(0), self.sample(3), self.sample(6)])
        self.write_jsonl("markers.jsonl", markers)
        summary = self.run_analysis()
        self.assertIn("| Wi-Fi radio off | 1 |", summary)
        self.assertIn("| B-radio-toggle | 3 |", summary)

    def test_driver_action_names_classify_fixed_scenario_rows(self):
        driver_actions = {
            "A-normal-connection": ["正常连接基线"],
            "B-radio-toggle": ["关闭 Wi-Fi", "观察无线电关闭", "重新开启 Wi-Fi", "观察无线电恢复"],
            "C-access-point-disappears": ["关闭测试接入点", "观察接入点不可用", "恢复测试接入点", "观察接入点恢复"],
            "D-manual-disassociation": ["恢复原网络连接"],
            "E-network-switch": ["连接网络 A", "切换至网络 B"],
        }
        expected = {
            "A-normal-connection": ["Normal connection"],
            "B-radio-toggle": ["Wi-Fi radio off", "Wi-Fi radio off", "Recovery", "Recovery"],
            "C-access-point-disappears": ["AP lost while Wi-Fi on", "AP lost while Wi-Fi on", "Recovery", "Recovery"],
            "D-manual-disassociation": ["Recovery"],
            "E-network-switch": ["Network switch", "Network switch"],
        }
        for scenario, actions in driver_actions.items():
            with self.subTest(scenario=scenario):
                self.assertEqual([analyze._action_family(scenario, action) for action in actions], expected[scenario])

        markers = []
        observations = []
        events = []
        cursor = 0
        for scenario, actions in driver_actions.items():
            markers.append({"time": f"2026-01-01T00:00:{cursor:02d}Z", "monotonicNanoseconds": cursor * 1_000_000_000, "markerType": "scenarioStarted", "scenarioName": scenario})
            cursor += 1
            for action in actions:
                markers.append({"time": f"2026-01-01T00:00:{cursor:02d}Z", "monotonicNanoseconds": cursor * 1_000_000_000, "markerType": "operatorActionStarted", "scenarioName": scenario, "actionName": action})
                markers.append({"time": f"2026-01-01T00:00:{cursor + 1:02d}Z", "monotonicNanoseconds": (cursor + 1) * 1_000_000_000, "markerType": "operatorActionCompleted", "scenarioName": scenario, "actionName": action})
                observations.append(self.sample(cursor + 2))
                events.append({"kind": "event", "time": f"2026-01-01T00:00:{cursor + 2:02d}Z", "monotonicNanoseconds": (cursor + 2) * 1_000_000_000, "source": "CoreWLAN", "eventType": "changed"})
                markers.append({"time": f"2026-01-01T00:00:{cursor + 3:02d}Z", "monotonicNanoseconds": (cursor + 3) * 1_000_000_000, "markerType": "observationCompleted", "scenarioName": scenario, "actionName": action})
                cursor += 4
            markers.append({"time": f"2026-01-01T00:00:{cursor:02d}Z", "monotonicNanoseconds": cursor * 1_000_000_000, "markerType": "scenarioCompleted", "scenarioName": scenario})
            cursor += 1
        self.write_jsonl("observations.jsonl", observations)
        self.write_jsonl("events.jsonl", events)
        self.write_jsonl("markers.jsonl", markers)
        summary = self.run_analysis()
        row_labels = {"Normal connection", "Wi-Fi radio off", "AP lost while Wi-Fi on", "Recovery", "Network switch"}
        rows = {line.split("|")[1].strip(): line for line in summary.splitlines() if line.startswith("| ") and line.split("|")[1].strip() in row_labels}
        self.assertIn("| Normal connection | 1 |", rows["Normal connection"])
        self.assertIn("| Wi-Fi radio off | 2 |", rows["Wi-Fi radio off"])
        self.assertIn("| AP lost while Wi-Fi on | 2 |", rows["AP lost while Wi-Fi on"])
        self.assertIn("| Recovery | 5 |", rows["Recovery"])
        self.assertIn("| Network switch | 2 |", rows["Network switch"])
        for family, expected_count in (("Normal connection", 1), ("Wi-Fi radio off", 2), ("AP lost while Wi-Fi on", 2), ("Recovery", 5), ("Network switch", 2)):
            self.assertEqual(rows[family].split("|")[-2].strip(), str(expected_count))

    def test_scenario_skip_and_interruption_close_open_intervals(self):
        markers = [
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": "C-access-point-disappears"},
            {"time": "2026-01-01T00:00:01Z", "monotonicNanoseconds": 1_000_000_000, "markerType": "operatorActionStarted", "scenarioName": "C-access-point-disappears", "actionName": "关闭测试接入点"},
            {"time": "2026-01-01T00:00:02Z", "monotonicNanoseconds": 2_000_000_000, "markerType": "scenarioSkipped", "scenarioName": "C-access-point-disappears", "skipReason": "not available"},
            {"time": "2026-01-01T00:00:03Z", "monotonicNanoseconds": 3_000_000_000, "markerType": "scenarioStarted", "scenarioName": "E-network-switch"},
            {"time": "2026-01-01T00:00:04Z", "monotonicNanoseconds": 4_000_000_000, "markerType": "operatorActionStarted", "scenarioName": "E-network-switch", "actionName": "切换至网络 B"},
            {"time": "2026-01-01T00:00:05Z", "monotonicNanoseconds": 5_000_000_000, "markerType": "scenarioInterrupted", "scenarioName": "E-network-switch"},
        ]
        intervals = analyze.scenario_intervals(markers)
        self.assertEqual(intervals["C-access-point-disappears"], [(0, 2_000_000_000)])
        self.assertEqual(intervals["E-network-switch"], [(3_000_000_000, 5_000_000_000)])
        action_spans = analyze.action_intervals(markers)
        self.assertEqual(action_spans["C-access-point-disappears"], [("关闭测试接入点", 1_000_000_000, 2_000_000_000)])
        self.assertEqual(action_spans["E-network-switch"], [("切换至网络 B", 4_000_000_000, 5_000_000_000)])
        self.write_jsonl("markers.jsonl", markers)
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(4), self.sample(6)])
        summary = self.run_analysis()
        self.assertIn("Skipped scenario marker(s): 1 (not counted as passes)", summary)
        self.assertIn("Interrupted/incomplete marker(s): 1 (not counted as passes)", summary)
        self.assertIn("| E-network-switch | 1 |", summary)  # Scenario evidence closes at interruption.
        self.assertIn("| Network switch | 1 |", summary)  # Fixed row excludes post-interruption samples.

    def test_scenario_only_bundle_keeps_name_fallback(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(4)])
        self.write_jsonl("markers.jsonl", [
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": "A-normal-connection"},
            {"time": "2026-01-01T00:00:03Z", "monotonicNanoseconds": 3_000_000_000, "markerType": "scenarioCompleted", "scenarioName": "A-normal-connection"},
        ])
        summary = self.run_analysis()
        self.assertIn("| Normal connection | 1 |", summary)

    def test_fixed_scenario_measurements_include_all_canonical_rows(self):
        summary = self.run_analysis()
        for scenario in ("Normal connection", "Wi-Fi radio off", "AP lost while Wi-Fi on", "Recovery", "Network switch"):
            self.assertIn(f"| {scenario} | 未观测 |", summary)
        self.assertIn("Link.Active true / false / null", summary)

    def test_scenario_metrics_cover_mode_power_service_link_and_source_counts(self):
        self.write_jsonl("observations.jsonl", [self.sample(1, mode="station", powerOnRaw=True, serviceActiveRaw=True, scLinkActive=True), self.sample(2, mode="none", powerOnRaw=False, serviceActiveRaw=False, scLinkActive=None)])
        self.write_jsonl("events.jsonl", [
            {"kind":"event", "time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000,"source":"CoreWLAN","eventType":"changed"},
            {"kind":"event", "time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000,"source":"SystemConfiguration","eventType":"changed"},
            {"kind":"event", "time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000,"source":"NWPath","eventType":"changed"},
        ])
        self.write_jsonl("markers.jsonl", [
            {"time":"2026-01-01T00:00:00Z","monotonicNanoseconds":0,"markerType":"start","scenarioName":"Normal connection"},
            {"time":"2026-01-01T00:00:03Z","monotonicNanoseconds":3_000_000_000,"markerType":"scenarioCompleted","scenarioName":"Normal connection"},
        ])
        summary = self.run_analysis()
        self.assertIn("station 1 / none 1", summary)
        self.assertIn("true 1 / false 1 / null 0", summary)
        self.assertIn("1 / 1 / 1", summary)

    def test_schema_version_and_required_timing_make_sample_invalid(self):
        bad = self.sample(1, schemaVersion=2)
        missing_monotonic = self.sample(2)
        del missing_monotonic["monotonicNanoseconds"]
        self.write_jsonl("observations.jsonl", [bad, missing_monotonic, self.sample(3)])
        summary = self.run_analysis()
        self.assertIn("Valid samples: 1", summary)
        self.assertIn("2 observation record(s) were not valid", summary)

    def test_raw_malformed_json_secret_is_never_archived(self):
        secret = "MalformedPrivateNetwork"
        (self.root / "observations.jsonl").write_text('{"kind":"sample","ssid":"' + secret + '","time":\n', encoding="utf-8")
        self.run_analysis()
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            contents = b"".join(archive.read(name) for name in archive.namelist())
        self.assertNotIn(secret.encode(), contents)
        self.assertIn(b"malformed source omitted", contents)

    def test_malformed_raw_regex_recovers_sensitive_values(self):
        secrets = analyze.collect_raw_line_secrets(['{"ip_address": "192.0.2.44", "ssid":"SecretSSID" garbage'])
        self.assertIn("192.0.2.44", secrets)
        self.assertIn("SecretSSID", secrets)

    def test_environment_sensitive_keys_and_ip_patterns_are_scrubbed(self):
        self.write_jsonl("events.jsonl", [{"kind":"event", "time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":1, "message":"host 192.0.2.45 and aa:bb:cc:dd:ee:ff"}])
        (self.root / "environment.json").write_text(json.dumps({"ssid": "PrivateSSID", "ip_address": "192.0.2.45"}), encoding="utf-8")
        self.run_analysis()
        with zipfile.ZipFile(self.root / "report.zip") as archive:
            payload = b"".join(archive.read(name) for name in archive.namelist())
        for value in (b"PrivateSSID", b"192.0.2.45", b"aa:bb:cc:dd:ee:ff"):
            self.assertNotIn(value, payload)

    def test_station_and_link_conflicts_are_reported(self):
        self.write_jsonl("observations.jsonl", [self.sample(1, mode="station", scLinkActive=False, nwPathUsesWiFi=False, ssidReadable=False)])
        summary = self.run_analysis()
        self.assertIn("station mode conflicts with Link.Active=false", summary)
        self.assertIn("SSID unreadable conflicts with station mode", summary)
        self.assertIn("no Wi-Fi NWPath conflicts with station mode", summary)

    def test_none_and_power_off_conflicts_are_reported(self):
        self.write_jsonl("observations.jsonl", [self.sample(1, mode="none", scLinkActive=True, powerOnRaw=False)])
        summary = self.run_analysis()
        self.assertIn("mode none conflicts with Link.Active=true", summary)
        self.assertIn("power off conflicts with an active Wi-Fi link", summary)

    def test_interface_disappearance_and_reappearance_are_reported(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2, interfaceEnumerated=False, interfaceUp=False), self.sample(3, interfaceEnumerated=True)])
        summary = self.run_analysis()
        self.assertIn("interface disappeared", summary)
        self.assertIn("interface reappeared", summary)

    def test_baseline_and_observation_markers_do_not_require_state_change(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2)])
        markers = [
            {"time": "2026-01-01T00:00:00Z", "monotonicNanoseconds": 0, "markerType": "scenarioStarted", "scenarioName": "A-normal-connection"},
            {"time": "2026-01-01T00:00:00.500Z", "monotonicNanoseconds": 500_000_000, "markerType": "operatorActionStarted", "scenarioName": "A-normal-connection", "actionName": "正常连接基线"},
            {"time": "2026-01-01T00:00:01Z", "monotonicNanoseconds": 1_000_000_000, "markerType": "operatorActionCompleted", "scenarioName": "A-normal-connection", "actionName": "正常连接基线"},
            {"time": "2026-01-01T00:00:02Z", "monotonicNanoseconds": 2_000_000_000, "markerType": "observationCompleted", "scenarioName": "A-normal-connection", "actionName": "正常连接基线"},
            {"time": "2026-01-01T00:00:03Z", "monotonicNanoseconds": 3_000_000_000, "markerType": "scenarioCompleted", "scenarioName": "A-normal-connection"},
        ]
        self.write_jsonl("markers.jsonl", markers)
        self.assertNotIn("operator action has no related observed state change", self.run_analysis())

    def test_operator_action_without_state_change_is_reported(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2)])
        self.write_jsonl("markers.jsonl", [{"time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000,"markerType":"operatorAction","scenarioName":"test"}])
        self.assertIn("operator action has no related observed state change", self.run_analysis())

    def test_notification_without_following_change_is_reported(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2)])
        self.write_jsonl("events.jsonl", [{"kind":"event", "source":"notification", "eventType":"changed", "time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000}])
        self.assertIn("notification(s) had no following state change", self.run_analysis())

    def test_registration_outcomes_and_source_family_counts(self):
        self.write_jsonl("events.jsonl", [
            {"kind":"event", "time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":1,"source":"CoreWLAN","eventType":"registration_success","success":True},
            {"kind":"event", "time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":2,"source":"SystemConfiguration","eventType":"registration_failed","success":False},
            {"kind":"event", "time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":3,"source":"NWPath","eventType":"registration"},
            {"kind":"event", "time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":4,"source":"CoreWLAN","eventType":"unregistration","success":True},
        ])
        summary = self.run_analysis()
        self.assertIn("success 1, failure 1, unknown 1", summary)
        self.assertIn("CoreWLAN", summary)
        self.assertIn("SystemConfiguration", summary)
        self.assertIn("NWPath", summary)

    def test_malformed_diagnostics_do_not_contain_raw_payload(self):
        secret = "DamagedNetworkSecret"
        (self.root / "observations.jsonl").write_text('{"ssid":"' + secret + '",broken\n', encoding="utf-8")
        summary = self.run_analysis()
        self.assertNotIn(secret, summary)

    def test_ctrl_c_or_other_input_is_not_overwritten(self):
        original = json.dumps(self.sample(1)) + "\n"
        (self.root / "observations.jsonl").write_text(original, encoding="utf-8")
        self.run_analysis()
        self.assertEqual((self.root / "observations.jsonl").read_text(encoding="utf-8"), original)

    def test_event_marker_relation_is_measured_and_no_event_is_unobserved(self):
        self.write_jsonl("observations.jsonl", [self.sample(1), self.sample(2)])
        self.write_jsonl("events.jsonl", [{"kind":"event", "time":"2026-01-01T00:00:01Z", "monotonicNanoseconds":1_000_000_000,"source":"CoreWLAN", "eventType":"changed"}])
        self.write_jsonl("markers.jsonl", [{"time":"2026-01-01T00:00:00Z", "monotonicNanoseconds":0,"markerType":"start","scenarioName":"Normal connection"}, {"time":"2026-01-01T00:00:03Z", "monotonicNanoseconds":3_000_000_000,"markerType":"scenarioCompleted","scenarioName":"Normal connection"}])
        summary = self.run_analysis()
        self.assertIn("| Normal connection | 2 |", summary)
        self.assertIn("Events related to marker interval", summary)


if __name__ == "__main__":
    unittest.main()
