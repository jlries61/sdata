#!/usr/bin/env python3
"""Unit tests for ssd-archive.py. Fixtures are small inline current.yml
documents in the same shape as the real file (single-quoted, line-folded
`landed:` scalars with doubled apostrophes), so the tests do not depend on the
gitignored .ssd/ tree being present.

Run: python3 scripts/ssd_archive_test.py
"""

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "ssd-archive.py"
spec = importlib.util.spec_from_file_location("ssd_archive", SCRIPT)
sa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sa)

LONG = ("SHIPPED+TAGGED 2026-09-17. The maintainer's note, with an apostrophe. " * 8).strip()

TWO_ACTIVE = """\
schema_version: 2
active:
- slug: alpha
  phase: review
  iteration: null
  started: '2026-09-01T00:00:00Z'
  last_touched: '2026-09-02T00:00:00Z'
  budget_hours: 4
  gate_rounds: 2
  branch: null
  touches:
  - src/a.adb
- slug: beta
  phase: code
  iteration: null
  started: '2026-09-03T00:00:00Z'
  gate_rounds: 0
  branch: add-beta
archived:
- slug: old
  phase: done
  iteration: null
  started: '2026-08-01T00:00:00Z'
  completed: '2026-08-02T00:00:00Z'
  branch: null
  gate_rounds: 1
  landed: 'short note'
"""

FOLDED = ("  landed: 'First sentence here. It''s folded across\n"
          "    several lines, with a second sentence. " + "More words. " * 40 + "'\n")


def with_long_archived():
    return ("schema_version: 2\nactive: []\narchived:\n- slug: big\n  phase: done\n"
            "  iteration: null\n  started: 's'\n  completed: 'c'\n  branch: null\n"
            "  gate_rounds: 1\n" + FOLDED +
            "- slug: small\n  phase: done\n  landed: 'tiny'\n")


class ArchiveTests(unittest.TestCase):

    def test_list_active(self):
        self.assertEqual(sa.list_active(TWO_ACTIVE), ["alpha", "beta"])

    def test_archive_moves_entry_and_keeps_other(self):
        new, note = sa.archive_entry(TWO_ACTIVE, "alpha", "Shipped fine.", "2026-09-19T00:00:00Z")
        self.assertIsNone(note)
        self.assertEqual(sa.list_active(new), ["beta"])
        head, _, _, _, r_body = sa.split_sections(new)
        slugs = [sa.block_slug(b) for b in sa.split_entries(r_body)]
        self.assertEqual(slugs, ["alpha", "old"])          # newest first
        self.assertIn("  phase: done\n", new)
        self.assertIn("  completed: '2026-09-19T00:00:00Z'\n", new)
        self.assertNotIn("last_touched", new)               # active-only fields dropped
        self.assertEqual(sa.count_entries(new), 3)          # nothing lost

    def test_archiving_last_active_leaves_empty_list(self):
        one, _ = sa.archive_entry(TWO_ACTIVE, "alpha", "x", "t")
        two, _ = sa.archive_entry(one, "beta", "x", "t")
        self.assertIn("\nactive: []\n", two)
        self.assertEqual(sa.list_active(two), [])
        self.assertEqual(sa.count_entries(two), 3)

    def test_long_note_is_summarized_and_returned(self):
        new, note = sa.archive_entry(TWO_ACTIVE, "beta", LONG, "t")
        self.assertEqual(note, ("landed.md", " ".join(LONG.split())))
        self.assertIn("[full: features/beta/landed.md]", new)
        self.assertLess(len(new), len(TWO_ACTIVE) + 500)

    def test_apostrophes_survive_round_trip(self):
        new, _ = sa.archive_entry(TWO_ACTIVE, "beta", "It's done, isn't it.", "t")
        self.assertIn("landed: 'It''s done, isn''t it.'", new)

    def test_unknown_slug_is_error(self):
        with self.assertRaises(sa.ArchiveError):
            sa.archive_entry(TWO_ACTIVE, "nope", "x", "t")

    def test_already_archived_is_distinguished(self):
        with self.assertRaises(sa.ArchiveError) as cm:
            sa.archive_entry(TWO_ACTIVE, "old", "x", "t")
        self.assertTrue(str(cm.exception).startswith("already archived"))

    def test_duplicate_archived_key_is_refused(self):
        bad = TWO_ACTIVE + "archived:\n- slug: shadowed\n"
        with self.assertRaises(sa.ArchiveError):
            sa.archive_entry(bad, "alpha", "x", "t")


class SlimTests(unittest.TestCase):

    def test_slim_shortens_only_long_entries(self):
        text = with_long_archived()
        new, moved, warns = sa.slim_archived(text)
        self.assertEqual([m[0] for m in moved], ["big"])
        self.assertEqual(warns, [])
        self.assertIn("landed: 'tiny'", new)
        self.assertIn("[full: features/big/landed.md]", new)
        self.assertLess(len(new), len(text))
        self.assertEqual(sa.count_entries(new), sa.count_entries(text))

    def test_slim_decodes_folded_scalar_and_doubled_quote(self):
        _, moved, _ = sa.slim_archived(with_long_archived())
        full = moved[0][2]
        self.assertTrue(full.startswith("First sentence here. It's folded across several lines"))

    def test_slim_is_idempotent(self):
        once, _, _ = sa.slim_archived(with_long_archived())
        twice, moved, _ = sa.slim_archived(once)
        self.assertEqual(once, twice)
        self.assertEqual(moved, [])

    def test_long_plain_scalar_is_left_alone_with_warning(self):
        text = ("active: []\narchived:\n- slug: plain\n  phase: done\n"
                "  landed: an unquoted plain scalar " + "word " * 80 + "\n")
        new, moved, warns = sa.slim_archived(text)
        self.assertEqual(new, text)
        self.assertEqual(moved, [])
        self.assertEqual(len(warns), 1)

    def test_short_plain_scalar_is_silent(self):
        text = "active: []\narchived:\n- slug: plain\n  landed: sdata main 657aa4e; guard\n"
        new, moved, warns = sa.slim_archived(text)
        self.assertEqual((new, moved, warns), (text, [], []))

    def test_duplicate_slugs_get_distinct_note_files(self):
        one = with_long_archived()
        big = one[one.index("- slug: big"):one.index("- slug: small")]
        text = "schema_version: 2\nactive: []\narchived:\n" + big + big.replace("iteration: null", "iteration: b")
        new, moved, _ = sa.slim_archived(text)
        self.assertEqual([m[1] for m in moved], ["landed.md", "landed-2.md"])
        self.assertIn("features/big/landed-2.md", new)


class CliTests(unittest.TestCase):

    def run_cli(self, ssd, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = sa.main(["--ssd-dir", str(ssd), *args])
        return rc, out.getvalue(), err.getvalue()

    def test_missing_tracker_is_a_quiet_success(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(self.run_cli(d, "--list"), (0, "", ""))
            self.assertEqual(self.run_cli(d, "alpha")[0], 0)

    def test_end_to_end_archive_writes_note_and_backup(self):
        with tempfile.TemporaryDirectory() as d:
            ssd = Path(d)
            (ssd / "current.yml").write_text(TWO_ACTIVE)
            rc, out, _ = self.run_cli(ssd, "alpha", "--landed", LONG,
                                      "--completed", "2026-09-19T00:00:00Z")
            self.assertEqual(rc, 0, out)
            self.assertTrue((ssd / "features" / "alpha" / "landed.md").is_file())
            self.assertEqual((ssd / "current.yml.prev").read_text(), TWO_ACTIVE)
            self.assertEqual(sa.list_active((ssd / "current.yml").read_text()), ["beta"])
            # second run: already archived -> success, no change
            before = (ssd / "current.yml").read_text()
            rc, out, _ = self.run_cli(ssd, "alpha")
            self.assertEqual(rc, 0)
            self.assertIn("already archived", out)
            self.assertEqual((ssd / "current.yml").read_text(), before)

    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            ssd = Path(d)
            (ssd / "current.yml").write_text(TWO_ACTIVE)
            rc, _, _ = self.run_cli(ssd, "alpha", "--dry-run")
            self.assertEqual(rc, 0)
            self.assertEqual((ssd / "current.yml").read_text(), TWO_ACTIVE)
            self.assertFalse((ssd / "current.yml.prev").exists())

    def test_slim_dry_run_then_apply(self):
        with tempfile.TemporaryDirectory() as d:
            ssd = Path(d)
            text = with_long_archived()
            (ssd / "current.yml").write_text(text)
            rc, out, _ = self.run_cli(ssd, "--slim")
            self.assertIn("dry run", out)
            self.assertEqual((ssd / "current.yml").read_text(), text)
            rc, out, _ = self.run_cli(ssd, "--slim", "--apply")
            self.assertEqual(rc, 0)
            self.assertLess(len((ssd / "current.yml").read_text()), len(text))
            self.assertTrue((ssd / "features" / "big" / "landed.md").is_file())
            self.assertEqual(len(list(ssd.glob("current.yml.bak-*"))), 1)

    def test_existing_note_file_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            ssd = Path(d)
            (ssd / "current.yml").write_text(with_long_archived())
            (ssd / "features" / "big").mkdir(parents=True)
            (ssd / "features" / "big" / "landed.md").write_text("mine")
            rc, _, _ = self.run_cli(ssd, "--slim", "--apply")
            self.assertEqual(rc, 0)
            self.assertEqual((ssd / "features" / "big" / "landed.md").read_text(), "mine")
            self.assertTrue((ssd / "features" / "big" / "landed-2.md").is_file())


if __name__ == "__main__":
    unittest.main()
