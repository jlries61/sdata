-- Bare DISPLAY (no explicit column list) combined with /FIRST=: the
-- systems-designer review's own blocking finding -- Execute_Metadata's
-- early-return to Display_All_Columns for a null Stmt.Display_Vars must
-- still thread /FIRST=/LAST=/BY= through, not silently ignore them.
USE "tests/data/display_rows.csv"
RUN
DISPLAY /FIRST=2
QUIT
