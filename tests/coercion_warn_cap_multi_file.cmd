-- PD-7/ADR-0020 regression (multi-file scope): a positional two-file USE
-- merge where each source independently has 15 coercion warnings (column A
-- in file 1, column C in file 2). The cap and its counter are per-source
-- Parse_CSV call, so each file must produce its OWN independent 10-warning
-- cap + summary line (20 warnings + 2 summaries total), not one combined
-- 15-warning count shared across both files.
USE "tests/data/coercion_cap_multi1.csv", "tests/data/coercion_cap_multi2.csv"
RUN
QUIT
