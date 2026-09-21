#!/usr/bin/env python3
"""Unit tests for check-adr-table.py's pure logic (`check`). Fixtures are small
inline adrs.md documents so the tests do not depend on the real file.

Run: python3 scripts/check_adr_table_test.py
"""

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-adr-table.py"
spec = importlib.util.spec_from_file_location("check_adr_table", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

GOOD = """\
# Architecture Decision Records

## Summary

| # | Title | Date | Status |
|---|---|---|---|
| ADR-001 | First decision | 2026-01-01 | Accepted |
| ADR-002 | Second decision | 2026-01-02 | Superseded by ADR-003 |
| ADR-003 | Third decision | 2026-01-03 | Accepted |

---

### ADR-001: First decision

**Date:** 2026-01-01 | **Status:** Accepted

Body.

### ADR-002: Second decision

**Date:** 2026-01-02 | **Status:** Superseded by [ADR-003](#adr-003-third-decision)

### ADR-003: Third decision

**Date:** 2026-01-03 | **Status:** Accepted (with a long note)
"""


class CheckTests(unittest.TestCase):

    def test_consistent_document_has_no_problems(self):
        self.assertEqual(mod.check(GOOD), [])

    def test_adr_missing_from_table(self):
        text = GOOD.replace("| ADR-003 | Third decision | 2026-01-03 | Accepted |\n", "")
        problems = mod.check(text)
        self.assertTrue(any("ADR-003" in p and "missing from the summary table" in p for p in problems), problems)

    def test_row_without_a_heading(self):
        text = GOOD.replace("| ADR-003 |", "| ADR-004 |", 1)
        problems = mod.check(text)
        self.assertTrue(any("ADR-004" in p and "no heading" in p for p in problems), problems)

    def test_title_mismatch(self):
        text = GOOD.replace("| ADR-002 | Second decision |", "| ADR-002 | A different title |")
        problems = mod.check(text)
        self.assertTrue(any("ADR-002" in p and "title" in p for p in problems), problems)

    def test_date_mismatch(self):
        text = GOOD.replace("| ADR-001 | First decision | 2026-01-01 |", "| ADR-001 | First decision | 2026-02-02 |")
        problems = mod.check(text)
        self.assertTrue(any("ADR-001" in p and "date" in p for p in problems), problems)

    def test_status_mismatch(self):
        text = GOOD.replace("| 2026-01-03 | Accepted |", "| 2026-01-03 | Rejected |")
        problems = mod.check(text)
        self.assertTrue(any("ADR-003" in p and "status" in p for p in problems), problems)

    def test_short_table_status_is_allowed_for_a_longer_body_status(self):
        # ADR-002's table says "Superseded by ADR-003"; the body links it. Not a problem.
        self.assertEqual([p for p in mod.check(GOOD) if "ADR-002" in p], [])

    def test_numbering_gap(self):
        text = GOOD.replace("ADR-003", "ADR-005")
        problems = mod.check(text)
        self.assertTrue(any("not contiguous" in p for p in problems), problems)

    def test_heading_wrapped_onto_a_second_line(self):
        # A heading that wraps renders as a heading plus a paragraph, so the
        # rest of the title is lost (this happened to ADR-057).
        text = GOOD.replace("### ADR-002: Second decision\n", "### ADR-002: Second\ndecision\n")
        problems = mod.check(text)
        self.assertTrue(any("ADR-002" in p for p in problems), problems)

    def test_the_real_file_is_consistent(self):
        real = (Path(__file__).resolve().parent.parent / "doc" / "adrs.md").read_text()
        self.assertEqual(mod.check(real), [])


if __name__ == "__main__":
    unittest.main()
