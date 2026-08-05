-- Regression test for P12 (design-vs-implementation audit,
-- .ssd/audits/2026-08-03-design-vs-implementation/report.md): re-DIMing an
-- array to a smaller range must retain the in-range elements' values, per
-- design.md §3.5 ("Contraction: Elements outside new range are deleted" --
-- implying elements inside the new range are NOT). Both temporary
-- (Temp_Symbols-backed) and permanent (table-column-backed) real arrays
-- previously lost ALL elements on any re-DIM; permanent arrays were
-- already correctly guarded, temporary arrays were not.
DIM Q(1 TO 5) /TEMP
SET Q(1) = 10
SET Q(5) = 50
PRINT Q(1) Q(5)
RUN
DIM Q(1 TO 3) /TEMP
PRINT Q(1)
RUN

DIM R(1 TO 5)
LET R(1) = 10
LET R(5) = 50
RUN
DIM R(1 TO 3)
PRINT R(1)
RUN
QUIT
