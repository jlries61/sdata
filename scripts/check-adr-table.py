#!/usr/bin/env python3
"""check-adr-table.py -- fail if the ADR summary table at the top of
doc/adrs.md disagrees with the ADR sections below it.

The table is a hand-copied duplicate of each section's heading, date and status.
It drifted twice (six ADRs missing and ten titles reworded, and a heading that
had wrapped onto a second line, which Markdown renders as a paragraph instead of
part of the title), and nothing noticed. This is the same failure class as the
hand-kept test counts removed in ADR-079, but here the summary is useful enough
to keep, so it is checked instead of deleted.

Checks: every `### ADR-NNN:` section has a table row and vice versa; numbering is
contiguous from 001; each row's title equals its heading's; dates agree; the
table's status is a prefix of the section's (the table may be shorter, and a
Markdown link in the section counts as its text); and no heading wraps onto a
second line.

Usage: scripts/check-adr-table.py            (checks doc/adrs.md)
Python 3 stdlib only, like the other scripts here.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ROW = re.compile(r"^\| (ADR-(\d+)) \| (.*?) \| (\S+) \| (.*?) \|\s*$")
HEADING = re.compile(r"^### (ADR-(\d+)): (.*)$")
META = re.compile(r"\*\*Date:\*\*\s*(\S+)\s*\|\s*\*\*Status:\*\*\s*(.*)$")
LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")


def parse(text):
    lines = text.split("\n")
    rows, heads = {}, {}
    for i, line in enumerate(lines):
        m = ROW.match(line)
        if m:
            rows[m[1]] = {"num": int(m[2]), "title": m[3], "date": m[4], "status": m[5]}
            continue
        m = HEADING.match(line)
        if m:
            entry = {"num": int(m[2]), "title": m[3], "date": None, "status": None,
                     "wrapped": False}
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if nxt.strip() and not nxt.startswith("**Date:**"):
                entry["wrapped"] = True
            for later in lines[i + 1:i + 6]:
                meta = META.search(later)
                if meta:
                    entry["date"], entry["status"] = meta[1], LINK.sub(r"\1", meta[2]).strip()
                    break
            heads[m[1]] = entry
    return rows, heads


def check(text):
    rows, heads = parse(text)
    problems = []
    for adr in sorted(set(heads) - set(rows)):
        problems.append(f"{adr}: has a section but is missing from the summary table")
    for adr in sorted(set(rows) - set(heads)):
        problems.append(f"{adr}: is in the summary table but has no heading")
    nums = sorted(h["num"] for h in heads.values())
    if nums != list(range(1, len(nums) + 1)):
        problems.append("ADR numbering is not contiguous from 001")
    for adr in sorted(set(rows) & set(heads)):
        r, h = rows[adr], heads[adr]
        if h["wrapped"]:
            problems.append(f"{adr}: the heading wraps onto a second line (Markdown renders the rest as a paragraph)")
        if r["title"] != h["title"]:
            problems.append(f"{adr}: title differs\n    table:   {r['title']}\n    heading: {h['title']}")
        if h["date"] is None:
            problems.append(f"{adr}: no '**Date:** ... | **Status:** ...' line under the heading")
            continue
        if r["date"] != h["date"]:
            problems.append(f"{adr}: date differs (table {r['date']}, section {h['date']})")
        if not h["status"].startswith(r["status"]):
            problems.append(f"{adr}: status differs (table {r['status']!r}, section {h['status']!r})")
    return problems


def main():
    path = ROOT / "doc" / "adrs.md"
    problems = check(path.read_text())
    if problems:
        print(f"check-adr-table: {len(problems)} problem(s) in {path.relative_to(ROOT)}:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    rows, _ = parse(path.read_text())
    print(f"check-adr-table: OK -- {len(rows)} ADRs, summary table and sections agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
