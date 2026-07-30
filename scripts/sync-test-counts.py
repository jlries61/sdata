#!/usr/bin/env python3
"""sync-test-counts.py -- keep the hand-maintained test-count prose in
CLAUDE.md, CONTRIBUTING.md, and doc/SOFTWARE_STANDARDS_REVIEW.md synced
with what `make check` (and the sibling crates' own suites) actually
report.

This exact drift has recurred three times (see the dated history rows in
SOFTWARE_STANDARDS_REVIEW.md's Test Coverage section, which this script
deliberately does NOT touch -- they're a log of past catches, not living
data). This script is the fix: regex-substitute only the numbers in known,
fixed-prose locations, so it works correctly the next time counts drift
too, not just this once.

Usage:
    scripts/sync-test-counts.py           # rewrite the tracked locations
    scripts/sync-test-counts.py --check   # verify only; exit 1 if stale

Python 3 stdlib only, matching this ecosystem's scripts/gen-reference.py
convention. Assumes bin/ is already built (`make build`/`make check`) for
sdata's own counts. The sibling crates (../sdata-core, ../data-vandal) are
optional: if either isn't checked out, its count is skipped with a warning
rather than failing -- CI for this repo alone never has those siblings,
only a local dev checkout following this ecosystem's usual layout does.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

UNIT_DRIVERS = [
    ("csv_unit_test", "csv"),
    ("sdata_unit_test", "sdata"),
    ("evaluator_unit_test", "eval"),
    ("file_io_unit_test", "fileio"),
    ("interpreter_unit_test", "interp"),
]

CORE_DRIVERS = [
    "values_tests", "parse_expression_tests", "call_function_tests",
    "aggregate_meta_test", "aggregate_exec_test", "transpose_test",
    "stats_test", "statistics_tests", "commands_tests",
]


def count_passed(binary: Path) -> int:
    """Parses "N passed, 0 failed." (digits precede "passed") or
    "Passed: N  Failed: 0" (digits follow "Passed:") -- the two formats
    actually in use across sdata's and sdata-core's unit drivers."""
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    matches = re.findall(r"(\d+)\s+passed\b|[Pp]assed:\s+(\d+)", output)
    if not matches:
        sys.exit(f"error: could not parse a pass count from {binary}\n"
                  f"  tail of output: {output[-300:]!r}")
    last = matches[-1]
    return int(last[0] or last[1])


def gather_counts():
    integration = len(list((ROOT / "tests").glob("*.cmd")))

    unit_counts = {}
    for binary_name, key in UNIT_DRIVERS:
        path = ROOT / "bin" / binary_name
        if not path.exists():
            sys.exit(f"error: {path} not built -- run `make build` first")
        unit_counts[key] = count_passed(path)
    unit_total = sum(unit_counts.values())
    breakdown = "/".join(str(unit_counts[key]) for _, key in UNIT_DRIVERS)

    core_total = None
    core_root = ROOT.parent / "sdata-core"
    if (core_root / "tests").is_dir():
        subprocess.run(
            ["alr", "exec", "--", "gprbuild", "-q", "-p",
             "-P", "tests/sdata_core_tests.gpr"],
            cwd=core_root, capture_output=True)
        missing = []
        total = 0
        for driver in CORE_DRIVERS:
            path = core_root / "tests" / "bin" / driver
            if not path.exists():
                missing.append(driver)
                continue
            total += count_passed(path)
        if missing:
            print(f"warning: sdata-core drivers not built, skipping its count: "
                  f"{missing}", file=sys.stderr)
        else:
            core_total = total
    else:
        print("warning: ../sdata-core not checked out -- skipping its count",
              file=sys.stderr)

    vandal_total = None
    vandal_root = ROOT.parent / "data-vandal"
    if (vandal_root / "tests").is_dir():
        vandal_total = len(list((vandal_root / "tests").glob("*.cmd")))
    else:
        print("warning: ../data-vandal not checked out -- skipping its count",
              file=sys.stderr)

    return {
        "integration": integration,
        "unit_total": unit_total,
        "unit_counts": unit_counts,
        "breakdown": breakdown,
        "core_total": core_total,
        "vandal_total": vandal_total,
    }


# Each rule: (file relative to ROOT, compiled regex, replacement-fn(match) -> str, label).
# Regexes anchor on FIXED surrounding prose, capturing only the numbers, so
# this keeps working correctly the next time counts drift -- not just today.
def build_rules(c):
    I = c["integration"]
    U = c["unit_total"]
    uc = c["unit_counts"]
    rules = []

    claude = "CLAUDE.md"
    rules.append((claude,
        re.compile(r"\d+ `\.cmd` integration tests in `tests/` \(\d+ unit checks total\)"),
        lambda m: f"{I} `.cmd` integration tests in `tests/` ({U} unit checks total)",
        "driver-list summary"))
    rules.append((claude,
        re.compile(r"(`bin/csv_unit_test` — `SData_Core\.CSV` functions \()\d+(\))"),
        lambda m: f"{m.group(1)}{uc['csv']}{m.group(2)}",
        "csv_unit_test count"))
    rules.append((claude,
        re.compile(r"(`bin/sdata_unit_test` — `SData_Core\.Table` / `Variables` / "
                   r"transient-table / merge / PDV \()\d+(\))"),
        lambda m: f"{m.group(1)}{uc['sdata']}{m.group(2)}",
        "sdata_unit_test count"))
    rules.append((claude,
        re.compile(r"(`bin/evaluator_unit_test` — expression evaluator \()\d+(\))"),
        lambda m: f"{m.group(1)}{uc['eval']}{m.group(2)}",
        "evaluator_unit_test count"))
    rules.append((claude,
        re.compile(r"(`bin/file_io_unit_test` — CSV/ODF/OOXML read-write \()\d+(\))"),
        lambda m: f"{m.group(1)}{uc['fileio']}{m.group(2)}",
        "file_io_unit_test count"))
    rules.append((claude,
        re.compile(r"(`bin/interpreter_unit_test` — control flow / SELECT / REPEAT \()\d+(\))"),
        lambda m: f"{m.group(1)}{uc['interp']}{m.group(2)}",
        "interpreter_unit_test count"))
    rules.append((claude,
        re.compile(r"All \d+ integration tests must pass before committing\."),
        lambda m: f"All {I} integration tests must pass before committing.",
        "'all N integration tests' line"))
    if c["vandal_total"] is not None:
        V = c["vandal_total"]
        rules.append((claude,
            re.compile(r"(`make check` \(sdata, )\d+( integration tests\))"),
            lambda m: f"{m.group(1)}{I}{m.group(2)}",
            "cross-crate gate line (sdata)"))
        rules.append((claude,
            re.compile(r"(data-vandal && make check` \(data-vandal, )\d+( integration tests\))"),
            lambda m: f"{m.group(1)}{V}{m.group(2)}",
            "cross-crate gate line (data-vandal)"))
    rules.append((claude,
        re.compile(r"(integration test scripts \()\d+(\))"),
        lambda m: f"{m.group(1)}{I}{m.group(2)}",
        "source-layout comment"))
    rules.append((claude,
        re.compile(r"\d+ integration tests, \d+ unit checks across 5 modules"),
        lambda m: f"{I} integration tests, {U} unit checks across 5 modules",
        "phase-status line"))

    contrib = "CONTRIBUTING.md"
    rules.append((contrib,
        re.compile(r"(followed by )\d+( integration tests\.)"),
        lambda m: f"{m.group(1)}{I}{m.group(2)}",
        "lead-in sentence"))
    rules.append((contrib,
        re.compile(r"All \d+ tests passed\."),
        lambda m: f"All {I} tests passed.",
        "sample output block"))

    review = "doc/SOFTWARE_STANDARDS_REVIEW.md"
    rules.append((review,
        re.compile(r"(\| Integration `\.cmd` \| \*\*)\d+(\*\* \|)"),
        lambda m: f"{m.group(1)}{I}{m.group(2)}",
        "coverage table: integration row"))
    rules.append((review,
        re.compile(r"(\| `csv_unit_test` \| )\d+( \|)"),
        lambda m: f"{m.group(1)}{uc['csv']}{m.group(2)}",
        "coverage table: csv row"))
    rules.append((review,
        re.compile(r"(\| `sdata_unit_test` \(Table/Variables/PDV/transient/merge\) \| )\d+( \|)"),
        lambda m: f"{m.group(1)}{uc['sdata']}{m.group(2)}",
        "coverage table: sdata row"))
    rules.append((review,
        re.compile(r"(\| `evaluator_unit_test` \| )\d+( \|)"),
        lambda m: f"{m.group(1)}{uc['eval']}{m.group(2)}",
        "coverage table: evaluator row"))
    rules.append((review,
        re.compile(r"(\| `file_io_unit_test` \| )\d+( \|)"),
        lambda m: f"{m.group(1)}{uc['fileio']}{m.group(2)}",
        "coverage table: file_io row"))
    rules.append((review,
        re.compile(r"(\| `interpreter_unit_test` \| )\d+( \|)"),
        lambda m: f"{m.group(1)}{uc['interp']}{m.group(2)}",
        "coverage table: interpreter row"))
    rules.append((review,
        re.compile(r"(\| \*\*Unit total\*\* \| \*\*)\d+(\*\* \|)"),
        lambda m: f"{m.group(1)}{U}{m.group(2)}",
        "coverage table: unit total row"))
    # These three sentences wrap across markdown source lines, so the fixed
    # prose either side of the number is joined with \s+ (matches a real
    # space or the newline the wrap introduces), not a literal space.
    rules.append((review,
        re.compile(r"(CI runs all unit suites \+)\s+\d+(\s+integration tests)"),
        lambda m: f"{m.group(1)} {I}{m.group(2)}",
        "narrative: CI line"))
    if c["vandal_total"] is not None:
        V = c["vandal_total"]
        rules.append((review,
            re.compile(r"(data-vandal\s+carries its own)\s+\d+(\s+integration tests)"),
            lambda m: f"{m.group(1)} {V}{m.group(2)}",
            "narrative: data-vandal line"))
    if c["core_total"] is not None:
        CORE = c["core_total"]
        rules.append((review,
            re.compile(r"(sdata-core\s+carries)\s+\d+(\s+in-crate assertions across)\s+\w+(\s+drivers)"),
            lambda m: f"{m.group(1)} {CORE}{m.group(2)} {len(CORE_DRIVERS)}{m.group(3)}",
            "narrative: sdata-core line"))

    return rules


def apply_rules(rules, check_only: bool) -> bool:
    stale = False
    by_file = {}
    for rel, pattern, replace, label in rules:
        by_file.setdefault(rel, []).append((pattern, replace, label))

    for rel, file_rules in by_file.items():
        path = ROOT / rel
        text = path.read_text()
        original = text
        for pattern, replace, label in file_rules:
            new_text, n = pattern.subn(replace, text)
            if n == 0:
                print(f"warning: pattern for {rel!r} ({label}) matched nothing "
                      f"-- prose may have moved; check manually", file=sys.stderr)
            elif new_text != text:
                if check_only:
                    print(f"STALE: {rel} -- {label}", file=sys.stderr)
                    stale = True
                text = new_text
        if not check_only and text != original:
            path.write_text(text)
            print(f"updated: {rel}")

    return stale


def main():
    check_only = "--check" in sys.argv[1:]
    counts = gather_counts()
    rules = build_rules(counts)
    stale = apply_rules(rules, check_only)

    print()
    print("Actual counts (source of truth):")
    print(f"  sdata integration:   {counts['integration']}")
    print(f"  sdata unit:          {counts['unit_total']} ({counts['breakdown']})")
    print(f"  sdata-core in-crate: {counts['core_total'] if counts['core_total'] is not None else '<skipped>'}")
    print(f"  data-vandal:         {counts['vandal_total'] if counts['vandal_total'] is not None else '<skipped>'}")

    if check_only and stale:
        print("\nTest-count references are stale. "
              "Run scripts/sync-test-counts.py to fix.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
