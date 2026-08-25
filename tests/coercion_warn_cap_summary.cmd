-- PD-7/ADR-0020 regression (over-cap case): 15 non-numeric-value coercion
-- warnings (audit's own repro shape) must print only the first 10, followed
-- by exactly one suppression-summary line reporting the true suppressed (5)
-- and total (15) counts.
USE "tests/data/coercion_cap_15.csv"
RUN
QUIT
