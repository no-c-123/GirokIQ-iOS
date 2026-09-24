#!/usr/bin/env python3
"""Turn an .xcresult into a Markdown report of the unit tests.

The CI artifacts that hold the raw bundles expire after 14 days, so the
deliverable needs a readable copy that lives in the repository.

Usage: test_report.py <path-to-.xcresult> <output.md>
"""

import json
import re
import subprocess
import sys


def xcresult(path, subcommand):
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", subcommand,
         "--path", path, "--format", "json"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"xcresulttool failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node.get("children", []))


def humanise(name):
    """testFreePlanIsCappedAtThreeNotebooks() -> Free plan is capped at three notebooks

    The split is acronym-aware: it breaks between a lowercase letter and a
    capital, and between a capital and a capital that starts a new word, so
    APIErrors becomes "API errors" rather than "A P I errors".
    """
    name = re.sub(r"\(\)$", "", name)
    name = re.sub(r"^test", "", name)
    spaced = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", name)
    text = spaced.strip()
    return text[:1].upper() + text[1:]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, out = sys.argv[1], sys.argv[2]

    summary = xcresult(path, "summary")
    tests = xcresult(path, "tests")

    suites = {}
    current = None
    for node in walk(tests.get("testNodes", [])):
        kind = node.get("nodeType")
        if kind == "Test Suite":
            current = node.get("name")
            suites.setdefault(current, [])
        elif kind == "Test Case" and current:
            suites[current].append((node.get("name", ""), node.get("result", "")))

    lines = [
        "# Reporte de pruebas unitarias — GirokIQ",
        "",
        f"**Resultado general:** {summary.get('result')}",
        "",
        "| Métrica | Valor |",
        "| --- | ---: |",
        f"| Pruebas ejecutadas | {summary.get('totalTestCount')} |",
        f"| Aprobadas | {summary.get('passedTests')} |",
        f"| Fallidas | {summary.get('failedTests')} |",
        f"| Omitidas | {summary.get('skippedTests')} |",
        "",
        "Generado con `Scripts/test_report.py` a partir del bundle `.xcresult`",
        "producido por `xcodebuild test`.",
        "",
    ]

    for suite in sorted(suites):
        cases = suites[suite]
        if not cases:
            continue
        passed = sum(1 for _, result in cases if result == "Passed")
        lines += [
            f"## {suite}",
            "",
            f"{passed} de {len(cases)} pruebas aprobadas.",
            "",
            "| Prueba | Resultado |",
            "| --- | --- |",
        ]
        for name, result in cases:
            mark = "✅" if result == "Passed" else "❌"
            lines.append(f"| {humanise(name)} | {mark} {result} |")
        lines.append("")

    with open(out, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"Escrito {out}: {summary.get('totalTestCount')} pruebas, "
          f"{len(suites)} suites, resultado {summary.get('result')}")


if __name__ == "__main__":
    main()
