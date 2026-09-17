-- /FIRST=0: header + rule + rule with zero data rows -- ADR-069's existing
-- empty-table shape, preserved exactly (ADR-078 must not add a separate
-- "empty order" message here).
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=0
QUIT
