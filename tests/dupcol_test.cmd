-- PD-5/ADR-0018 regression: a duplicate column name in a CSV header must
-- warn (design.md sec4.2/USE sec7.1's documented "last occurrence wins,
-- warning issued" -- the warning half was never implemented before this
-- fix) while still correctly letting the last occurrence win the data.
USE "tests/data/dupcol.csv"
RUN
DISPLAY
QUIT
