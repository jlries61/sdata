#!/usr/bin/env python3
"""Unit tests for check-syntax-doc-sync.py's pure decision logic
(`evaluate`). Fixtures are the real changed-file lists from historical
commits in this repo's own git log -- captured as data, not fetched via a
live git call, so these tests don't depend on repo history being present
or unmutated.

Run: python3 scripts/check_syntax_doc_sync_test.py
"""

import importlib.util
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parent / "check-syntax-doc-sync.py"
spec = importlib.util.spec_from_file_location("check_syntax_doc_sync", SCRIPT_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
evaluate = module.evaluate


class EvaluateTests(unittest.TestCase):

    def test_doc_only_commit_has_nothing_to_check(self):
        # 15d1dc1 "Fix design.md's stale prompt string in sec6.3 (PE-6)":
        # touches design.md only, no trigger-set file -- nothing to gate.
        files = ["doc/design.md"]
        status, detail = evaluate(files, "Fix design.md's stale prompt string\n")
        self.assertEqual(status, "no-trigger")
        self.assertEqual(detail, [])

    def test_parser_change_with_docs_in_same_range_passes(self):
        # A commit range spanning the add-save-decimals PR: d113928 alone
        # ("feat(parser): SAVE /DECIMALS (paren + slash)...") touches only
        # the parser, but 3b38d30 ("docs: SAVE /DECIMALS in HELP, man page,
        # design.md...") lands in the same PR/range -- the union is what
        # the CI gate actually diffs (base..head across the whole push/PR,
        # not commit-by-commit), so this represents that combined range.
        files = [
            "src/parser/sdata-parser.adb",
            "src/sdata-help.adb",
            "man/man1/sdata.1",
            "doc/design.md",
            "tests/interpreter_unit_test.adb",
        ]
        status, detail = evaluate(files, "feat(parser): SAVE /DECIMALS\ndocs: SAVE /DECIMALS in HELP, man page, design.md\n")
        self.assertEqual(status, "ok")
        self.assertEqual(set(detail), {"src/sdata-help.adb", "man/man1/sdata.1", "doc/design.md"})

    def test_parser_only_change_with_no_docs_and_no_trailer_is_stale(self):
        # 130e7a0 "Raise Script_Error from parser instead of print-and-continue
        # (ADR-060)": touched sdata-parser.adb plus CLAUDE.md/CONTRIBUTING.md/
        # SOFTWARE_STANDARDS_REVIEW.md/adrs.md and test fixtures -- none of
        # which are in the required set (HELP/man/design.md). Pushed direct
        # to main as a single commit; under this gate it would have failed.
        files = [
            "CLAUDE.md",
            "CONTRIBUTING.md",
            "doc/SOFTWARE_STANDARDS_REVIEW.md",
            "doc/adrs.md",
            "src/parser/sdata-parser.adb",
            "tests/expected/parse_err_case_conditions.out",
        ]
        status, detail = evaluate(files, "Raise Script_Error from parser instead of print-and-continue (ADR-060)\n")
        self.assertEqual(status, "stale")
        self.assertEqual(detail, ["src/parser/sdata-parser.adb"])

    def test_escape_trailer_skips_an_otherwise_stale_change(self):
        files = ["src/sdata-lexer.adb"]
        messages = (
            "refactor(lexer): extract token-scan helper, no new syntax\n\n"
            "Doc-Sync: not-applicable -- pure internal refactor, no syntax added\n"
        )
        status, detail = evaluate(files, messages)
        self.assertEqual(status, "escaped")
        self.assertEqual(detail, ["src/sdata-lexer.adb"])

    def test_trailer_requires_a_reason_not_just_the_bare_key(self):
        files = ["src/sdata-ast.ads"]
        messages = "some commit\n\nDoc-Sync: not-applicable\n"
        status, _ = evaluate(files, messages)
        self.assertEqual(status, "stale")

    def test_multiple_trigger_files_any_one_required_file_satisfies(self):
        files = ["src/sdata-ast.ads", "src/parser/sdata-parser.adb", "doc/design.md"]
        status, detail = evaluate(files, "feat: new statement kind\n")
        self.assertEqual(status, "ok")
        self.assertEqual(detail, ["doc/design.md"])


if __name__ == "__main__":
    unittest.main()
