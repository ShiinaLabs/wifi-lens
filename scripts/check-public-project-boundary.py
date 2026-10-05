#!/usr/bin/env python3
"""Check the public Xcode project's structural ownership allowlists."""

from __future__ import annotations

import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath


PUBLIC_TARGETS = {
    "WiFiLens",
    "WiFiLensCore",
    "WiFiLensTests",
    "WiFiLensCoreTests",
    "WiFiLensUITests",
}
PUBLIC_SCHEMES = {"WiFi Lens", "WiFiLensCore", "WiFiLensTests", "WiFiLensUITests"}


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def project_json(path: Path) -> dict:
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def package_identity(url: str) -> str:
    return url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git").lower()


def check(root: Path) -> list[str]:
    problems: list[str] = []
    project_path = root / "WiFiLens.xcodeproj/project.pbxproj"
    try:
        data = project_json(project_path)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        return [f"cannot read the native project: {error}"]

    objects = data.get("objects", {})
    project = objects.get(data.get("rootObject"), {})
    target_ids = project.get("targets", [])
    target_names = {objects.get(target_id, {}).get("name") for target_id in target_ids}
    if target_names != PUBLIC_TARGETS:
        problems.append(f"native target set is {sorted(target_names)}")
    if project.get("projectReferences"):
        problems.append("native project references another project")

    if (root / ".gitmodules").exists():
        problems.append("public checkout contains a Git submodule manifest")

    direct_package_ids: set[str] = set()
    for target_id in target_ids:
        target = objects.get(target_id, {})
        product_ids = set(target.get("packageProductDependencies", []))
        for phase_id in target.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            for build_id in phase.get("files", []):
                build_file = objects.get(build_id, {})
                if build_file.get("productRef"):
                    product_ids.add(build_file["productRef"])
        for product_id in product_ids:
            product = objects.get(product_id, {})
            package_id = product.get("package")
            if package_id:
                direct_package_ids.add(package_id)
    project_package_ids = set(project.get("packageReferences", []))
    if direct_package_ids != project_package_ids:
        problems.append("remote package references do not match package products used by approved targets")

    resolved_path = root / "WiFiLens.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    if resolved_path.exists():
        try:
            resolved = json.loads(resolved_path.read_text(encoding="utf-8"))
            identities = {pin.get("identity", "").lower() for pin in resolved.get("pins", [])}
            for package_id in project_package_ids:
                url = objects.get(package_id, {}).get("repositoryURL", "")
                identity = package_identity(url)
                if identity not in identities:
                    problems.append(f"resolved package lock is missing a declared dependency: {identity}")
        except (OSError, json.JSONDecodeError) as error:
            problems.append(f"cannot read the resolved package lock: {error}")

    for object_data in objects.values():
        if object_data.get("isa") != "PBXFileReference":
            continue
        source_tree = object_data.get("sourceTree", "")
        path = object_data.get("path", "")
        if source_tree in ("SOURCE_ROOT", "<group>") and path:
            parsed = PurePosixPath(path)
            if parsed.is_absolute() or ".." in parsed.parts:
                problems.append(f"project contains a non-local file reference: {path}")

    scheme_dir = root / "WiFiLens.xcodeproj/xcshareddata/xcschemes"
    scheme_files = sorted(scheme_dir.glob("*.xcscheme"))
    scheme_names = {path.stem for path in scheme_files}
    if scheme_names != PUBLIC_SCHEMES:
        problems.append(f"shared scheme set is {sorted(scheme_names)}")
    for path in scheme_files:
        try:
            tree = ET.parse(path)
        except (OSError, ET.ParseError) as error:
            problems.append(f"cannot parse scheme {path.name}: {error}")
            continue
        for node in tree.findall(".//BuildableReference"):
            target_name = node.get("BlueprintName")
            container = node.get("ReferencedContainer")
            if target_name not in PUBLIC_TARGETS:
                problems.append(f"scheme {path.name} references a non-public target")
            if container != "container:WiFiLens.xcodeproj":
                problems.append(f"scheme {path.name} references a non-local project")

    return problems


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    problems = check(root)
    if problems:
        for problem in problems:
            print(f"FAIL: {problem}", file=sys.stderr)
        return 1
    print("PASS: public Xcode ownership structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
