-- Two-way grid combined with an active BY -- a combination no pre-ADR-076
-- test exercised (tables_by.cmd / tables_save_by.cmd only cover the
-- one-way path under BY). Confirms Put_By_Header's new plain "G$ = p"
-- divider (matching STATS' own format) and the two-way grid's own
-- independently width-computed block, repeat correctly per group.
USE "tests/data/tables_twoway_by.csv"
BY G$
TABLES REGION$*PRODUCT$
QUIT
