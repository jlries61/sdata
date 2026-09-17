-- Two-way grid: per-column width scoping must NOT leak across columns
-- (ADR-076 Risk Assessment / 02-systems-designer.md's incremental risk).
-- B$=x's column legitimately needs width 9 (RowPct(p,x) = 100.00000, since
-- row p has no B$=y data at all); B$=y's column never exceeds width 8 (no
-- cell in that column reaches a 3-digit integer part). A wrong,
-- globally-shared width model would widen B$=y's column to 9 too; the
-- correct, per-column model keeps it at 8 -- hand-computed, not just
-- re-run-and-eyeballed.
USE "tests/data/tables_twoway_asymmetric_width.csv"
TABLES A$*B$
QUIT
