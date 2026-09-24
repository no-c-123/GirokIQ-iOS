#!/usr/bin/env python3
"""Render a Markdown document to a print-ready PDF.

Exists because the machine has no pandoc, weasyprint or wkhtmltopdf, but does
have Chrome, which prints HTML to PDF well. The Markdown subset handled here is
the one the project's documents actually use: headings, tables with alignment,
lists, emphasis, inline code, links, rules and paragraphs. It is deliberately
not a general Markdown implementation.

Usage:
    markdown_to_pdf.py <input.md> <output.pdf> [--title "..."]
"""

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]

CSS = """
@page { size: A4; margin: 20mm 18mm; }

:root {
  --ink: #16161a;
  --muted: #5b5b66;
  --rule: #d8d8e0;
  --accent: #8a6d2f;
  --code-bg: #f3f3f5;
}

* { box-sizing: border-box; }

body {
  font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
  font-size: 10.5pt;
  line-height: 1.55;
  color: var(--ink);
  margin: 0;
  -webkit-font-smoothing: antialiased;
}

h1, h2, h3, h4 {
  font-family: Georgia, "Times New Roman", serif;
  font-weight: 600;
  line-height: 1.25;
  color: var(--ink);
}

h1 {
  font-size: 23pt;
  margin: 0 0 4pt;
  letter-spacing: -0.2pt;
}

h2 {
  font-size: 14.5pt;
  margin: 22pt 0 8pt;
  padding-bottom: 4pt;
  border-bottom: 1px solid var(--rule);
  /* A heading stranded at the foot of a page reads as a mistake. */
  break-after: avoid;
  break-inside: avoid;
}

h3 {
  font-size: 11.8pt;
  margin: 16pt 0 6pt;
  break-after: avoid;
}

h4 { font-size: 10.8pt; margin: 12pt 0 4pt; break-after: avoid; }

p { margin: 0 0 8pt; orphans: 2; widows: 2; }

strong { font-weight: 650; }

a { color: var(--ink); text-decoration: none; border-bottom: 0.5px solid var(--rule); }

code {
  font-family: "SF Mono", Menlo, Consolas, monospace;
  font-size: 8.8pt;
  background: var(--code-bg);
  padding: 1px 4px;
  border-radius: 3px;
}

hr {
  border: 0;
  border-top: 1px solid var(--rule);
  margin: 18pt 0;
}

ul, ol { margin: 0 0 8pt; padding-left: 16pt; }
li { margin-bottom: 3pt; }

table {
  width: 100%;
  border-collapse: collapse;
  margin: 8pt 0 12pt;
  font-size: 9.3pt;
}

/* A long table is allowed to split rather than leaving a third of a page
   blank, and table-header-group makes the browser repeat the header row on
   each page it continues onto. */
thead { background: #f7f7f9; display: table-header-group; }

th, td {
  border: 0.5px solid var(--rule);
  padding: 4.5pt 6pt;
  text-align: left;
  vertical-align: top;
}

th {
  font-weight: 600;
  font-size: 8.8pt;
  text-transform: uppercase;
  letter-spacing: 0.3pt;
  color: var(--muted);
}

td.right, th.right { text-align: right; }
td.center, th.center { text-align: center; }

.doc-header {
  border-bottom: 2px solid var(--accent);
  padding-bottom: 10pt;
  margin-bottom: 16pt;
}

.doc-header .meta {
  font-size: 9.2pt;
  color: var(--muted);
  line-height: 1.7;
}

/* Long tables are allowed to break, but their rows are not. */
tr { break-inside: avoid; }
"""


def find_chrome():
    for path in CHROME_CANDIDATES:
        if os.path.exists(path):
            return path
    found = shutil.which("chromium") or shutil.which("google-chrome")
    if found:
        return found
    sys.exit("No Chrome-compatible browser found to render the PDF.")


def inline(text):
    """Inline markup. Escaping happens first so the source cannot inject HTML."""
    out = html.escape(text)
    # Code spans first: their contents must not be treated as emphasis.
    placeholders = []

    def stash(match):
        placeholders.append(match.group(1))
        return f"\x00{len(placeholders) - 1}\x00"

    out = re.sub(r"`([^`]+)`", stash, out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", out)

    def restore(match):
        return f"<code>{placeholders[int(match.group(1))]}</code>"

    return re.sub(r"\x00(\d+)\x00", restore, out)


def split_row(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def alignments(separator_cells):
    result = []
    for cell in separator_cells:
        cell = cell.strip()
        if cell.startswith(":") and cell.endswith(":"):
            result.append("center")
        elif cell.endswith(":"):
            result.append("right")
        else:
            result.append("")
    return result


def convert(markdown):
    lines = markdown.split("\n")
    out = []
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        if stripped.startswith("---") and set(stripped) <= {"-"} and len(stripped) >= 3:
            out.append("<hr>")
            i += 1
            continue

        heading = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if heading:
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            i += 1
            continue

        # Table: a header row followed by a separator row.
        if stripped.startswith("|") and i + 1 < len(lines) and re.match(
            r"^\s*\|[\s:\-|]+\|\s*$", lines[i + 1]
        ):
            headers = split_row(stripped)
            aligns = alignments(split_row(lines[i + 1]))
            rows = []
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i].strip()))
                i += 1

            def cell(tag, value, index):
                align = aligns[index] if index < len(aligns) else ""
                attr = f' class="{align}"' if align else ""
                return f"<{tag}{attr}>{inline(value)}</{tag}>"

            head = "".join(cell("th", h, n) for n, h in enumerate(headers))
            body = "".join(
                "<tr>" + "".join(cell("td", c, n) for n, c in enumerate(row)) + "</tr>"
                for row in rows
            )
            out.append(f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>")
            continue

        if re.match(r"^[-*]\s+", stripped):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*]\s+", lines[i]):
                item = re.sub(r"^\s*[-*]\s+", "", lines[i])
                # Join continuation lines belonging to the same bullet.
                i += 1
                while (i < len(lines) and lines[i].strip()
                       and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i])
                       and lines[i].startswith((" ", "\t"))):
                    item += " " + lines[i].strip()
                    i += 1
                items.append(f"<li>{inline(item)}</li>")
            out.append("<ul>" + "".join(items) + "</ul>")
            continue

        if re.match(r"^\d+\.\s+", stripped):
            items = []
            while i < len(lines) and re.match(r"^\s*\d+\.\s+", lines[i]):
                item = re.sub(r"^\s*\d+\.\s+", "", lines[i])
                i += 1
                while (i < len(lines) and lines[i].strip()
                       and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i])
                       and lines[i].startswith((" ", "\t"))):
                    item += " " + lines[i].strip()
                    i += 1
                items.append(f"<li>{inline(item)}</li>")
            out.append("<ol>" + "".join(items) + "</ol>")
            continue

        # Paragraph: consume until a blank line or the start of another block.
        # A line ending in two spaces is Markdown's hard break and is kept,
        # which is what makes a block like the document's title metadata read
        # as separate lines instead of one run-on sentence.
        buffer = [line.rstrip("\n")]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if not nxt or nxt.startswith(("#", "|", "---")) or re.match(r"^([-*]|\d+\.)\s+", nxt):
                break
            buffer.append(lines[i].rstrip("\n"))
            i += 1

        # Join first, THEN apply inline markup. Formatting the lines one by one
        # would break any emphasis that spans a line wrap: "**por\ntarget**"
        # would leave the asterisks visible in the output.
        BREAK = "\x01"
        joined = []
        for n, raw in enumerate(buffer):
            joined.append(raw.strip())
            if raw.endswith("  ") and n < len(buffer) - 1:
                joined.append(BREAK)
        text = " ".join(joined).replace(f" {BREAK} ", BREAK)
        out.append("<p>" + inline(text).replace(BREAK, "<br>") + "</p>")

    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("--title", default=None)
    args = parser.parse_args()

    with open(args.source) as handle:
        markdown = handle.read()

    body = convert(markdown)
    title = args.title or os.path.basename(args.source)

    document = f"""<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8">
<title>{html.escape(title)}</title>
<style>{CSS}</style>
</head><body>{body}</body></html>"""

    with tempfile.TemporaryDirectory() as tmp:
        html_path = os.path.join(tmp, "document.html")
        with open(html_path, "w") as handle:
            handle.write(document)

        output = os.path.abspath(args.output)
        result = subprocess.run(
            [
                find_chrome(),
                "--headless",
                "--disable-gpu",
                "--no-pdf-header-footer",
                f"--print-to-pdf={output}",
                "--virtual-time-budget=4000",
                f"--user-data-dir={os.path.join(tmp, 'profile')}",
                f"file://{html_path}",
            ],
            capture_output=True,
            text=True,
        )

        if not os.path.exists(output):
            sys.exit(f"Chrome did not produce a PDF.\n{result.stderr.strip()}")

    size_kb = os.path.getsize(output) / 1024
    print(f"Wrote {output} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
