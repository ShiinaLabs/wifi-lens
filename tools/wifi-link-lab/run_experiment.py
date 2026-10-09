#!/usr/bin/env python3
"""Run an operator-led Wi-Fi link experiment using a compiled collector."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

SCHEMA_VERSION = 1
SAMPLE_REQUIRED = {
    "kind", "time", "monotonicNanoseconds", "sampleStartedAt", "sampleEndedAt",
    "sampleStartMonotonicNanoseconds", "trigger", "interfaceName", "mode", "modeRaw",
    "powerOnRaw", "serviceActiveRaw", "ssidReadable", "ssidTag", "bssidReadable",
    "bssidTag", "channelReadable", "channel", "callDurationsMs", "scLinkKeyPresent",
    "scLinkActive", "scLinkDetaching", "scIPv4KeyPresent", "scIPv6KeyPresent",
    "interfaceEnumerated", "interfaceUp", "interfaceRunning", "ipv4Present", "ipv6Present",
    "flagsConflict", "nwPathStatus", "nwPathUsesWiFi", "nwPathInterfaceNames", "errorsByField",
}
SCENARIOS = [
    {
        "name": "A-normal-connection",
        "title": "A — 正常连接基线",
        "optional": False,
        "actions": [("保持 Wi‑Fi 正常连接；准备好后按回车开始观察。", "正常连接基线", 20)],
    },
    {
        "name": "B-radio-toggle",
        "title": "B — 关闭并重新开启 Wi‑Fi",
        "optional": False,
        "actions": [
            ("通过 macOS 控制中心手动关闭 Wi‑Fi。", "关闭 Wi‑Fi", 15),
            ("保持 Wi‑Fi 关闭，观察至少 15 秒。", "观察无线电关闭", 15),
            ("手动重新开启 Wi‑Fi。", "重新开启 Wi‑Fi", 20),
            ("保持 Wi‑Fi 开启并观察恢复。", "观察无线电恢复", 20),
        ],
    },
    {
        "name": "C-access-point-disappears",
        "title": "C — 无线电开启时接入点消失与恢复",
        "optional": False,
        "actions": [
            ("确认 Mac 的 Wi‑Fi 已开启并连接到可独立控制的测试热点或路由器。", "确认接入点连接", 20),
            ("保持 Mac 的 Wi‑Fi 开启，手动关闭测试热点或路由器。", "关闭测试接入点", 20),
            ("保持接入点关闭；避免 Mac 自动切换到其他已知网络。", "观察接入点不可用", 20),
            ("手动恢复同一个测试热点或路由器。", "恢复测试接入点", 20),
            ("保持连接并观察恢复。", "观察接入点恢复", 20),
        ],
    },
    {
        "name": "D-manual-disassociation",
        "title": "D — 手动解除关联（可选）",
        "optional": True,
        "actions": [
            ("确认 Wi‑Fi 已开启并连接到测试网络。", "确认初始连接", 20),
            ("如果系统提供保持 Wi‑Fi 开启的断开/解除关联操作，请手动执行；否则输入 s 跳过本场景。", "手动解除关联", 20),
            ("手动重新连接到原测试网络。", "恢复原网络连接", 20),
        ],
    },
    {
        "name": "E-network-switch",
        "title": "E — 网络 A 切换至网络 B",
        "optional": True,
        "actions": [
            ("连接至测试网络 A。", "连接网络 A", 20),
            ("切换至测试网络 B。", "切换至网络 B", 20),
        ],
    },
    {
        "name": "F-cli-permission-context",
        "title": "F — 命令行工具权限上下文（可选）",
        "optional": True,
        "actions": [
            ("记录命令行运行环境当前与 Wi‑Fi/位置权限有关的状态；不要输入或记录名称、地址等敏感信息。", "记录命令行权限基线", 20),
            ("仅在能明确识别目标权限时，通过系统设置手动更改命令行运行环境的相关权限；否则跳过。", "更改命令行权限", 20),
        ],
    },
    {
        "name": "G-app-permission-context",
        "title": "G — WiFi Lens App 权限上下文（可选）",
        "optional": True,
        "actions": [
            ("记录 WiFi Lens App 当前与 Wi‑Fi/位置权限有关的状态；不要输入或记录名称、地址等敏感信息。", "记录 App 权限基线", 20),
            ("通过系统设置手动更改 WiFi Lens App 的相关权限；不要使用 tccutil reset。", "更改 App 权限", 20),
        ],
    },
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def append_jsonl(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def marker(output_dir: Path, marker_type: str, scenario_name: str,
           action_name: str | None = None, skip_reason: str | None = None) -> None:
    record = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "marker",
        "time": utc_now(),
        "monotonicNanoseconds": time.monotonic_ns(),
        "markerType": marker_type,
        "scenarioName": scenario_name,
    }
    if action_name:
        record["actionName"] = action_name
    if skip_reason:
        record["skipReason"] = skip_reason
    append_jsonl(output_dir / "markers.jsonl", record)


def is_valid_sample(path: Path) -> bool:
    try:
        with path.open("r", encoding="utf-8") as stream:
            for line in stream:
                try:
                    record = json.loads(line)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                if not isinstance(record, dict) or record.get("schemaVersion") != SCHEMA_VERSION:
                    continue
                if record.get("kind") != "sample" or not SAMPLE_REQUIRED.issubset(record):
                    continue
                if not isinstance(record.get("time"), str) or not isinstance(record.get("sampleStartedAt"), str):
                    continue
                if not isinstance(record.get("sampleEndedAt"), str):
                    continue
                if not isinstance(record.get("monotonicNanoseconds"), int):
                    continue
                if not isinstance(record.get("sampleStartMonotonicNanoseconds"), int):
                    continue
                if record.get("trigger") not in {"timer", "notification", "startup"}:
                    continue
                return True
    except FileNotFoundError:
        return False
    return False


def wait_for_first_sample(path: Path, child: subprocess.Popen, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if is_valid_sample(path):
            return
        if child.poll() is not None:
            raise RuntimeError(f"collector exited before a valid sample (exit {child.returncode})")
        time.sleep(0.25)
    raise TimeoutError(f"no valid schemaVersion=1 sample appeared within {timeout:g} seconds")


def wait_window(seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        time.sleep(min(remaining, 0.5))


def terminate_child(child: subprocess.Popen) -> None:
    if child.poll() is not None:
        return
    try:
        child.send_signal(signal.SIGINT)
        child.wait(timeout=8)
    except subprocess.TimeoutExpired:
        child.terminate()
        try:
            child.wait(timeout=4)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


def skip_scenario(output_dir: Path, scenario_name: str) -> None:
    reason = input("请输入跳过原因：").strip()
    marker(output_dir, "scenarioSkipped", scenario_name, skip_reason=reason or "未提供原因")


def run_scenarios(output_dir: Path) -> None:
    print("所有系统操作都由你手动完成。本工具不会更改 Wi‑Fi、权限或系统设置，也不会发起网络请求。", flush=True)
    active_scenario: str | None = None
    try:
        for scenario in SCENARIOS:
            name = scenario["name"]
            print(f"\n=== {scenario['title']} ===", flush=True)
            answer = input("按回车开始本场景；输入 s 可跳过：").strip().lower()
            if answer == "s":
                skip_scenario(output_dir, name)
                continue
            active_scenario = name
            marker(output_dir, "scenarioStarted", name)
            for guidance, action_name, duration in scenario["actions"]:
                print(f"\n{guidance}（观察时长：{duration} 秒）", flush=True)
                answer = input("按回车开始操作；输入 s 可跳过本场景：").strip().lower()
                if answer == "s":
                    skip_scenario(output_dir, name)
                    active_scenario = None
                    break
                marker(output_dir, "operatorActionStarted", name, action_name)
                answer = input("操作完成后再次按回车；输入 s 可跳过本场景：").strip().lower()
                if answer == "s":
                    skip_scenario(output_dir, name)
                    active_scenario = None
                    break
                marker(output_dir, "operatorActionCompleted", name, action_name)
                print(f"正在离线采样观察 {duration} 秒……", flush=True)
                wait_window(duration)
                marker(output_dir, "observationCompleted", name, action_name)
            else:
                marker(output_dir, "scenarioCompleted", name)
                active_scenario = None
    except KeyboardInterrupt:
        marker(output_dir, "scenarioInterrupted" if active_scenario else "experimentInterrupted",
               active_scenario or "experiment", skip_reason="用户按下 Ctrl+C；场景未完成")
        raise
    except EOFError:
        marker(output_dir, "scenarioInterrupted" if active_scenario else "experimentInterrupted",
               active_scenario or "experiment", skip_reason="输入已结束；场景未完成")
        raise KeyboardInterrupt


def run_analyzer(lab_dir: Path, output_dir: Path) -> int:
    analyzer = lab_dir / "analyze.py"
    if not analyzer.is_file():
        print(f"Analyzer not found: {analyzer}; raw evidence is preserved.", file=sys.stderr)
        return 2
    result = subprocess.run([sys.executable, str(analyzer), str(output_dir)], cwd=lab_dir, check=False)
    return result.returncode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a guided, operator-led Wi-Fi link experiment.")
    parser.add_argument("collector", type=Path, help="compiled collector binary supplied by run.sh")
    parser.add_argument("--startup-timeout", type=float, default=120,
                        help="seconds to wait for the first valid collector sample (default: 120)")
    parser.add_argument("--output-root", type=Path,
                        help="evidence parent directory (default: ~/Desktop)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.startup_timeout <= 0:
        print("Startup timeout must be greater than zero.", file=sys.stderr)
        return 2
    lab_dir = Path(__file__).resolve().parent
    collector = args.collector.expanduser().resolve()
    if not collector.is_file() or not os.access(collector, os.X_OK):
        print(f"Compiled collector is missing or not executable: {collector}; no experiment was started.", file=sys.stderr)
        return 2

    stamp = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    output_root = args.output_root.expanduser() if args.output_root else Path.home() / "Desktop"
    if not output_root.is_absolute():
        output_root = Path.cwd() / output_root
    output_dir = output_root / f"WiFiLens-LinkProbe-{stamp}"
    output_dir.mkdir(parents=True, exist_ok=False)
    observations = output_dir / "observations.jsonl"
    (output_dir / "events.jsonl").touch()
    (output_dir / "markers.jsonl").touch()

    env = os.environ.copy()
    env["WIFI_LINK_LAB_OUTPUT_DIR"] = str(output_dir)
    child = subprocess.Popen([str(collector), str(output_dir)], cwd=lab_dir, env=env)
    interrupted = False
    collector_error = False
    try:
        print("Waiting for the collector's first valid v1 sample before showing experiment instructions.", flush=True)
        wait_for_first_sample(observations, child, args.startup_timeout)
        print(f"First valid sample received. Evidence directory: {output_dir}", flush=True)
        run_scenarios(output_dir)
    except KeyboardInterrupt:
        interrupted = True
        print("\nCtrl+C received; stopping only the collector child started by this driver.", file=sys.stderr)
    except (RuntimeError, TimeoutError, OSError) as error:
        collector_error = True
        print(f"Experiment stopped: {error}", file=sys.stderr)
    finally:
        terminate_child(child)

    analysis_status = run_analyzer(lab_dir, output_dir)
    archive = output_dir / "report.zip"
    print(f"Evidence directory: {output_dir}")
    print(f"Sanitized report archive: {archive if archive.is_file() else 'not created (see analyzer status)'}")
    if interrupted:
        return 130
    if collector_error or child.returncode not in (0, None) or analysis_status != 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
