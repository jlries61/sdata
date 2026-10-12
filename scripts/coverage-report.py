#!/usr/bin/env python3
"""Aggregate gcov line-coverage data for sdata + sdata-core.

Run via `make coverage` (see Makefile), which builds both crates with
-fprofile-arcs -ftest-coverage, runs the full test suite against the
instrumented binaries (producing .gcda files in each crate's own obj/
tree -- gcov writes each compiled unit's .gcda next to where it was
*compiled*, so sdata-core's land in ../sdata-core/obj/, not here), then
invokes this script to turn the raw .gcda/.gcno pairs into a readable
per-file + overall summary.

Deliberately prints a report rather than writing a coverage percentage
into any committed doc: ADR-079 established that test counts drift when
quoted in prose and the suite's own output is the only source of truth;
a coverage percentage is the same category of fact and gets the same
treatment here. Re-run `make coverage` for a current number; don't quote
yesterday's.

gcov also reports coverage for GNAT-runtime and generic-instantiation
sources inlined into our object files (Ada.Containers generics, etc.) --
those are filtered out below by requiring the reported path to live
under the crate's own src/ directory, so the percentages reflect this
project's own code, not the runtime it links against.

KNOWN LIMITATION: a .gcda file is processed independently per compiled
unit, so if the SAME source path is reported by more than one .gcda (the
textbook case is a widely-`with`'d .ads whose inline declarations get
compiled into many different .adb object files, each only exercising the
subset its own callers reach), the LAST one processed wins outright --
this does not take the union of covered lines the way a real per-line
merge (e.g. via lcov) would. gcov does not merge across independently-
given .gcda inputs on its own; doing this correctly needs per-line
union logic over the generated .gcov sidecar files, not just summing or
overwriting the summary percentage, and isn't implemented here. Checked
empirically for this codebase: neither crate declares its own generic
packages (only standard-library ones, already excluded by the src/
filter above), so the known-worst case doesn't currently apply -- but a
future widely-shared .ads with partial, caller-dependent coverage could
still be mis-reported. Flagged rather than silently assumed correct;
tighten with a real per-line merge before trusting a borderline
per-file percentage near a decision threshold.
"""
import os
import re
import subprocess

SDATA_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SDATA_CORE_ROOT = os.path.abspath(os.path.join(SDATA_ROOT, "..", "sdata-core"))

CRATES = [
    ("sdata", os.path.join(SDATA_ROOT, "obj"), os.path.join(SDATA_ROOT, "src")),
    ("sdata-core", os.path.join(SDATA_CORE_ROOT, "obj"), os.path.join(SDATA_CORE_ROOT, "src")),
]


def find_gcda_dirs(obj_root):
    """Directories directly containing .gcda files under obj_root.

    Walked rather than assumed at a fixed depth: the root crate's own
    objects land directly in obj/, while a dependency crate (built in
    whatever profile Alire picked -- release by default, development if
    requested) gets an obj/<profile>/ subdirectory. Don't hardcode which.
    """
    dirs = []
    for dirpath, _dirnames, filenames in os.walk(obj_root):
        if any(f.endswith(".gcda") for f in filenames):
            dirs.append(dirpath)
    return dirs


def collect(obj_root, src_root):
    src_root = os.path.abspath(src_root)
    results = {}
    for obj_dir in find_gcda_dirs(obj_root):
        gcdas = [f for f in os.listdir(obj_dir) if f.endswith(".gcda")]
        generated_gcov = []
        for gcda in gcdas:
            proc = subprocess.run(
                ["gcov", "-b", gcda], cwd=obj_dir, capture_output=True, text=True
            )
            for block in proc.stdout.split("File '")[1:]:
                path = block[: block.index("'")]
                m = re.search(r"Lines executed:([\d.]+)% of (\d+)", block)
                if not m:
                    continue
                pct, total = float(m.group(1)), int(m.group(2))
                if not os.path.abspath(path).startswith(src_root):
                    continue
                executed = round(pct / 100.0 * total)
                results[path] = (executed, total)
        # gcov writes a .gcov sidecar per source file it touched, including
        # the GNAT-runtime ones filtered out above -- clean up so repeated
        # `make coverage` runs don't accumulate hundreds of stale files in
        # an already-gitignored but still-real directory.
        for f in os.listdir(obj_dir):
            if f.endswith(".gcov"):
                os.remove(os.path.join(obj_dir, f))
    return results


def report(name, results, rel_to):
    if not results:
        print(f"{name}: no coverage data found -- did `make coverage` run first?")
        return 0, 0
    tot_exec = sum(e for e, _ in results.values())
    tot_lines = sum(t for _, t in results.values())
    pct = 100.0 * tot_exec / tot_lines if tot_lines else 0.0
    print(f"\n=== {name}: {tot_exec}/{tot_lines} lines ({pct:.1f}%) "
          f"across {len(results)} files ===")
    for path, (e, t) in sorted(results.items(), key=lambda kv: kv[1][0] / kv[1][1]):
        p = 100.0 * e / t if t else 0.0
        rel = os.path.relpath(path, rel_to)
        print(f"  {p:5.1f}%  {e:5d}/{t:<5d}  {rel}")
    return tot_exec, tot_lines


def main():
    grand_exec = grand_lines = 0
    for name, obj_root, src_root in CRATES:
        results = collect(obj_root, src_root)
        e, t = report(name, results, src_root)
        grand_exec += e
        grand_lines += t
    if grand_lines:
        print(f"\n=== Combined: {grand_exec}/{grand_lines} lines "
              f"({100.0 * grand_exec / grand_lines:.1f}%) ===")
    else:
        print("\nNo coverage data found in either crate. Run `make coverage`.")


if __name__ == "__main__":
    main()
