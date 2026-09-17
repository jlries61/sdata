-- List-form (K=3) with every observation excluded (all three crossing
-- variables missing): confirms Print_Ruled_Table's Force_Header_When_Empty
-- path -- the header must still print with zero data rows, matching
-- list-form's pre-ADR-076 behavior exactly (it never had a "no rows to
-- display" message, unlike STATS' own empty-result case).
USE MOCK
LET A$ = ""
LET B$ = ""
LET C$ = ""
RUN
TABLES A$*B$*C$
QUIT
