-- DISPLAY /BY= naming a variable that IS ALSO among the printed columns:
-- sorting by GROUP$ and printing GROUP$ are independent operations that
-- simply happen to reference the same column -- no special handling
-- needed, confirmed by this test (systems-designer review, "already
-- handled, still deserves a test" finding).
USE "tests/data/display_rows.csv"
RUN
DISPLAY GROUP$ /BY=GROUP$
QUIT
