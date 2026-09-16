#!/usr/bin/env python3
"""Summarise code coverage from an .xcresult bundle and enforce a threshold.

Xcode reports coverage per *target*, but this app target is one big SwiftUI
module whose views cannot be meaningfully unit tested. Gating on the whole
target would therefore measure how much UI exists, not how well the tested
logic is covered. So the gate is applied to an explicit list of files — the
logic actually under test, declared in coverage_targets.json — while the
whole-target number is still reported for context.

Usage:
    coverage_report.py <path-to-.xcresult> [--config Scripts/coverage_targets.json]
                                           [--markdown-out summary.md]
                                           [--sonar-out coverage-sonar.xml]
"""

import argparse
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET


def xccov(args):
    result = subprocess.run(["xcrun", "xccov"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"xccov failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def percent(covered, executable):
    return 100.0 * covered / executable if executable else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("xcresult")
    parser.add_argument("--config", default="Scripts/coverage_targets.json")
    parser.add_argument("--markdown-out")
    parser.add_argument("--sonar-out")
    args = parser.parse_args()

    with open(args.config) as handle:
        config = json.load(handle)

    threshold = float(config["threshold"])
    tracked = set(config["files"])

    report = xccov(["view", "--report", "--json", args.xcresult])

    # Flatten every file the report knows about, keyed by repo-relative path.
    files = {}
    target_totals = {}
    for target in report.get("targets", []):
        target_totals[target["name"]] = (
            target.get("coveredLines", 0),
            target.get("executableLines", 0),
        )
        for source in target.get("files", []):
            path = source.get("path", "")
            relative = os.path.relpath(path, os.getcwd()) if os.path.isabs(path) else path
            files[relative] = (
                source.get("coveredLines", 0),
                source.get("executableLines", 0),
            )

    missing = sorted(name for name in tracked if name not in files)
    rows = []
    covered_total = 0
    executable_total = 0
    for name in sorted(tracked):
        if name not in files:
            continue
        covered, executable = files[name]
        covered_total += covered
        executable_total += executable
        rows.append((name, covered, executable, percent(covered, executable)))

    gate = percent(covered_total, executable_total)

    lines = []
    lines.append("## Unit test coverage\n")
    lines.append(f"**Modules under test: {gate:.1f}%** (gate: {threshold:.0f}%)\n")
    lines.append("| File | Covered | Executable | Coverage |")
    lines.append("| --- | ---: | ---: | ---: |")
    for name, covered, executable, pct in rows:
        lines.append(f"| `{name}` | {covered} | {executable} | {pct:.1f}% |")
    lines.append(f"| **Total** | **{covered_total}** | **{executable_total}** | **{gate:.1f}%** |")

    if target_totals:
        lines.append("\n### Whole-target coverage (context only, not gated)\n")
        lines.append("| Target | Coverage |")
        lines.append("| --- | ---: |")
        for name, (covered, executable) in sorted(target_totals.items()):
            lines.append(f"| {name} | {percent(covered, executable):.1f}% |")

    if missing:
        lines.append("\n> **Warning:** these tracked files were absent from the coverage report:")
        for name in missing:
            lines.append(f"> - `{name}`")

    summary = "\n".join(lines)
    print(summary)

    if args.markdown_out:
        with open(args.markdown_out, "w") as handle:
            handle.write(summary + "\n")

    if args.sonar_out:
        # SonarQube generic test-coverage format, so one test run feeds both the
        # CI gate and Sonar. Line detail comes from a per-file xccov archive
        # query, which is why this is only done when Sonar output is requested.
        root = ET.Element("coverage", version="1")
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            covered, executable = files[name]
            if not executable:
                continue
            detail = xccov(["view", "--archive", "--file", name, "--json", args.xcresult])
            file_element = ET.SubElement(root, "file", path=name)
            for line in detail:
                if not line.get("isExecutable"):
                    continue
                ET.SubElement(
                    file_element,
                    "lineToCover",
                    lineNumber=str(line["line"]),
                    covered="true" if line.get("executionCount", 0) > 0 else "false",
                )
        ET.ElementTree(root).write(args.sonar_out, encoding="utf-8", xml_declaration=True)
        print(f"\nWrote Sonar coverage to {args.sonar_out}")

    if missing:
        sys.exit(f"\nFAILED: {len(missing)} tracked file(s) missing from the coverage report.")

    if gate + 1e-9 < threshold:
        sys.exit(f"\nFAILED: coverage {gate:.1f}% is below the {threshold:.0f}% gate.")

    print(f"\nPASSED: coverage {gate:.1f}% meets the {threshold:.0f}% gate.")


if __name__ == "__main__":
    main()
