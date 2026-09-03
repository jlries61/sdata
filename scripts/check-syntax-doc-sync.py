#!/usr/bin/env python3
"""check-syntax-doc-sync.py -- fail if a commit that changes sdata's
statement-kind-defining files (AST / parser / lexer) doesn't also update
the user-facing doc set (HELP text, man page, design.md) in the same
change.

This is the semantic-content analogue of scripts/sync-test-counts.py,
which already does this for *numeric* test-count prose. CLAUDE.md's
"Keeping the user-facing surface in sync" section states the rule this
script enforces; doc/design.md (+ doc/adrs.md) is the source of truth
those three doc files are checked *against* when they disagree with each
other, per CLAUDE.md's "Conflict resolution" paragraph -- but this script
only checks *presence* (were the docs touched at all), not correctness,
which no path-based heuristic can safely judge.

This makes drift visible on the triggering push; it does not and cannot
block a merge to main (no branch protection exists on this repo -- see
.ssd/milestones/2026-09-03-post-pe-audit-remediation/systems-designer-r1.md).
That's the same honest trade-off scripts/sync-test-counts.py already makes.

Usage:
    scripts/check-syntax-doc-sync.py

    Diffs $DOC_SYNC_BASE_SHA..$DOC_SYNC_HEAD_SHA (both from the
    environment, set by CI -- see .github/workflows/test.yml). Locally,
    with neither set, defaults to HEAD~1..HEAD.

Escape hatch: a commit message trailer of the form
    Doc-Sync: not-applicable -- <reason>
anywhere in the diffed commit range skips the check (logged, not silent)
for non-syntax changes to the trigger-set files (e.g. internal parser
refactors, bug fixes that add no new syntax). This is an audit trail for
the next periodic milestone review (feynman / codebase-skeptic), not a
continuously-enforced claim -- code-reviewer does not run on every push
in this repo's actual direct-push-to-main workflow.

Python 3 stdlib only, matching this ecosystem's scripts/gen-reference.py
and scripts/sync-test-counts.py convention.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Files where a new statement kind, literal syntax, or keyword is added.
TRIGGER_SET = [
    "src/sdata-ast.ads",
    "src/sdata-ast.adb",
    "src/parser/sdata-parser.adb",
    "src/sdata-lexer.adb",
]

# The user-facing surface CLAUDE.md requires to stay in sync with the above.
REQUIRED_SET = [
    "src/sdata-help.adb",
    "man/man1/sdata.1",
    "doc/design.md",
]

TRAILER_RE = re.compile(r"^Doc-Sync:\s*not-applicable\s*[-—]\s*\S.*$", re.MULTILINE)


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"error: git {' '.join(args)} failed:\n{result.stderr}")
    return result.stdout


def resolve_range() -> tuple[str, str]:
    base = os.environ.get("DOC_SYNC_BASE_SHA", "").strip()
    head = os.environ.get("DOC_SYNC_HEAD_SHA", "").strip() or "HEAD"

    # Local runs, and GitHub's all-zeros placeholder for "branch created"
    # push events, both fall back to the last commit.
    if not base or set(base) == {"0"}:
        base = "HEAD~1"

    # A shallow checkout, a base SHA from a history this clone doesn't have
    # (force-push, fork), or any other resolution failure: fail safe to
    # HEAD~1 rather than crashing the check outright.
    check = subprocess.run(["git", "cat-file", "-e", base], cwd=ROOT,
                            capture_output=True)
    if check.returncode != 0:
        print(f"warning: base {base!r} not found in this checkout, "
              f"falling back to HEAD~1", file=sys.stderr)
        base = "HEAD~1"

    return base, head


def changed_files(base: str, head: str) -> list[str]:
    out = git("diff", "--name-only", f"{base}..{head}")
    return [line.strip() for line in out.splitlines() if line.strip()]


def commit_messages(base: str, head: str) -> str:
    return git("log", "--format=%B%x00", f"{base}..{head}")


def has_escape_trailer(messages: str) -> bool:
    return bool(TRAILER_RE.search(messages))


# Pure decision logic, deliberately separated from the git I/O above so it
# can be unit-tested against fixture data (tests/check_syntax_doc_sync_test.py)
# without a live git call or real repo history.
def evaluate(files: list[str], messages: str) -> tuple[str, list[str]]:
    """Returns (status, detail) where status is one of:
    "no-trigger" (nothing to check), "ok" (docs updated), "escaped"
    (trailer present), "stale" (docs missing, no trailer). `detail` is
    the triggered file list for "ok"/"escaped"/"stale", empty for
    "no-trigger"."""
    triggered = [f for f in files if f in TRIGGER_SET]
    satisfied = [f for f in files if f in REQUIRED_SET]

    if not triggered:
        return "no-trigger", []
    if satisfied:
        return "ok", satisfied
    if has_escape_trailer(messages):
        return "escaped", triggered
    return "stale", triggered


def main() -> None:
    base, head = resolve_range()
    files = changed_files(base, head)
    messages = commit_messages(base, head)

    status, detail = evaluate(files, messages)

    if status == "no-trigger":
        print("check-syntax-doc-sync: no statement-kind-defining files "
              "changed, skipping.")
        return

    if status == "ok":
        triggered = [f for f in files if f in TRIGGER_SET]
        print(f"check-syntax-doc-sync: OK -- {', '.join(detail)} "
              f"updated alongside {', '.join(triggered)}.")
        return

    if status == "escaped":
        print("check-syntax-doc-sync: SKIPPED (Doc-Sync: not-applicable "
              f"trailer present) -- {', '.join(detail)} changed with no "
              "doc update. Logged for the next milestone audit to "
              "spot-check.", file=sys.stderr)
        return

    # status == "stale"
    print("STALE: syntax-defining file(s) changed with no corresponding "
          "doc update.", file=sys.stderr)
    print(f"  Changed (trigger set):   {', '.join(detail)}", file=sys.stderr)
    print(f"  Required (none touched): {', '.join(REQUIRED_SET)}", file=sys.stderr)
    print(file=sys.stderr)
    print("If this really isn't a syntax change (e.g. an internal parser "
          "refactor), add a trailer to the commit message:", file=sys.stderr)
    print('  Doc-Sync: not-applicable -- <reason>', file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
