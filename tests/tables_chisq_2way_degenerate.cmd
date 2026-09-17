-- TABLES /CHISQ (2-way) when the crossing variable has only one observed
-- level (DF = 0): Chi_Square_Tests' own degenerate guard returns
-- Valid = False, and the "(chi-square not computed: ...)" message prints
-- instead of a statistics table. Pre-ADR-076, this branch was completely
-- untested even though it's easy to trigger (any 2-way /CHISQ where one
-- crossing variable happens to have a single distinct value); adding
-- coverage since ADR-076 touched this exact print path (the header line
-- is now printed inside the invalid branch instead of unconditionally
-- before the validity check, though the resulting text is identical).
USE "tests/data/tables_chisq_2way_degenerate.csv"
TABLES A$*B$ /CHISQ
QUIT
